output "vpc_id" {
  description = "생성된 VPC의 ID"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "VPC의 IP 주소 범위"
  value       = aws_vpc.main.cidr_block
}
