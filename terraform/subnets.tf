# 이 리전에서 사용 가능한 가용 영역(AZ) 목록을 AWS에서 읽어온다
data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  # 앞의 두 AZ만 사용한다 (예: ap-southeast-2a, ap-southeast-2b)
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  # 서브넷 6개를 한곳에 정의한다. 설계 문서(docs/02-network-design.md)와 같은 구조.
  subnets = {
    public-a = { cidr = "10.0.0.0/24", az = local.azs[0], tier = "public" }
    public-b = { cidr = "10.0.1.0/24", az = local.azs[1], tier = "public" }
    app-a    = { cidr = "10.0.10.0/24", az = local.azs[0], tier = "private-app" }
    app-b    = { cidr = "10.0.11.0/24", az = local.azs[1], tier = "private-app" }
    db-a     = { cidr = "10.0.20.0/24", az = local.azs[0], tier = "private-db" }
    db-b     = { cidr = "10.0.21.0/24", az = local.azs[1], tier = "private-db" }
  }

  public_subnets = { for k, v in local.subnets : k => v if v.tier == "public" }
}

resource "aws_subnet" "this" {
  for_each = local.subnets

  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az

  # 퍼블릭 서브넷에서 시작하는 리소스에만 공인 IP를 자동으로 붙인다
  map_public_ip_on_launch = each.value.tier == "public"

  tags = {
    Name = "${var.project_name}-${each.key}"
    Tier = each.value.tier
  }
}
