resource "aws_ecr_repository" "analyzer" {
  name                 = "${local.name}-image-analyzer"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = false

  encryption_configuration {
    encryption_type = "AES256"
  }

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
