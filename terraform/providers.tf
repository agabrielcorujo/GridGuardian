data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

locals {
  name              = "${var.project_name}-${var.environment}"
  function_name     = "${local.name}-image-analyzer"
  partition         = data.aws_partition.current.partition
  account_id        = data.aws_caller_identity.current.account_id
  worker_enabled    = var.image_tag != null
  foundation_model  = trimprefix(var.bedrock_model_id, "us.")
  inference_profile = "arn:${local.partition}:bedrock:${var.aws_region}:${local.account_id}:inference-profile/${var.bedrock_model_id}"
  foundation_models = "arn:${local.partition}:bedrock:us-*::foundation-model/${local.foundation_model}"
}

# The existing image bucket remains outside Terraform management.
data "aws_s3_bucket" "images" {
  bucket = var.images_bucket_name
}

# The tag must already exist; resolve it to a digest for reproducible deployments.
data "aws_ecr_image" "analyzer" {
  count           = local.worker_enabled ? 1 : 0
  repository_name = aws_ecr_repository.analyzer.name
  image_tag       = var.image_tag
}

provider "aws" {
  region              = var.aws_region
  allowed_account_ids = ["379810014574"]

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}
