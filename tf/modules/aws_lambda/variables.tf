variable "app" {
  description = "Name of the application"
  type        = string
}

variable "env" {
  description = "Name of the environment (dev or prod)"
  type        = string
}

variable "org" {
  description = "Name of the organization (e.g. missiontech)"
  type        = string
}

variable "repo" {
  description = "The URL of the github repo managing this infrastructure"
  type        = string
}

variable "tags" {
  description = "Tags to apply to every resource"
  type        = map(string)
}

locals {
  tags = merge(var.tags, {
    app : var.app
    env : var.env
    org : var.org
    repo : var.repo
  })
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

variable "public_app_name" {
  description = "Public-facing name for the app. Will appear as the subdomain for the custom domain (e.g., 'myapp' for myapp.missiontech.org). Defaults to the app name."
  type        = string
  default     = null
}

variable "enable_migrations" {
  description = "Enable database migrations via CodeBuild"
  type        = bool
  default     = false
}
