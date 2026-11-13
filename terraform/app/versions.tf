terraform {
  required_version = ">= 1.10.0" # S3 네이티브 잠금(use_lockfile)에 필요

  # app 루트의 state. network 루트와 key를 달리해서 장부를 따로 둔다.
  backend "s3" {
    bucket       = "aws-tf-springboot-tfstate-6fa62f"
    key          = "app/terraform.tfstate"
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

# network 루트가 만든 VPC, 서브넷, 보안 그룹 정보를 읽기 전용으로 가져온다.
# 이 루트는 network를 읽기만 하고 고치지 않는다. (예외: 프라이빗 서브넷의 NAT 경로 aws_route 하나)
# network를 아직 apply하지 않았다면 여기서 에러가 난다. 순서: network -> app.
data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket = "aws-tf-springboot-tfstate-6fa62f"
    key    = "network/terraform.tfstate"
    region = var.aws_region
  }
}

locals {
  net = data.terraform_remote_state.network.outputs
}
