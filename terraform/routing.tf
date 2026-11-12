# 인터넷 게이트웨이: VPC와 인터넷을 잇는 문
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# 퍼블릭 라우팅 테이블: "인터넷으로 가는 길은 인터넷 게이트웨이로"라는 길 안내표
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

# 퍼블릭 서브넷에만 이 길 안내표를 연결한다. 프라이빗 서브넷은 연결하지 않아 인터넷에서 직접 닿지 않는다.
resource "aws_route_table_association" "public" {
  for_each = local.public_subnets

  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.public.id
}

# ---------- 프라이빗 앱 서브넷의 출구: NAT Gateway ----------
# 앱은 프라이빗 서브넷에 있어 인터넷에서 들어올 수 없다. 대신 NAT를 거쳐 밖으로만 나갈 수 있다.
# (ECR에서 이미지 받기, CloudWatch로 로그 보내기에 필요)
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-nat-eip"
  }
}

# ponytail: NAT를 AZ a에 1개만 둔다(비용 절감). a가 장애 나면 b의 앱도 밖으로 못 나간다. 운영 환경이면 AZ마다 1개.
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.this["public-a"].id

  tags = {
    Name = "${var.project_name}-nat"
  }

  depends_on = [aws_internet_gateway.main]
}

resource "aws_route_table" "private_app" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-private-app-rt"
  }
}

# 앱 서브넷에만 연결한다. DB 서브넷은 밖으로 나갈 일이 없어 연결하지 않는다.
resource "aws_route_table_association" "private_app" {
  for_each = { for k, v in local.subnets : k => v if v.tier == "private-app" }

  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.private_app.id
}
