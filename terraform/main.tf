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
  tags = {
    project = var.project
  }
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

# --- DynamoDB: sessions ---
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

# --- DynamoDB: chart-templates ---
resource "aws_dynamodb_table" "chart_templates" {
  name         = "${var.project}-chart-templates"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "templateId"
  attribute {
    name = "templateId"
    type = "S"
  }
  tags = local.tags
}

# --- DynamoDB: connections ---
resource "aws_dynamodb_table" "connections" {
  name         = "${var.project}-connections"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "connectionId"
  attribute {
    name = "connectionId"
    type = "S"
  }
  tags = local.tags
}

# --- IAM Role: Lambda execution role ---
resource "aws_iam_role" "lambda_role" {
  name = "${var.project}-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
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
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          aws_dynamodb_table.sessions.arn,
          aws_dynamodb_table.chart_templates.arn,
          aws_dynamodb_table.connections.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.transcripts.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "transcribe:StartStreamTranscription",
          "transcribe:StartStreamTranscriptionWebSocket"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel"
        ]
        Resource = "arn:aws:bedrock:${data.aws_region.current.name}::foundation-model/*"
      },
      {
        Effect = "Allow"
        Action = [
          "execute-api:ManageConnections"
        ]
        Resource = "arn:aws:execute-api:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*/*"
      }
    ]
  })
}

# --- Seed chart-templates with Neuromodulator template ---
resource "aws_dynamodb_table_item" "neuromodulator_template" {
  table_name = aws_dynamodb_table.chart_templates.name
  hash_key   = aws_dynamodb_table.chart_templates.hash_key
  item = jsonencode({
    templateId             = { S = "neuromodulator" }
    templateName           = { S = "Neuromodulator Treatment Form" }
    fields = { S = jsonencode({
      patientId                = ""
      providerId               = ""
      date                     = ""
      chiefComplaint           = ""
      treatmentPerformed       = ""
      areasOfTreatment         = []
      productsUsed             = [{ name = "", units = "", lot = "" }]
      dosage                   = ""
      technique                = ""
      skinAssessment           = ""
      adverseReactions         = ""
      postTreatmentInstructions = ""
      followUpDate             = ""
      providerNotes            = ""
      consentObtained          = true
      photographsTaken         = false
    })}
  })
}

# --- Outputs ---
output "s3_bucket_name" {
  value = aws_s3_bucket.transcripts.id
}

output "sessions_table_name" {
  value = aws_dynamodb_table.sessions.name
}

output "chart_templates_table_name" {
  value = aws_dynamodb_table.chart_templates.name
}

output "connections_table_name" {
  value = aws_dynamodb_table.connections.name
}

output "lambda_role_arn" {
  value = aws_iam_role.lambda_role.arn
}
