variable "project_name" {
  description = "Project name for our deployment"
  type        = string
  # default     = "aws_serverless_ecommerce_analytics"
  default = "aws-serverless-ecommerce-analytics"

}

variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}


variable "aws_region" {
  description = "AWS region where our deployment will be applied"
  type        = string
  default     = "us-east-1"

}

variable "enable_force_destroy" {
  description = "Enable force destroy on S3 buckets (dev only)"
  type        = bool
  default     = false
}

variable "alert_email" {
  description = "email address to which budget and monitoring alarms are sent"
  type        = string
  default     = "ellon.solomon@gmail.com"

}

