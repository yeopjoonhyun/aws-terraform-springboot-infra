# 프라이빗 서브넷의 노드가 인터넷(ECR, EKS API)에 나갈 출구. 시간당 요금이 나간다.
# app 루트(ECS)도 같은 라우팅 테이블에 같은 경로를 넣으므로 app과 eks는 동시에 켜지 않는다.
resource "aws_eip" "nat" {
  domain = "vpc"
  tags = {
    Name = "${var.project_name}-eks-nat-eip"
  }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = local.net.public_subnet_ids[0]
  tags = {
    Name = "${var.project_name}-eks-nat"
  }
}

resource "aws_route" "private_app_nat" {
  route_table_id         = local.net.private_app_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main.id
}
