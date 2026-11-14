resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr

  # 인스턴스가 DNS 이름을 받을 수 있게 한다 (ECS, RDS 접속에 필요)
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}
