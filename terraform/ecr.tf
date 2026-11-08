resource "aws_ecr_repository" "analyzer" {
  name                 = "gridguardian-dev-image-analyzer"
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_repository_policy" "analyzer" {
  repository = aws_ecr_repository.analyzer.name
  policy = jsonencode({
    "Statement" : [
      {
        "Action" : [
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer"
        ],
        "Condition" : {
          "ArnLike" : {
            "aws:SourceArn" : [
              "arn:aws:lambda:us-east-1:379810014574:function:gridguardian-dev-image-analyzer",
              "arn:aws:lambda:us-east-1:379810014574:function:GridGuardianAPI"
            ]
          }
        },
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "lambda.amazonaws.com"
        },
        "Sid" : "LambdaImageRetrieval"
      }
    ],
    "Version" : "2012-10-17"
  })
}
