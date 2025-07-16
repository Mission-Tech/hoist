variable "app" {
  description = "Name of the application"
  type        = string
}

variable "dev_region" {
  description = "AWS region for dev environment"
  type        = string
}

variable "prod_region" {
  description = "AWS region for prod environment"
  type        = string
}

variable "github_org" {
  description = "GitHub organization name for commit links"
  type        = string
}