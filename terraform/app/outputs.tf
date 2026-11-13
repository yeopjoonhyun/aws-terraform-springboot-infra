output "ecr_repository_url" {
  description = "앱 이미지를 푸시할 ECR 저장소 주소"
  value       = aws_ecr_repository.app.repository_url
}

output "alb_url" {
  description = "앱 접속 주소"
  value       = "http://${aws_lb.app.dns_name}"
}
