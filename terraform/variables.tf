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
  description = "Existing DynamoDB table with report_id (String) as its partition key and no sort key."
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
