terraform {
  required_version = ">= 1.10.0" # S3 네이티브 잠금(use_lockfile)에 필요

  # registry 루트의 state. 다른 루트와 key를 달리해서 장부를 따로 둔다.
  backend "s3" {
    bucket       = "aws-tf-springboot-tfstate-6fa62f"
    key          = "registry/terraform.tfstate"
    region       = "ap-southeast-2"
    encrypt      = true
    use_lockfile = true
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

  # 개인 계정이 아니면 실행을 멈춘다. (팀 프로젝트와 계정이 섞이는 사고 방지)
  allowed_account_ids = [var.aws_account_id]

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
    }
  }
}
