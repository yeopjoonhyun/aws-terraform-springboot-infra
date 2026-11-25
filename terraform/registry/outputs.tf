# app 루트(ECS 작업 정의)와 CI가 이 주소로 이미지를 받고 올린다.
output "ecr_repository_url" {
  description = "앱 이미지를 푸시할 ECR 저장소 주소"
  value       = aws_ecr_repository.app.repository_url
}

# CI 워크플로의 role-to-assume에 쓴다.
output "deployer_role_arn" {
  description = "GitHub Actions가 OIDC로 맡는 배포 역할"
  value       = aws_iam_role.deployer.arn
}
