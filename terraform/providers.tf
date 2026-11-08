<<<<<<< HEAD:terraform/main.tf
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  name              = "${var.project_name}-${var.environment}"
  function_name     = "${local.name}-image-analyzer"
  partition         = data.aws_partition.current.partition
  account_id        = data.aws_caller_identity.current.account_id
  worker_enabled    = var.image_tag != null
  foundation_model  = trimprefix(var.bedrock_model_id, "us.")
  inference_profile = "arn:${local.partition}:bedrock:${var.aws_region}:${local.account_id}:inference-profile/${var.bedrock_model_id}"
  foundation_models = "arn:${local.partition}:bedrock:us-*::foundation-model/${local.foundation_model}"
}

# The existing image bucket remains outside Terraform management.
data "aws_s3_bucket" "images" {
  bucket = var.images_bucket_name
}

import {
  to = aws_dynamodb_table.reports
  id = var.reports_table_name
}

resource "aws_dynamodb_table" "reports" {
  name         = var.reports_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "zipcode"
  range_key    = "condition-timestamp"

  attribute {
    name = "zipcode"
    type = "S"
  }

  attribute {
    name = "condition-timestamp"
    type = "S"
  }
}

resource "aws_ecr_repository" "analyzer" {
  name                 = "${local.name}-image-analyzer"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = false

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository_policy" "analyzer" {
  repository = aws_ecr_repository.analyzer.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "LambdaImageRetrieval"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"]
      Condition = {
        ArnLike = {
          "aws:SourceArn" = [
            "arn:${local.partition}:lambda:${var.aws_region}:${local.account_id}:function:${local.function_name}",
            "arn:${local.partition}:lambda:${var.aws_region}:${local.account_id}:function:GridGuardianAPI",
          ]
        }
      }
    }]
  })
}

resource "aws_cloudwatch_log_group" "analyzer" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = 14
}

# Captures exhausted asynchronous invocations; this is not an input queue.
resource "aws_sqs_queue" "analysis_failures" {
  name                      = "${local.name}-analysis-failures"
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true
}

resource "aws_iam_role" "analyzer" {
  name = "${local.name}-analyzer"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "analyzer" {
  name = "image-analysis"
  role = aws_iam_role.analyzer.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadUploadedImages"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:GetObjectVersion"]
        Resource = "${data.aws_s3_bucket.images.arn}/${var.image_prefix}*"
      },
      {
        Sid      = "ReadAndWriteReports"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem"]
        Resource = aws_dynamodb_table.reports.arn
      },
      {
        Sid      = "InvokeNovaInferenceProfile"
        Effect   = "Allow"
        Action   = "bedrock:InvokeModel"
        Resource = local.inference_profile
      },
      {
        Sid      = "InvokeRoutedNovaModels"
        Effect   = "Allow"
        Action   = "bedrock:InvokeModel"
        Resource = local.foundation_models
        Condition = {
          StringEquals = { "bedrock:InferenceProfileArn" = local.inference_profile }
        }
      },
      {
        Sid      = "WriteWorkerLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.analyzer.arn}:*"
      },
      {
        Sid      = "CaptureFailedAnalysis"
        Effect   = "Allow"
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.analysis_failures.arn
      }
    ]
  })
}

# The tag must already exist; resolve it to a digest for reproducible deployments.
data "aws_ecr_image" "analyzer" {
  count           = local.worker_enabled ? 1 : 0
  repository_name = aws_ecr_repository.analyzer.name
  image_tag       = var.image_tag
}

resource "aws_lambda_function" "analyzer" {
  count         = local.worker_enabled ? 1 : 0
  function_name = local.function_name
  description   = "Analyze uploaded infrastructure images with Amazon Nova and store JSON reports."
  role          = aws_iam_role.analyzer.arn
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.analyzer.repository_url}@${data.aws_ecr_image.analyzer[0].image_digest}"
  architectures = ["x86_64"]
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_size

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.analyzer.name
  }

  environment {
    variables = {
      IMAGES_BUCKET        = data.aws_s3_bucket.images.id
      IMAGE_PREFIX         = var.image_prefix
      REPORTS_TABLE        = aws_dynamodb_table.reports.name
      REPORT_PARTITION_KEY = aws_dynamodb_table.reports.hash_key
      REPORT_SORT_KEY      = aws_dynamodb_table.reports.range_key
      BEDROCK_MODEL_ID     = var.bedrock_model_id
    }
  }

  depends_on = [aws_iam_role_policy.analyzer, aws_ecr_repository_policy.analyzer]
}

resource "aws_lambda_function_event_invoke_config" "analyzer" {
  count                        = local.worker_enabled ? 1 : 0
  function_name                = aws_lambda_function.analyzer[0].function_name
  maximum_event_age_in_seconds = 3600
  maximum_retry_attempts       = 2

  destination_config {
    on_failure {
      destination = aws_sqs_queue.analysis_failures.arn
    }
  }
}

resource "aws_lambda_permission" "s3_upload" {
  count          = local.worker_enabled ? 1 : 0
  statement_id   = "AllowImageBucketInvocation"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.analyzer[0].function_name
  principal      = "s3.amazonaws.com"
  source_arn     = data.aws_s3_bucket.images.arn
  source_account = local.account_id
}

resource "aws_s3_bucket_notification" "images" {
  count  = local.worker_enabled ? 1 : 0
  bucket = data.aws_s3_bucket.images.id

  lambda_function {
    id                  = "AnalyzeUploadedImage"
    lambda_function_arn = aws_lambda_function.analyzer[0].arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = var.image_prefix
  }

  depends_on = [aws_lambda_permission.s3_upload, aws_lambda_function_event_invoke_config.analyzer]
=======
provider "aws" {
  region              = "us-east-1"
  allowed_account_ids = ["379810014574"]

  default_tags {
    tags = {
      Environment = "dev"
      ManagedBy   = "Terraform"
      Project     = "gridguardian"
    }
  }
>>>>>>> 230aa06 (updated terraform directory so its more intuitive):terraform/providers.tf
}
