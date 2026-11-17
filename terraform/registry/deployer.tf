# GitHub Actions(CD)가 쓰는 배포 전용 IAM 사용자.
# 원래는 키 없이 OIDC로 들어가야 하지만, 조직 SCP가 OIDC 공급자 생성을 막아서 장기 키를 쓰는 차선책이다.
# 위험을 줄이려고 권한을 "이 ECR 저장소 1개에 푸시, 이 ECS 서비스 1개 갱신"으로만 좁힌다.
# ponytail: OIDC가 허용되면 이 사용자와 키를 지우고 OIDC 역할로 바꾼다.
# 키는 Terraform으로 만들지 않는다 (만들면 비밀 키가 state 파일에 남는다). 만드는 법은 docs/07-cicd.md.

locals {
  ecs_cluster     = "${var.project_name}-cluster"
  ecs_service_arn = "arn:aws:ecs:${var.aws_region}:${var.aws_account_id}:service/${local.ecs_cluster}/${var.project_name}-app"
  task_exec_role  = "arn:aws:iam::${var.aws_account_id}:role/${var.project_name}-task-execution"
}

resource "aws_iam_user" "deployer" {
  name = "${var.project_name}-github-deployer"
}

resource "aws_iam_user_policy" "deployer" {
  name = "deploy-app"
  user = aws_iam_user.deployer.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "EcrLogin" # 로그인 토큰은 저장소를 지정할 수 없는 API라 *
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Sid    = "EcrPushThisRepo"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
          "ecr:DescribeImages", # 같은 태그가 이미 있는지 확인 (IMMUTABLE이라 덮어쓰기 불가)
        ]
        Resource = aws_ecr_repository.app.arn
      },
      {
        Sid      = "EcsDeployThisService"
        Effect   = "Allow"
        Action   = ["ecs:DescribeServices", "ecs:UpdateService"]
        Resource = local.ecs_service_arn
      },
      {
        Sid      = "EcsTaskDefinition" # 작업 정의 API는 리소스를 지정할 수 없어 *
        Effect   = "Allow"
        Action   = ["ecs:DescribeTaskDefinition", "ecs:RegisterTaskDefinition"]
        Resource = "*"
      },
      {
        Sid      = "PassExecutionRoleToEcsOnly" # 새 작업 정의에 실행 역할을 붙일 때 필요. ECS에만 넘길 수 있다
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = local.task_exec_role
        Condition = {
          StringEquals = { "iam:PassedToService" = "ecs-tasks.amazonaws.com" }
        }
      },
    ]
  })
}
