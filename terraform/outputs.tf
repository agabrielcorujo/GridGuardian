output "github_ecr_push_role_arn" {
  description = "Set the GitHub repository Actions variable AWS_ECR_PUSH_ROLE_ARN to this value."
  value       = aws_iam_role.github_ecr_push.arn
}

output "images_bucket_name" {
  description = "Existing bucket for original inspection images."
  value       = data.aws_s3_bucket.images.id
}

output "image_upload_prefix" {
  description = "Upload images under this prefix to trigger analysis once the worker is deployed."
  value       = var.image_prefix
}

output "reports_table_name" {
  description = "Managed DynamoDB reports table; keys are zipcode (String) and condition-timestamp (String)."
  value       = aws_dynamodb_table.reports.name
}

output "ecr_repository_url" {
  description = "Build and push the analysis worker image here before setting image_tag."
  value       = aws_ecr_repository.analyzer.repository_url
}

output "lambda_function_name" {
  description = "Null until an image_tag is supplied and Lambda is deployed."
  value       = try(aws_lambda_function.analyzer[0].function_name, null)
}

output "analysis_log_group" {
  description = "CloudWatch log group for Lambda execution and processing-stage logs."
  value       = aws_cloudwatch_log_group.analyzer.name
}

output "analysis_failure_queue_url" {
  description = "Failed invocation records for investigation and manual replay."
  value       = aws_sqs_queue.analysis_failures.url
}
