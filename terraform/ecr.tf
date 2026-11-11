# 앱 Docker 이미지를 보관하는 저장소 (ECS가 여기서 이미지를 받아 실행한다)
resource "aws_ecr_repository" "app" {
  name = "${var.project_name}-app"

  # 같은 태그로 이미지를 덮어쓰지 못하게 해서 "배포된 버전"이 바뀌지 않게 한다
  image_tag_mutability = "IMMUTABLE"

  # 이미지가 남아 있어도 destroy로 지울 수 있게 한다 (실습 후 정리용)
  force_delete = true

  # 푸시할 때마다 알려진 취약점(CVE)을 자동으로 검사한다
  image_scanning_configuration {
    scan_on_push = true
  }
}

# 이미지가 계속 쌓여 저장 요금이 늘지 않도록 최근 10개만 남긴다
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "최근 이미지 10개만 유지"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}
