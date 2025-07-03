variable "tfstate_access_role_name" {
  description = "Name of the IAM role that needs access to Terraform state S3 bucket and DynamoDB table"
  type        = string
  default     = ""
}

variable "env" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
}

variable "app" {
  description = "Application name"
  type        = string
  default     = ""
}

variable "org" {
    description = "Organization name"
    type        = string
    default     = ""
}
