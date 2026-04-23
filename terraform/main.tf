terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  default = "us-east-1"
}

variable "project" {
  default = "msi-transcribe-poc"
}

locals {
  tags = { project = var.project }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# --- S3 Bucket for transcripts/audio ---
resource "aws_s3_bucket" "transcripts" {
  bucket = "${var.project}-transcripts-${data.aws_caller_identity.current.account_id}"
  tags   = local.tags
}

resource "aws_s3_bucket_server_side_encryption_configuration" "transcripts" {
  bucket = aws_s3_bucket.transcripts.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "transcripts" {
  bucket                  = aws_s3_bucket.transcripts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- DynamoDB: sessions (charts + transcripts) ---
resource "aws_dynamodb_table" "sessions" {
  name         = "${var.project}-sessions"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "sessionId"
  attribute {
    name = "sessionId"
    type = "S"
  }
  tags = local.tags
}

# --- Cognito Identity Pool (unauthenticated for POC) ---
resource "aws_cognito_identity_pool" "transcribe_pool" {
  identity_pool_name               = "${var.project}-identity-pool"
  allow_unauthenticated_identities = true
  allow_classic_flow               = true
  tags                             = local.tags
}

resource "aws_iam_role" "cognito_unauth_role" {
  name = "${var.project}-cognito-unauth-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Federated = "cognito-identity.amazonaws.com" }
      Action   = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "cognito-identity.amazonaws.com:aud" = aws_cognito_identity_pool.transcribe_pool.id
        }
        "ForAnyValue:StringLike" = {
          "cognito-identity.amazonaws.com:amr" = "unauthenticated"
        }
      }
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy" "cognito_unauth_policy" {
  name = "${var.project}-cognito-unauth-policy"
  role = aws_iam_role.cognito_unauth_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["transcribe:StartStreamTranscriptionWebSocket"]
      Resource = "*"
    }]
  })
}

resource "aws_cognito_identity_pool_roles_attachment" "main" {
  identity_pool_id = aws_cognito_identity_pool.transcribe_pool.id
  roles = {
    unauthenticated = aws_iam_role.cognito_unauth_role.arn
  }
}

# --- IAM Role: Lambda execution role ---
resource "aws_iam_role" "lambda_role" {
  name = "${var.project}-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.project}-lambda-policy"
  role = aws_iam_role.lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Scan"
        ]
        Resource = aws_dynamodb_table.sessions.arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject"]
        Resource = "${aws_s3_bucket.transcripts.arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["bedrock:InvokeModel"]
        Resource = "arn:aws:bedrock:${data.aws_region.current.name}::foundation-model/*"
      },

    ]
  })
}

# --- Outputs ---
output "s3_bucket_name" {
  value = aws_s3_bucket.transcripts.id
}

output "sessions_table_name" {
  value = aws_dynamodb_table.sessions.name
}

output "lambda_role_arn" {
  value = aws_iam_role.lambda_role.arn
}

output "cognito_identity_pool_id" {
  value = aws_cognito_identity_pool.transcribe_pool.id
}

output "cognito_unauth_role_arn" {
  value = aws_iam_role.cognito_unauth_role.arn
}

output "region" {
  value = var.region
}
