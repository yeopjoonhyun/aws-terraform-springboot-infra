# ECS 클러스터: 컨테이너들을 묶어 관리하는 단위. Fargate라 서버(EC2)는 직접 만들지 않는다.
resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"
}

# 앱 로그를 모으는 곳. 실습용이라 7일만 보관해 저장 요금을 줄인다.
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.project_name}-app"
  retention_in_days = 7
}

# 실행 역할: ECS가 "컨테이너를 띄우기 위해" 쓰는 권한 (ECR에서 이미지 받기, 로그 쓰기)
resource "aws_iam_role" "task_execution" {
  name = "${var.project_name}-task-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "task_execution" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# 컨테이너를 띄울 때 ECS가 DB 비밀을 꺼내 환경 변수로 넣는다. 그 비밀 하나만 읽을 수 있게 허용한다.
# (비밀은 RDS 기본 키 aws/secretsmanager로 암호화되어 있어 KMS 권한은 따로 필요 없다)
resource "aws_iam_role_policy" "task_execution_db_secret" {
  name = "read-db-secret"
  role = aws_iam_role.task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "secretsmanager:GetSecretValue"
      Resource = local.db.db_secret_arn
    }]
  })
}

# 작업 정의: "어떤 이미지를, 얼마만큼의 CPU·메모리로, 어떻게 실행할지" 적은 설계도
resource "aws_ecs_task_definition" "app" {
  family                   = "${var.project_name}-app"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_vcpu * 1024
  memory                   = var.task_vcpu * 2048 # Fargate 최소 메모리: 0.5 또는 1 GiB
  execution_role_arn       = aws_iam_role.task_execution.arn

  # 이미지를 Apple Silicon(arm64)에서 빌드했으므로 ARM64로 실행한다. x86보다 시간당 약 20% 저렴하다.
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  container_definitions = jsonencode([{
    name         = "app"
    image        = "${local.registry.ecr_repository_url}:${var.image_tag}"
    essential    = true
    portMappings = [{ containerPort = var.app_port, protocol = "tcp" }]

    # 비밀이 아닌 설정값. prod 프로필이 켜지면 application-prod.yml이 이 값으로 MySQL에 접속한다.
    environment = [
      { name = "SPRING_PROFILES_ACTIVE", value = "prod" },
      { name = "DB_HOST", value = local.db.db_host },
      { name = "DB_NAME", value = local.db.db_name },
    ]

    # 비밀값. 작업 정의에는 위치(ARN)만 적고, 실제 값은 시작할 때 ECS가 Secrets Manager에서 꺼낸다.
    # "ARN:키::" 는 비밀(JSON) 안의 username, password 칸을 하나씩 꺼내라는 뜻이다.
    secrets = [
      { name = "DB_USERNAME", valueFrom = "${local.db.db_secret_arn}:username::" },
      { name = "DB_PASSWORD", valueFrom = "${local.db.db_secret_arn}:password::" },
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.app.name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "app"
      }
    }
  }])
}

# 서비스: 작업(컨테이너)을 항상 원하는 개수만큼 유지하고, ALB 대상 그룹에 자동으로 등록한다
resource "aws_ecs_service" "app" {
  name                          = "${var.project_name}-app"
  cluster                       = aws_ecs_cluster.main.id
  task_definition               = aws_ecs_task_definition.app.arn
  desired_count                 = 2
  launch_type                   = "FARGATE"
  availability_zone_rebalancing = "ENABLED"

  # 앱이 뜨는 동안(JVM 기동) ALB 헬스체크 실패로 컨테이너가 교체되지 않도록 기다려 준다
  health_check_grace_period_seconds = 120

  network_configuration {
    subnets          = local.net.private_app_subnet_ids
    security_groups  = [local.net.security_group_ids["app"]]
    assign_public_ip = false # 프라이빗 서브넷: 공인 IP 없이 NAT로만 나간다
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "app"
    container_port   = var.app_port
  }

  lifecycle {
    # 처음에는 2개로 시작하고, 이후 작업 수는 Application Auto Scaling이 관리한다.
    ignore_changes = [desired_count]
  }

  # 대상 그룹이 ALB에 연결되고, 프라이빗 서브넷에서 NAT로 나가는 길이 생긴 뒤에 서비스를 만들어야 한다
  # (길이 없으면 ECR에서 이미지를 받지 못해 작업이 시작되지 못한다)
  # 비밀을 읽는 권한이 붙기 전에 작업이 시작되면 비밀을 못 꺼내 실패하므로 그것도 기다린다
  depends_on = [aws_lb_listener.http, aws_route.private_app_nat, aws_iam_role_policy.task_execution_db_secret]
}
