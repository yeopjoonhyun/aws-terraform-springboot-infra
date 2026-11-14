# 모듈의 출력값. 부르는 루트(network)가 같은 이름으로 다시 내보내고, app 루트가 terraform_remote_state로 읽는다.

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "VPC의 IP 주소 범위"
  value       = aws_vpc.main.cidr_block
}

output "subnet_ids" {
  description = "서브넷 이름별 ID (예: public-a, app-a, db-a)"
  value       = { for k, s in aws_subnet.this : k => s.id }
}

output "public_subnet_ids" {
  description = "퍼블릭 서브넷 ID 목록 (ALB가 사용)"
  value       = [for k, v in local.public_subnets : aws_subnet.this[k].id]
}

output "private_app_subnet_ids" {
  description = "앱용 프라이빗 서브넷 ID 목록 (ECS가 사용)"
  value       = [for k, v in local.subnets : aws_subnet.this[k].id if v.tier == "private-app"]
}

output "security_group_ids" {
  description = "보안 그룹 ID (alb, app, db)"
  value = {
    alb = aws_security_group.alb.id
    app = aws_security_group.app.id
    db  = aws_security_group.db.id
  }
}

output "private_app_route_table_id" {
  description = "앱 서브넷의 라우팅 테이블 ID (app 루트가 NAT로 나가는 길을 추가한다)"
  value       = aws_route_table.private_app.id
}

output "internet_gateway_id" {
  description = "인터넷 게이트웨이 ID"
  value       = aws_internet_gateway.main.id
}
