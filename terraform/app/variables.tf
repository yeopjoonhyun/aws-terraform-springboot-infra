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
  description = "Spring Boot 앱이 듣는 포트"
  type        = number
  default     = 8080
}

variable "image_tag" {
  description = "ECS로 실행할 앱 이미지 태그 (Git 커밋 해시). 예: -var image_tag=aa3e184"
  type        = string
}

variable "task_vcpu" {
  description = "Fargate 작업당 vCPU. 기동 시간 비교 시 0.5로 바꾼다."
  type        = number
  default     = 0.25

  validation {
    condition     = contains([0.25, 0.5], var.task_vcpu)
    error_message = "task_vcpu는 0.25 또는 0.5여야 합니다."
  }
}

variable "aws_account_id" {
  description = "이 프로젝트가 쓰는 개인 AWS 계정 번호. Public 레포라 terraform.tfvars(커밋 안 됨)에만 적는다."
  type        = string
}
