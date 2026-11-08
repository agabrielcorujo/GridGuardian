resource "aws_sqs_queue" "analysis_failures" {
  name                       = "gridguardian-dev-analysis-failures"
  message_retention_seconds  = 1209600
  visibility_timeout_seconds = 30
  max_message_size           = 262144
  sqs_managed_sse_enabled    = true
}
