output "api_function_name" {
  value = aws_lambda_function.api.function_name
}

output "api_function_arn" {
  value = aws_lambda_function.api.arn
}

output "ecr_repository_url" {
  value = aws_ecr_repository.analyzer.repository_url
}

output "github_ecr_push_role_arn" {
  value = aws_iam_role.github_ecr_push.arn
}

output "reports_table_name" {
  value = aws_dynamodb_table.reports.name
}

output "analysis_failure_queue_url" {
  value = aws_sqs_queue.analysis_failures.url
}

output "images_bucket_name" {
  value = "grid-guardian-images"
}

output "image_upload_prefix" {
  value = "images/"
}
