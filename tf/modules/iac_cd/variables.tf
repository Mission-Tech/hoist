# ------------------------------------
# -----------  Common tags -----------
# ------------------------------------

variable "app" {
    description = "Name of the application"
    type        = string
}

locals {
    env = "tools" # only to be applied in tools environment
}

variable "org" {
    description = "The name of your organization (e.g., missiontech)"
    type        = string
}

variable "repo" {
    description = "The URL of the github repo managing this infrastructure"
    type        = string
}

variable tags {
    description = "Tags to apply to every resource"
    type = map(string)
}

locals {
    tags = merge(var.tags, {
        app: var.app
        env: local.env
        org: var.org
        repo: var.repo
    })
}

# -------------------------------------------------
# ----------- Module-specific variables -----------
# -------------------------------------------------

variable "ci_role_name" {
    description = "The name of the role that CI assumes"
    type        = string
}

variable "github_oidc_provider_arn" {
    description = "ARN of the GitHub OIDC provider. If not provided, will assume it by convention"
    type        = string
    default     = ""
}

variable "dev_account_id" {
    description = "AWS Account ID for the dev account"
    type        = string
}

variable "prod_account_id" {
    description = "AWS Account ID for the prod account"
    type        = string
}

variable "slack_cd_webhook_url" {
    description = "Slack webhook URL for CD notifications"
    type        = string
    sensitive   = true
}

variable "opentofu_version" {
    description = "Version of OpenTofu to use in Lambda functions"
    type        = string
}

variable "github_org" {
    description = "GitHub organization name"
    type        = string
}

