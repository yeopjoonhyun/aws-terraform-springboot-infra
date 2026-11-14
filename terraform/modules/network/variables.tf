# 이 모듈은 provider를 직접 설정하지 않는다. 리전, 계정 고정, 공통 태그는 부르는 루트가 정한다.

variable "project_name" {
  description = "리소스 이름 앞에 붙는 접두사"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC의 IP 주소 범위"
  type        = string
}

variable "app_port" {
  description = "앱 포트 (보안 그룹 규칙에 쓴다)"
  type        = number
}

variable "db_port" {
  description = "DB 포트 (보안 그룹 규칙에 쓴다)"
  type        = number
}
