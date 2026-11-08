resource "aws_cloudwatch_log_group" "api" {
  name              = "/aws/lambda/GridGuardianAPI"
  retention_in_days = 14
}

resource "aws_iam_role" "api" {
  name = "${local.name}-api"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "api" {
  name = "serve-reports"
  role = aws_iam_role.api.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadAndCreateReports"
        Effect   = "Allow"
        Action   = ["dynamodb:Query", "dynamodb:PutItem"]
        Resource = aws_dynamodb_table.reports.arn
      },
      {
        Sid      = "ReadInspectionImages"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:GetObjectVersion"]
        Resource = "arn:aws:s3:::grid-guardian-images/images/*"
      },
      {
        Sid      = "WriteFunctionLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.api.arn}:*"
      }
    ]
  })
}

resource "aws_lambda_function" "api" {
  function_name = "GridGuardianAPI"
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.analyzer.repository_url}@${var.api_image_digest}"
  architectures = ["x86_64"]
  role          = aws_iam_role.api.arn
  memory_size   = 256
  timeout       = 15

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.reports.name
    }
  }

  # Terraform owns infrastructure; Actions owns releases after initial creation.
  lifecycle {
    ignore_changes = [image_uri]
  }

  depends_on = [
    aws_ecr_repository_policy.analyzer,
    aws_iam_role_policy.api,
    aws_cloudwatch_log_group.api,
  ]
}
