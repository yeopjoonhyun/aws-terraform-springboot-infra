variable "aws_region" {
  description = "리소스를 만들 AWS 리전"
  type        = string
  default     = "ap-southeast-2" # 시드니
}

variable "project_name" {
  description = "리소스 이름과 태그에 쓰는 프로젝트 이름"
  type        = string
  default     = "aws-tf-springboot"
}

variable "aws_account_id" {
  description = "이 프로젝트가 쓰는 개인 AWS 계정 번호. Public 레포라 terraform.tfvars(커밋 안 됨)에만 적는다."
  type        = string
}

variable "deletion_protection" {
  description = "RDS 삭제 방지. destroy 전에 -var deletion_protection=false 로 apply해서 먼저 끈다."
  type        = bool
  default     = true
}
