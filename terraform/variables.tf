variable "github_repository" {
  description = "GitHub owner/repository allowed to publish worker images through OIDC."
  type        = string
  default     = "agabrielcorujo/GridGuardian"

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "Use owner/repository without a URL prefix."
  }
}

variable "github_owner_id" {
  description = "Immutable numeric GitHub owner ID used in this repository's OIDC subject."
  type        = string
  default     = "148304752"

  validation {
    condition     = can(regex("^[0-9]+$", var.github_owner_id))
    error_message = "Use the numeric GitHub owner ID."
  }
}

variable "github_repository_id" {
  description = "Immutable numeric GitHub repository ID used in its OIDC subject."
  type        = string
  default     = "1449534292"

  validation {
    condition     = can(regex("^[0-9]+$", var.github_repository_id))
    error_message = "Use the numeric GitHub repository ID."
  }
}

variable "github_publish_branches" {
  description = "Branches trusted to assume the ECR publishing role. Keep aligned with workflow triggers and job condition."
  type        = list(string)
  default     = ["main", "aws-infra"]

  validation {
    condition     = length(var.github_publish_branches) > 0 && alltrue([for branch in var.github_publish_branches : length(trimspace(branch)) > 0])
    error_message = "Supply at least one nonempty branch name."
  }
}

variable "github_oidc_provider_arn" {
  description = "Existing GitHub OIDC provider ARN, or null to create the account's provider."
  type        = string
  default     = null

  validation {
    condition     = var.github_oidc_provider_arn == null ? true : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:oidc-provider/token\\.actions\\.githubusercontent\\.com$", var.github_oidc_provider_arn))
    error_message = "Supply the GitHub OIDC provider ARN or null."
  }
}

variable "aws_region" {
  description = "AWS Region for the stack and Bedrock source endpoint."
  type        = string
  default     = "us-east-1"
}

variable "images_bucket_name" {
  description = "Existing S3 image bucket in the deployment Region; Terraform does not manage its storage settings."
  type        = string
  default     = "grid-guardian-images"
}

variable "reports_table_name" {
  description = "Existing DynamoDB table to import and manage; keys are zipcode (String) and condition-timestamp (String)."
  type        = string
  default     = "GridGuardian"
}

variable "project_name" {
  description = "Lowercase project name used in AWS resource names."
  type        = string
  default     = "gridguardian"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,24}$", var.project_name))
    error_message = "Use 1-25 lowercase letters, digits, or hyphens, starting with a letter."
  }
}

variable "environment" {
  description = "Deployment environment used to separate resource names."
  type        = string
  default     = "dev"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,9}$", var.environment))
    error_message = "Use 1-10 lowercase letters, digits, or hyphens, starting with a letter."
  }
}

variable "image_tag" {
  description = "Existing immutable tag in this stack's ECR repository. Leave null for the initial infrastructure-only deployment. Keep set after enabling Lambda."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.image_tag == null ? true : can(regex("^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$", var.image_tag))
    error_message = "Supply a valid ECR tag, preferably a Git commit SHA, or null."
  }
}

variable "image_prefix" {
  description = "Only objects uploaded under this S3 prefix trigger analysis. Upload image files only under this prefix."
  type        = string
  default     = "images/"

  validation {
    condition     = length(var.image_prefix) > 0 && endswith(var.image_prefix, "/")
    error_message = "Use a nonempty prefix ending in /, such as images/."
  }
}

variable "bedrock_model_id" {
  description = "US cross-Region Nova inference profile used by the worker."
  type        = string
  default     = "us.amazon.nova-2-lite-v1:0"

  validation {
    condition     = can(regex("^us\\.amazon\\.nova-[a-z0-9.:-]+$", var.bedrock_model_id))
    error_message = "Use a US Amazon Nova inference profile ID, such as us.amazon.nova-2-lite-v1:0."
  }
}

variable "lambda_timeout" {
  description = "Maximum seconds for fetching, analyzing, and saving one invocation."
  type        = number
  default     = 180

  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900 && floor(var.lambda_timeout) == var.lambda_timeout
    error_message = "Lambda timeout must be a whole number between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Worker memory in MB."
  type        = number
  default     = 512

  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240 && floor(var.lambda_memory_size) == var.lambda_memory_size
    error_message = "Memory must be a whole number between 128 and 10240 MB."
  }
}
