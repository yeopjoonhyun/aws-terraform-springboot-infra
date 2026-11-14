# network 루트: 네트워크 모듈을 한 번 불러 VPC, 서브넷, 라우팅, 보안 그룹을 만든다.
# 실제 코드는 ../modules/network 에 있다. 다른 환경(dev/prod)이나 EKS 루트도 같은 모듈을 다시 쓸 수 있다.
module "network" {
  source = "../modules/network"

  project_name = var.project_name
  vpc_cidr     = var.vpc_cidr
  app_port     = var.app_port
  db_port      = var.db_port
}

# ---------- 모듈로 옮기기 전 주소 -> 옮긴 뒤 주소 ----------
# 리소스는 그대로이고 장부(state) 속 이름만 바뀌었다고 Terraform에 알려 준다.
# 이 블록이 없으면 Terraform은 "옛것을 지우고 새것을 만든다"고 판단해 네트워크를 다시 만든다.
# 모든 곳에서 apply가 끝난 뒤에는 지워도 되지만, 이력 설명용으로 남겨 둔다.

moved {
  from = aws_vpc.main
  to   = module.network.aws_vpc.main
}

moved {
  from = aws_internet_gateway.main
  to   = module.network.aws_internet_gateway.main
}

moved {
  from = aws_route_table.public
  to   = module.network.aws_route_table.public
}

moved {
  from = aws_route_table_association.public
  to   = module.network.aws_route_table_association.public
}

moved {
  from = aws_route_table.private_app
  to   = module.network.aws_route_table.private_app
}

moved {
  from = aws_route_table_association.private_app
  to   = module.network.aws_route_table_association.private_app
}

moved {
  from = aws_subnet.this
  to   = module.network.aws_subnet.this
}

moved {
  from = aws_security_group.alb
  to   = module.network.aws_security_group.alb
}

moved {
  from = aws_vpc_security_group_ingress_rule.alb_http
  to   = module.network.aws_vpc_security_group_ingress_rule.alb_http
}

moved {
  from = aws_vpc_security_group_ingress_rule.alb_https
  to   = module.network.aws_vpc_security_group_ingress_rule.alb_https
}

moved {
  from = aws_vpc_security_group_egress_rule.alb_to_app
  to   = module.network.aws_vpc_security_group_egress_rule.alb_to_app
}

moved {
  from = aws_security_group.app
  to   = module.network.aws_security_group.app
}

moved {
  from = aws_vpc_security_group_ingress_rule.app_from_alb
  to   = module.network.aws_vpc_security_group_ingress_rule.app_from_alb
}

moved {
  from = aws_vpc_security_group_egress_rule.app_to_db
  to   = module.network.aws_vpc_security_group_egress_rule.app_to_db
}

moved {
  from = aws_vpc_security_group_egress_rule.app_https_out
  to   = module.network.aws_vpc_security_group_egress_rule.app_https_out
}

moved {
  from = aws_security_group.db
  to   = module.network.aws_security_group.db
}

moved {
  from = aws_vpc_security_group_ingress_rule.db_from_app
  to   = module.network.aws_vpc_security_group_ingress_rule.db_from_app
}
