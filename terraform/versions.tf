terraform {
<<<<<<< HEAD
  required_version = ">= 1.7.0, < 2.0.0"

=======
  required_version = ">= 1.5.0, < 2.0.0"
>>>>>>> 230aa06 (updated terraform directory so its more intuitive)
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.72.0"
    }
  }
}
<<<<<<< HEAD

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
=======
>>>>>>> 230aa06 (updated terraform directory so its more intuitive)
