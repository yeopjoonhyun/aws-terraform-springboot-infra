terraform {
  required_version = ">= 1.10.0" # S3 네이티브 잠금(use_lockfile)에 필요

  # state(장부)를 내 컴퓨터가 아니라 S3 버킷에 둔다. 버킷은 bootstrap/ 에서 만든다.
  # 버킷 이름은 무작위 접미사만 있고 계정 번호가 없어서 커밋해도 된다.
  backend "s3" {
    bucket       = "aws-tf-springboot-tfstate-6fa62f"
    key          = "app/terraform.tfstate"
    region       = "ap-southeast-2"
    encrypt      = true
    use_lockfile = true # 동시에 두 곳에서 apply하지 못하게 S3에 잠금 파일을 만든다
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  # 개인 계정이 아니면 실행을 멈춘다. 같은 맥에서 팀 프로젝트(다른 AWS 계정)를 해도
  # 자격 증명이 바뀌었을 때 엉뚱한 계정에 리소스를 만들지 않게 막는 안전장치.
  allowed_account_ids = [var.aws_account_id]

  # 모든 리소스에 공통 태그를 자동으로 붙인다 (비용 추적, 정리에 유용)
  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
    }
  }
}
