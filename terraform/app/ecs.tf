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

# 작업 정의: "어떤 이미지를, 얼마만큼의 CPU·메모리로, 어떻게 실행할지" 적은 설계도
resource "aws_ecs_task_definition" "app" {
  family                   = "${var.project_name}-app"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256 # 0.25 vCPU (Fargate 최소)
  memory                   = 512 # 0.5 GB
  execution_role_arn       = aws_iam_role.task_execution.arn

  # 이미지를 Apple Silicon(arm64)에서 빌드했으므로 ARM64로 실행한다. x86보다 시간당 약 20% 저렴하다.
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  container_definitions = jsonencode([{
    name         = "app"
    image        = "${aws_ecr_repository.app.repository_url}:${var.image_tag}"
    essential    = true
    portMappings = [{ containerPort = var.app_port, protocol = "tcp" }]

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
  name            = "${var.project_name}-app"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 1
  launch_type     = "FARGATE"

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

  # 대상 그룹이 ALB에 연결되고, 프라이빗 서브넷에서 NAT로 나가는 길이 생긴 뒤에 서비스를 만들어야 한다
  # (길이 없으면 ECR에서 이미지를 받지 못해 작업이 시작되지 못한다)
  depends_on = [aws_lb_listener.http, aws_route.private_app_nat]
}
