terraform {
  required_version = ">=1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }

}

provider "aws" {
  region = var.aws_region
  # region = "us-east-1"

  default_tags {
    tags = local.common_tags
  }
}




# terraform {
#   required_version = ">= 1.0"

#   required_providers {
#     aws = {
#       source  = "hashicorp/aws"
#       version = "~> 5.0"
#     }
#     archive = {
#       source  = "hashicorp/archive"
#       version = "~> 2.0"
#     }
#     random = {
#       source  = "hashicorp/random"
#       version = "~> 3.0"
#     }
#   }

#   # Optional: Remote backend for team collaboration
#   # backend "s3" {
#   #   bucket = "terraform-state-bucket"
#   #   key    = "ecommerce-analytics/terraform.tfstate"
#   #   region = "us-east-1"
#   # }
# }

# provider "aws" {
#   region = var.aws_region

#   default_tags {
#     tags = local.common_tags
#   }
# }
