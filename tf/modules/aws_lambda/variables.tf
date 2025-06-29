variable "app" {
  description = "Name of the application"
  type        = string
}

variable "env" {
  description = "Name of the environment (e.g., dev, staging, prod)"
  type        = string
}

variable "ci_assume_role_name" {
    description = "Name of the role that CI will assume. Necessary because we need to give it additional permissions."
    type = string
}
