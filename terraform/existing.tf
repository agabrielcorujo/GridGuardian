# Restored from the existing local state because main.tf was empty.
# Keep these addresses: they already own the shared infrastructure.

resource "aws_dynamodb_table" "reports" {
  name         = "GridGuardian"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "zipcode"
  range_key    = "condition-timestamp"
  attribute {
    name = "condition-timestamp"
    type = "S"
  }
  attribute {
    name = "zipcode"
    type = "S"
  }
}

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

resource "aws_iam_openid_connect_provider" "github" {
  count           = 1 # Preserve the existing github[0] state address.
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["ab9d0263244dd0326eb67015705a667e79cfe998"]

}

resource "aws_iam_role" "analyzer" {
  name = "gridguardian-dev-analyzer"
  assume_role_policy = jsonencode({
    "Statement" : [
      {
        "Action" : "sts:AssumeRole",
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "lambda.amazonaws.com"
        }
      }
    ],
    "Version" : "2012-10-17"
  })
}

resource "aws_iam_role" "github_ecr_push" {
  name = "gridguardian-dev-github-ecr-push"
  assume_role_policy = jsonencode({
    "Statement" : [
      {
        "Action" : "sts:AssumeRoleWithWebIdentity",
        "Condition" : {
          "StringEquals" : {
            "token.actions.githubusercontent.com:aud" : "sts.amazonaws.com",
            "token.actions.githubusercontent.com:sub" : [
              "repo:agabrielcorujo@148304752/GridGuardian@1449534292:ref:refs/heads/main",
              "repo:agabrielcorujo@148304752/GridGuardian@1449534292:ref:refs/heads/aws-infra",
              "repo:agabrielcorujo@148304752/GridGuardian@1449534292:ref:refs/heads/api",
              "repo:agabrielcorujo/GridGuardian:ref:refs/heads/api"
            ]
          }
        },
        "Effect" : "Allow",
        "Principal" : {
          "Federated" : "arn:aws:iam::379810014574:oidc-provider/token.actions.githubusercontent.com"
        }
      }
    ],
    "Version" : "2012-10-17"
  })
}

resource "aws_iam_role_policy" "analyzer" {
  name = "image-analysis"
  role = aws_iam_role.analyzer.id
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Action" : [
          "s3:GetObject",
          "s3:GetObjectVersion"
        ],
        "Effect" : "Allow",
        "Resource" : "arn:aws:s3:::grid-guardian-images/images/*",
        "Sid" : "ReadUploadedImages"
      },
      {
        "Action" : [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem"
        ],
        "Effect" : "Allow",
        "Resource" : "arn:aws:dynamodb:us-east-1:379810014574:table/GridGuardian",
        "Sid" : "ReadAndWriteReports"
      },
      {
        "Action" : "bedrock:InvokeModel",
        "Effect" : "Allow",
        "Resource" : "arn:aws:bedrock:us-east-1:379810014574:inference-profile/us.amazon.nova-2-lite-v1:0",
        "Sid" : "InvokeNovaInferenceProfile"
      },
      {
        "Action" : "bedrock:InvokeModel",
        "Condition" : {
          "StringEquals" : {
            "bedrock:InferenceProfileArn" : "arn:aws:bedrock:us-east-1:379810014574:inference-profile/us.amazon.nova-2-lite-v1:0"
          }
        },
        "Effect" : "Allow",
        "Resource" : "arn:aws:bedrock:us-*::foundation-model/amazon.nova-2-lite-v1:0",
        "Sid" : "InvokeRoutedNovaModels"
      },
      {
        "Action" : "sqs:SendMessage",
        "Effect" : "Allow",
        "Resource" : "arn:aws:sqs:us-east-1:379810014574:gridguardian-dev-analysis-failures",
        "Sid" : "CaptureFailedAnalysis"
      }
    ]
  })
}

resource "aws_iam_role_policy" "github_ecr_push" {
  name = "publish-worker-image"
  role = aws_iam_role.github_ecr_push.id
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Action" : "ecr:GetAuthorizationToken",
        "Effect" : "Allow",
        "Resource" : "*",
        "Sid" : "AuthenticateToECR"
      },
      {
        "Action" : [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:CompleteLayerUpload",
          "ecr:GetDownloadUrlForLayer",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart"
        ],
        "Effect" : "Allow",
        "Resource" : "arn:aws:ecr:us-east-1:379810014574:repository/gridguardian-dev-image-analyzer",
        "Sid" : "PushWorkerImage"
      }
    ]
  })
}

resource "aws_sqs_queue" "analysis_failures" {
  name                       = "gridguardian-dev-analysis-failures"
  message_retention_seconds  = 1209600
  visibility_timeout_seconds = 30
  max_message_size           = 262144
  sqs_managed_sse_enabled    = true
}
