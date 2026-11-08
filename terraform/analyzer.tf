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
