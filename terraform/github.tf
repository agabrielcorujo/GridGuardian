resource "aws_iam_openid_connect_provider" "github" {
  count           = 1 # Preserve the existing github[0] state address.
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["ab9d0263244dd0326eb67015705a667e79cfe998"]

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

resource "aws_iam_role_policy" "github_api_deploy" {
  name = "deploy-gridguardian-api"
  role = aws_iam_role.github_ecr_push.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "DeployAPIImage"
      Effect   = "Allow"
      Action   = ["lambda:GetFunction", "lambda:GetFunctionConfiguration", "lambda:UpdateFunctionCode"]
      Resource = aws_lambda_function.api.arn
    }]
  })
}
