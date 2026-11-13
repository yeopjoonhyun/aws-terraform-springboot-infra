variable "aws_region" {
  description = "리소스를 만들 AWS 리전"
  type        = string
  default     = "ap-southeast-2" # 시드니 (이 계정에서 EC2가 허용된 리전)
}

variable "project_name" {
  description = "리소스 이름과 태그에 쓰는 프로젝트 이름"
  type        = string
  default     = "aws-tf-springboot"
}

variable "app_port" {
  description = "Spring Boot 앱이 듣는 포트 (보안 그룹 규칙에 쓴다)"
  type        = number
  default     = 8080
}

variable "db_port" {
  description = "DB 포트 (MySQL 기준)"
  type        = number
  default     = 3306
}

variable "vpc_cidr" {
  description = "VPC의 IP 주소 범위"
  type        = string
  default     = "10.0.0.0/16"
}

variable "aws_account_id" {
  description = "이 프로젝트가 쓰는 개인 AWS 계정 번호. Public 레포라 terraform.tfvars(커밋 안 됨)에만 적는다."
  type        = string
}
