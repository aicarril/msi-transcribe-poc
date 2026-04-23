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
      Effect    = "Allow"
      Principal = { Federated = "cognito-identity.amazonaws.com" }
      Action    = "sts:AssumeRoleWithWebIdentity"
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
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:DeleteItem", "dynamodb:Scan"]
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
        Resource = [
          "arn:aws:bedrock:*::foundation-model/*",
          "arn:aws:bedrock:*:${data.aws_caller_identity.current.account_id}:inference-profile/*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = "arn:aws:lambda:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:function:${var.project}-extract-chart"
      }
    ]
  })
}

# --- Amazon Transcribe Custom Vocabulary ---
resource "aws_transcribe_vocabulary" "medical_spa" {
  vocabulary_name = "${var.project}-medical-spa"
  language_code   = "en-US"
  phrases = [
    "Botox", "Dysport", "Juvederm", "Restylane",
    "microneedling", "dermaplaning", "chemical-peel",
    "IPL", "laser-resurfacing", "hyaluronic-acid",
    "platelet-rich-plasma", "PRP",
    "subcutaneous", "intramuscular",
    "erythema", "edema", "contraindication",
    "glabella", "nasolabial", "mentalis",
    "orbicularis", "corrugator", "procerus",
    "frontalis", "masseter",
    "CoolSculpting", "PDO-threads",
    "neuromodulator", "dermal-filler"
  ]
  tags = local.tags
}

# --- Lambda: extract-chart ---
data "archive_file" "extract_chart" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/extract-chart"
  output_path = "${path.module}/extract-chart.zip"
}

resource "aws_lambda_function" "extract_chart" {
  function_name    = "${var.project}-extract-chart"
  role             = aws_iam_role.lambda_role.arn
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  timeout          = 60
  memory_size      = 256
  filename         = data.archive_file.extract_chart.output_path
  source_code_hash = data.archive_file.extract_chart.output_base64sha256
  environment {
    variables = {
      SESSIONS_TABLE = aws_dynamodb_table.sessions.name
      S3_BUCKET      = aws_s3_bucket.transcripts.id
    }
  }
  tags = local.tags
}

# --- API Gateway REST API ---
resource "aws_api_gateway_rest_api" "api" {
  name = "${var.project}-api"
  tags = local.tags
}

resource "aws_api_gateway_resource" "extract_chart" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "extract-chart"
}

# POST /extract-chart
resource "aws_api_gateway_method" "extract_chart_post" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.extract_chart.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "extract_chart_post" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.extract_chart.id
  http_method             = aws_api_gateway_method.extract_chart_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.extract_chart.invoke_arn
}

# CORS OPTIONS /extract-chart
resource "aws_api_gateway_method" "extract_chart_options" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.extract_chart.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "extract_chart_options" {
  rest_api_id       = aws_api_gateway_rest_api.api.id
  resource_id       = aws_api_gateway_resource.extract_chart.id
  http_method       = aws_api_gateway_method.extract_chart_options.http_method
  type              = "MOCK"
  request_templates = { "application/json" = "{\"statusCode\": 200}" }
}

resource "aws_api_gateway_method_response" "extract_chart_options" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.extract_chart.id
  http_method = aws_api_gateway_method.extract_chart_options.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "extract_chart_options" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.extract_chart.id
  http_method = aws_api_gateway_method.extract_chart_options.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type'"
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
  depends_on = [aws_api_gateway_integration.extract_chart_options]
}

resource "aws_lambda_permission" "api_gw_extract_chart" {
  statement_id  = "AllowAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.extract_chart.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

# --- Lambda: credentials ---
data "archive_file" "credentials" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/credentials"
  output_path = "${path.module}/credentials.zip"
}

resource "aws_iam_role" "credentials_lambda_role" {
  name = "${var.project}-credentials-lambda-role"
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

resource "aws_iam_role_policy" "credentials_lambda_policy" {
  name = "${var.project}-credentials-lambda-policy"
  role = aws_iam_role.credentials_lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect   = "Allow"
        Action   = ["cognito-identity:GetId", "cognito-identity:GetCredentialsForIdentity"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_lambda_function" "credentials" {
  function_name    = "${var.project}-credentials"
  role             = aws_iam_role.credentials_lambda_role.arn
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  timeout          = 10
  memory_size      = 128
  filename         = data.archive_file.credentials.output_path
  source_code_hash = data.archive_file.credentials.output_base64sha256
  environment {
    variables = {
      IDENTITY_POOL_ID = aws_cognito_identity_pool.transcribe_pool.id
    }
  }
  tags = local.tags
}

# GET /credentials
resource "aws_api_gateway_resource" "credentials" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "credentials"
}

resource "aws_api_gateway_method" "credentials_get" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.credentials.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "credentials_get" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.credentials.id
  http_method             = aws_api_gateway_method.credentials_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.credentials.invoke_arn
}

# CORS OPTIONS /credentials
resource "aws_api_gateway_method" "credentials_options" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.credentials.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "credentials_options" {
  rest_api_id       = aws_api_gateway_rest_api.api.id
  resource_id       = aws_api_gateway_resource.credentials.id
  http_method       = aws_api_gateway_method.credentials_options.http_method
  type              = "MOCK"
  request_templates = { "application/json" = "{\"statusCode\": 200}" }
}

resource "aws_api_gateway_method_response" "credentials_options" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.credentials.id
  http_method = aws_api_gateway_method.credentials_options.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "credentials_options" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.credentials.id
  http_method = aws_api_gateway_method.credentials_options.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
  depends_on = [aws_api_gateway_integration.credentials_options]
}

resource "aws_lambda_permission" "api_gw_credentials" {
  statement_id  = "AllowAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.credentials.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

# --- Lambda: sessions ---
data "archive_file" "sessions" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/sessions"
  output_path = "${path.module}/sessions.zip"
}

resource "aws_lambda_function" "sessions" {
  function_name    = "${var.project}-sessions"
  role             = aws_iam_role.lambda_role.arn
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  timeout          = 60
  memory_size      = 256
  filename         = data.archive_file.sessions.output_path
  source_code_hash = data.archive_file.sessions.output_base64sha256
  environment {
    variables = {
      SESSIONS_TABLE        = aws_dynamodb_table.sessions.name
      EXTRACT_FUNCTION_NAME = aws_lambda_function.extract_chart.function_name
    }
  }
  tags = local.tags
}

resource "aws_lambda_permission" "api_gw_sessions" {
  statement_id  = "AllowAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.sessions.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

# API Gateway: /sessions
resource "aws_api_gateway_resource" "sessions" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "sessions"
}

# GET /sessions
resource "aws_api_gateway_method" "sessions_get" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.sessions.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "sessions_get" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.sessions.id
  http_method             = aws_api_gateway_method.sessions_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.sessions.invoke_arn
}

# POST /sessions
resource "aws_api_gateway_method" "sessions_post" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.sessions.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "sessions_post" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.sessions.id
  http_method             = aws_api_gateway_method.sessions_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.sessions.invoke_arn
}

# OPTIONS /sessions
resource "aws_api_gateway_method" "sessions_options" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.sessions.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "sessions_options" {
  rest_api_id       = aws_api_gateway_rest_api.api.id
  resource_id       = aws_api_gateway_resource.sessions.id
  http_method       = aws_api_gateway_method.sessions_options.http_method
  type              = "MOCK"
  request_templates = { "application/json" = "{\"statusCode\": 200}" }
}

resource "aws_api_gateway_method_response" "sessions_options" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.sessions.id
  http_method = aws_api_gateway_method.sessions_options.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "sessions_options" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.sessions.id
  http_method = aws_api_gateway_method.sessions_options.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
  depends_on = [aws_api_gateway_integration.sessions_options]
}

# /sessions/{id}
resource "aws_api_gateway_resource" "session_id" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_resource.sessions.id
  path_part   = "{id}"
}

# GET /sessions/{id}
resource "aws_api_gateway_method" "session_id_get" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.session_id.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "session_id_get" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.session_id.id
  http_method             = aws_api_gateway_method.session_id_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.sessions.invoke_arn
}

# OPTIONS /sessions/{id}
resource "aws_api_gateway_method" "session_id_options" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.session_id.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "session_id_options" {
  rest_api_id       = aws_api_gateway_rest_api.api.id
  resource_id       = aws_api_gateway_resource.session_id.id
  http_method       = aws_api_gateway_method.session_id_options.http_method
  type              = "MOCK"
  request_templates = { "application/json" = "{\"statusCode\": 200}" }
}

resource "aws_api_gateway_method_response" "session_id_options" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.session_id.id
  http_method = aws_api_gateway_method.session_id_options.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "session_id_options" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.session_id.id
  http_method = aws_api_gateway_method.session_id_options.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
  depends_on = [aws_api_gateway_integration.session_id_options]
}

# /sessions/{id}/end
resource "aws_api_gateway_resource" "session_end" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_resource.session_id.id
  path_part   = "end"
}

# POST /sessions/{id}/end
resource "aws_api_gateway_method" "session_end_post" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.session_end.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "session_end_post" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.session_end.id
  http_method             = aws_api_gateway_method.session_end_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.sessions.invoke_arn
}

# OPTIONS /sessions/{id}/end
resource "aws_api_gateway_method" "session_end_options" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.session_end.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "session_end_options" {
  rest_api_id       = aws_api_gateway_rest_api.api.id
  resource_id       = aws_api_gateway_resource.session_end.id
  http_method       = aws_api_gateway_method.session_end_options.http_method
  type              = "MOCK"
  request_templates = { "application/json" = "{\"statusCode\": 200}" }
}

resource "aws_api_gateway_method_response" "session_end_options" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.session_end.id
  http_method = aws_api_gateway_method.session_end_options.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "session_end_options" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.session_end.id
  http_method = aws_api_gateway_method.session_end_options.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type'"
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
  depends_on = [aws_api_gateway_integration.session_end_options]
}

# /sessions/{id}/save
resource "aws_api_gateway_resource" "session_save" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_resource.session_id.id
  path_part   = "save"
}

# POST /sessions/{id}/save
resource "aws_api_gateway_method" "session_save_post" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.session_save.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "session_save_post" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.session_save.id
  http_method             = aws_api_gateway_method.session_save_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.sessions.invoke_arn
}

# OPTIONS /sessions/{id}/save
resource "aws_api_gateway_method" "session_save_options" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.session_save.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "session_save_options" {
  rest_api_id       = aws_api_gateway_rest_api.api.id
  resource_id       = aws_api_gateway_resource.session_save.id
  http_method       = aws_api_gateway_method.session_save_options.http_method
  type              = "MOCK"
  request_templates = { "application/json" = "{\"statusCode\": 200}" }
}

resource "aws_api_gateway_method_response" "session_save_options" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.session_save.id
  http_method = aws_api_gateway_method.session_save_options.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "session_save_options" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.session_save.id
  http_method = aws_api_gateway_method.session_save_options.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type'"
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
  depends_on = [aws_api_gateway_integration.session_save_options]
}

# --- API Gateway Deployment ---
resource "aws_api_gateway_deployment" "api" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  depends_on = [
    aws_api_gateway_integration.extract_chart_post,
    aws_api_gateway_integration.extract_chart_options,
    aws_api_gateway_integration.credentials_get,
    aws_api_gateway_integration.credentials_options,
    aws_api_gateway_integration.sessions_get,
    aws_api_gateway_integration.sessions_post,
    aws_api_gateway_integration.sessions_options,
    aws_api_gateway_integration.session_id_get,
    aws_api_gateway_integration.session_id_options,
    aws_api_gateway_integration.session_end_post,
    aws_api_gateway_integration.session_end_options,
    aws_api_gateway_integration.session_save_post,
    aws_api_gateway_integration.session_save_options
  ]
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.extract_chart.id,
      aws_api_gateway_resource.credentials.id,
      aws_api_gateway_resource.sessions.id,
      aws_api_gateway_resource.session_id.id,
      aws_api_gateway_resource.session_end.id,
      aws_api_gateway_resource.session_save.id,
      aws_api_gateway_method.sessions_post.id,
      aws_api_gateway_method.session_end_post.id,
      aws_api_gateway_method.session_save_post.id,
    ]))
  }
  lifecycle { create_before_destroy = true }
}

resource "aws_api_gateway_stage" "prod" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.api.id
  stage_name    = "prod"
  tags          = local.tags
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

output "custom_vocabulary_name" {
  value = aws_transcribe_vocabulary.medical_spa.vocabulary_name
}

output "api_url" {
  value = "${aws_api_gateway_stage.prod.invoke_url}"
}
