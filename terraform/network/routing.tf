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

# 프라이빗 앱 서브넷의 길 안내표. 여기에는 "밖으로 나가는 길"을 일부러 넣지 않는다.
# NAT Gateway는 시간당 요금이 나가서 app 루트가 만들고, 그 길(aws_route)도 app 루트가 이 표에 추가한다.
# (그래서 network 루트는 전부 무료이고, app을 지우면 밖으로 나가는 길도 함께 사라진다)
# 주의: 이 표에 route 블록을 직접 쓰면 app 루트의 aws_route와 충돌하므로 넣지 않는다.
resource "aws_route_table" "private_app" {
  vpc_id = aws_vpc.main.id

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
