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

variable "github_repo" {
  # GitHub 토큰의 sub는 이름 뒤에 바뀌지 않는 ID를 붙인다 (소유자@ID/레포@ID).
  # 레포를 지우고 같은 이름으로 다시 만들어도 ID가 달라 역할을 맡지 못한다. ID는 공개 정보다.
  description = "배포 역할을 맡을 수 있는 GitHub 레포 (토큰 sub 형식)"
  type        = string
  default     = "yeopjoonhyun@220882173/aws-terraform-springboot-infra@1449203694"
}
