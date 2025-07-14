variable "app" {
  description = "Name of the application"
  type        = string
}

variable "dev_account_id" {
  description = "AWS account ID for dev environment"
  type        = string
}

variable "dev_region" {
  description = "AWS region for dev environment"
  type        = string
}

variable "prod_account_id" {
  description = "AWS account ID for prod environment"
  type        = string
}

variable "prod_region" {
  description = "AWS region for prod environment"
  type        = string
}