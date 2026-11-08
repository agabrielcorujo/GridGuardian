locals {
  # Repositories created after July 15, 2026 use IDs in the OIDC subject.
  github_oidc_subject_prefix = "repo:${split("/", var.github_repository)[0]}@${var.github_owner_id}/${split("/", var.github_repository)[1]}@${var.github_repository_id}"
}

# One GitHub OIDC provider per AWS account. Supply its ARN if it already exists.
resource "aws_iam_openid_connect_provider" "github" {
  count = var.github_oidc_provider_arn == null ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

resource "aws_iam_role" "github_ecr_push" {
  name = "${local.name}-github-ecr-push"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.github_oidc_provider_arn != null ? var.github_oidc_provider_arn : aws_iam_openid_connect_provider.github[0].arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = concat(
            [for branch in var.github_publish_branches : "${local.github_oidc_subject_prefix}:ref:refs/heads/${branch}"],
            [for branch in var.github_publish_branches : "repo:${var.github_repository}:ref:refs/heads/${branch}" if branch == "api"],
          )
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "github_ecr_push" {
  name = "publish-worker-image"
  role = aws_iam_role.github_ecr_push.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AuthenticateToECR"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Sid    = "PushWorkerImage"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:CompleteLayerUpload",
          "ecr:GetDownloadUrlForLayer",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart",
        ]
        Resource = aws_ecr_repository.analyzer.arn
      }
    ]
  })
}
