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

variable "cluster_version" {
  description = "쿠버네티스 버전. 표준 지원이 끝난 버전은 연장 지원 요금이 6배라 표준 지원 버전만 쓴다."
  type        = string
  default     = "1.37"
}

variable "node_instance_type" {
  description = "노드 EC2 타입. 앱 이미지가 ARM64라 Graviton(t4g)을 쓴다."
  type        = string
  default     = "t4g.medium"
}
