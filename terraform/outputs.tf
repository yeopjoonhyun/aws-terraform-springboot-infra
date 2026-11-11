output "vpc_id" {
  description = "생성된 VPC의 ID"
  value       = aws_vpc.main.id
}

output "subnet_ids" {
  description = "서브넷 이름별 ID"
  value       = { for k, s in aws_subnet.this : k => s.id }
}

output "security_group_ids" {
  description = "보안 그룹 ID (alb, app, db)"
  value = {
    alb = aws_security_group.alb.id
    app = aws_security_group.app.id
    db  = aws_security_group.db.id
  }
}

output "internet_gateway_id" {
  description = "인터넷 게이트웨이 ID"
  value       = aws_internet_gateway.main.id
}

output "vpc_cidr" {
  description = "VPC의 IP 주소 범위"
  value       = aws_vpc.main.cidr_block
}

output "ecr_repository_url" {
  description = "앱 이미지를 푸시할 ECR 저장소 주소"
  value       = aws_ecr_repository.app.repository_url
}
