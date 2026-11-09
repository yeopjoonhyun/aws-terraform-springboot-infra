output "vpc_id" {
  description = "생성된 VPC의 ID"
  value       = aws_vpc.main.id
}

output "subnet_ids" {
  description = "서브넷 이름별 ID"
  value       = { for k, s in aws_subnet.this : k => s.id }
}

output "internet_gateway_id" {
  description = "인터넷 게이트웨이 ID"
  value       = aws_internet_gateway.main.id
}

output "vpc_cidr" {
  description = "VPC의 IP 주소 범위"
  value       = aws_vpc.main.cidr_block
}
