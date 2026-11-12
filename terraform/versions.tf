terraform {
  required_version = ">= 1.5.0"

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
