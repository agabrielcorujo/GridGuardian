# Mocked provider: no AWS credentials or real resource creation.
mock_provider "aws" {
  mock_data "aws_s3_bucket" {
    defaults = {
      id  = "grid-guardian-images"
      arn = "arn:aws:s3:::grid-guardian-images"
    }
  }
  mock_data "aws_dynamodb_table" {
    defaults = {
      name      = "GridGuardian"
      arn       = "arn:aws:dynamodb:us-east-1:123456789012:table/GridGuardian"
      hash_key  = "report_id"
      range_key = ""
    }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/gridguardian-dev-analyzer" }
  }
  mock_resource "aws_lambda_function" {
    defaults = { arn = "arn:aws:lambda:us-east-1:123456789012:function:gridguardian-dev-image-analyzer" }
  }
  mock_resource "aws_sqs_queue" {
    defaults = { arn = "arn:aws:sqs:us-east-1:123456789012:gridguardian-dev-analysis-failures" }
  }
  mock_resource "aws_ecr_repository" {
    defaults = {
      repository_url = "123456789012.dkr.ecr.us-east-1.amazonaws.com/gridguardian-dev-image-analyzer"
    }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_ecr_image" {
    defaults = { image_digest = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }
  }
}

run "bootstrap_without_image" {
  command = plan

  assert {
    condition     = length(aws_lambda_function.analyzer) == 0 && length(aws_s3_bucket_notification.images) == 0
    error_message = "Bootstrap must not create Lambda or its trigger before the image exists."
  }
  assert {
    condition     = data.aws_dynamodb_table.reports.hash_key == "report_id" && data.aws_dynamodb_table.reports.name == "GridGuardian" && data.aws_s3_bucket.images.bucket == "grid-guardian-images"
    error_message = "The stack must reference the existing image bucket and reports table with report_id."
  }
}

run "worker_with_image" {
  # Resolve computed repository URLs and image digests using the mock provider.
  command = apply
  variables {
    image_tag = "test-commit"
  }
  assert {
    condition     = length(aws_lambda_function.analyzer) == 1 && length(aws_lambda_permission.s3_upload) == 1 && length(aws_s3_bucket_notification.images) == 1
    error_message = "An image tag must enable Lambda and its authorized S3 trigger."
  }
  assert {
    condition     = aws_lambda_function.analyzer[0].environment[0].variables["REPORT_ID_KEY"] == "report_id" && aws_lambda_function.analyzer[0].environment[0].variables["REPORTS_TABLE"] == "GridGuardian"
    error_message = "The worker must receive the existing table name and actual partition key."
  }
  assert {
    condition     = endswith(aws_lambda_function.analyzer[0].image_uri, "@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
    error_message = "Lambda must use the resolved image digest."
  }
  assert {
    condition     = length(aws_lambda_function_event_invoke_config.analyzer) == 1 && aws_lambda_function_event_invoke_config.analyzer[0].maximum_retry_attempts == 2
    error_message = "The worker must configure retries and a failure destination."
  }
}
