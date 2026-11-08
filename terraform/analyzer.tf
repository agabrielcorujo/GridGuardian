resource "aws_cloudwatch_log_group" "analyzer" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = 14
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
}
