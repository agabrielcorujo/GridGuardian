# Adopt the API resources already created from the api branch into the
# aws-infra state. Import blocks are safe to retain after a successful import.
import {
  to = aws_lambda_function.api
  id = "GridGuardianAPI"
}

import {
  to = aws_iam_role.api
  id = "${local.name}-api"
}

import {
  to = aws_iam_role_policy.api
  id = "${local.name}-api:serve-reports"
}

import {
  to = aws_cloudwatch_log_group.api
  id = "/aws/lambda/GridGuardianAPI"
}

import {
  to = aws_iam_role_policy.github_api_deploy
  id = "${local.name}-github-ecr-push:deploy-gridguardian-api"
}
