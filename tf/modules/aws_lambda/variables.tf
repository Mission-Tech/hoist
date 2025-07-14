variable "app" {
  description = "Name of the application"
  type        = string
}

variable "env" {
  description = "Name of the environment (dev or prod)"
  type        = string
}

variable "ci_assume_role_name" {
    description = "Name of the role that CI will assume. Necessary because we need to give it additional permissions."
    type = string
}

variable "error_rate_threshold" {
  description = "Number of errors that trigger the CloudWatch alarm during deployment"
  type        = number
  default     = 10
}

variable "ecr_image_tag_trigger" {
  description = "ECR image tag that triggers deployments (e.g., 'latest', 'prod')"
  type        = string
  default     = "latest"
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 30
}

variable "lambda_memory_size" {
  description = "Lambda function memory size in MB"
  type        = number
  default     = 512
}

variable "dev_account_id" {
  description = "AWS account ID for dev environment (used in prod to read dev deployments)"
  type        = string
  default     = null
}

variable "prod_account_id" {
  description = "AWS account ID for prod environment (used in dev to create cross-account role)"
  type        = string
  default     = null
}

