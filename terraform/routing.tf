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
