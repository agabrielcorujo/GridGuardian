output "images_bucket_name" {
  description = "Existing bucket for original inspection images."
  value       = data.aws_s3_bucket.images.id
}

output "image_upload_prefix" {
  description = "Upload images under this prefix to trigger analysis once the worker is deployed."
  value       = var.image_prefix
}

output "reports_table_name" {
  description = "Existing DynamoDB reports table; partition key is report_id (String)."
  value       = data.aws_dynamodb_table.reports.name
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
  value = aws_cloudwatch_log_group.analyzer.name
}

output "analysis_failure_queue_url" {
  description = "Failed invocation records for investigation and manual replay."
  value       = aws_sqs_queue.analysis_failures.url
}
