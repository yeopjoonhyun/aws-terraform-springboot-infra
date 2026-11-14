# app 루트가 terraform_remote_state로 이 값들을 읽는다. 모듈로 옮기기 전과 이름을 똑같이 유지한다.
# 이름을 바꾸면 app 루트도 함께 고쳐야 한다.

output "vpc_id" {
  value = module.network.vpc_id
}

output "vpc_cidr" {
  value = module.network.vpc_cidr
}

output "subnet_ids" {
  value = module.network.subnet_ids
}

output "public_subnet_ids" {
  value = module.network.public_subnet_ids
}

output "private_app_subnet_ids" {
  value = module.network.private_app_subnet_ids
}

output "security_group_ids" {
  value = module.network.security_group_ids
}

output "private_app_route_table_id" {
  value = module.network.private_app_route_table_id
}

output "internet_gateway_id" {
  value = module.network.internet_gateway_id
}
