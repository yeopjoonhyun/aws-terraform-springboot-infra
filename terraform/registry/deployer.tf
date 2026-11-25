# GitHub Actions(CD)가 AWS에 들어갈 때 쓰는 권한.
# 장기 키 없이 OIDC로 들어온다: GitHub이 실행마다 서명한 토큰을 주고, AWS가 확인한 뒤 1시간짜리 임시 키를 내준다.
# 권한은 "이 ECR 저장소 1개에 푸시, 이 ECS 서비스 1개 갱신"으로만 좁힌다.

locals {
  ecs_cluster     = "${var.project_name}-cluster"
  ecs_service_arn = "arn:aws:ecs:${var.aws_region}:${var.aws_account_id}:service/${local.ecs_cluster}/${var.project_name}-app"
  task_exec_role  = "arn:aws:iam::${var.aws_account_id}:role/${var.project_name}-task-execution"

  deploy_policy = jsonencode({
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

# GitHub Actions 토큰을 믿을 발급처로 등록한다 (계정에 하나, 무료)
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

# 이 레포의 main 브랜치에서 돈 워크플로만 이 역할을 맡을 수 있다. PR과 다른 브랜치, 다른 레포는 거부된다.
resource "aws_iam_role" "deployer" {
  name = "${var.project_name}-github-deployer"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:ref:refs/heads/main"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "deployer" {
  name   = "deploy-app"
  role   = aws_iam_role.deployer.id
  policy = local.deploy_policy
}

# ponytail: CI가 OIDC 역할로 성공하면 아래 사용자와 키를 지운다 (전환 중에만 남긴다).
resource "aws_iam_user" "deployer" {
  name = "${var.project_name}-github-deployer"
}

resource "aws_iam_user_policy" "deployer" {
  name   = "deploy-app"
  user   = aws_iam_user.deployer.name
  policy = local.deploy_policy
}
