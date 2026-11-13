# ---------- 프라이빗 앱 서브넷의 출구: NAT Gateway ----------
# 앱은 프라이빗 서브넷에 있어 인터넷에서 들어올 수 없다. 대신 NAT를 거쳐 밖으로만 나갈 수 있다.
# (ECR에서 이미지 받기, CloudWatch로 로그 보내기에 필요)
# NAT는 시간당 요금이 나가서 요금이 나가는 다른 리소스와 함께 이 루트에서 만들고 지운다.
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-nat-eip"
  }
}

# ponytail: NAT를 AZ a에 1개만 둔다(비용 절감). a가 장애 나면 b의 앱도 밖으로 못 나간다. 운영 환경이면 AZ마다 1개.
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = local.net.subnet_ids["public-a"]

  tags = {
    Name = "${var.project_name}-nat"
  }
}

# network 루트가 만든 프라이빗 길 안내표에 "밖으로 나가는 길은 NAT로"를 추가한다.
# 이 루트를 destroy하면 이 길도 함께 사라져서, network는 항상 처음 상태(무료)로 돌아간다.
resource "aws_route" "private_app_nat" {
  route_table_id         = local.net.private_app_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main.id
}
