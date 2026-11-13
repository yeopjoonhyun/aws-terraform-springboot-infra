# Terraform state(장부)를 보관할 S3 버킷을 만든다.
# 이 폴더의 state만 예외적으로 로컬에 둔다. (보관함이 생기기 전에는 장부를 둘 곳이 없다)
# 이 버킷은 실습 후 destroy 대상이 아니다. state가 여기에 있기 때문이다.

terraform {
  required_version = ">= 1.10.0" # S3 네이티브 잠금(use_lockfile)에 필요

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

variable "aws_region" {
  type    = string
  default = "ap-southeast-2"
}

variable "aws_account_id" {
  description = "이 계정에서만 실행되도록 고정 (값은 커밋되지 않는 terraform.tfvars에 둔다)"
  type        = string
}

variable "project_name" {
  type    = string
  default = "aws-tf-springboot"
}

provider "aws" {
  region              = var.aws_region
  allowed_account_ids = [var.aws_account_id]

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
    }
  }
}

# S3 버킷 이름은 전 세계에서 유일해야 한다. 계정 번호 대신 무작위 접미사를 붙여 Public 레포에 계정 정보가 드러나지 않게 한다.
resource "random_id" "suffix" {
  byte_length = 3
}

resource "aws_s3_bucket" "state" {
  bucket = "${var.project_name}-tfstate-${random_id.suffix.hex}"

  # 실수로 destroy해도 장부가 지워지지 않게 막는다.
  lifecycle {
    prevent_destroy = true
  }
}

# 버전 관리: 장부가 잘못 덮어써져도 이전 버전으로 되돌릴 수 있다.
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# 장부에는 민감한 값이 들어갈 수 있으니 외부 공개를 전부 막는다.
resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 오래된 버전은 90일 뒤 정리해 저장 비용이 쌓이지 않게 한다.
resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# HTTPS가 아닌 접근은 거부한다.
resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })

  depends_on = [aws_s3_bucket_public_access_block.state]
}

output "state_bucket" {
  description = "다음 단계에서 backend 설정에 넣을 버킷 이름"
  value       = aws_s3_bucket.state.id
}
