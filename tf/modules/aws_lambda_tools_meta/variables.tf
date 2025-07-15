variable "app" {
  description = "Name of the application"
  type        = string
}

variable "ci_assume_role_name" {
  description = "Name of the CI role that needs aws_lambda_tools permissions attached"
  type        = string
}