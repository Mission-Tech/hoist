variable "app" {
  description = "Name of the application"
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
    env : "tools"
    org : var.org
    repo : var.repo
  })
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

variable "enable_migrations" {
  description = "Enable database migrations in the pipeline"
  type        = bool
  default     = false
}