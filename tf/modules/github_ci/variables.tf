# ------------------------------------
# -----------  Common tags -----------
# ------------------------------------

variable "app" {
    description = "Name of the application"
    type        = string
}

variable "env" {
    description = "Environment name (dev, prod)"
    type        = string
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
    description = "Additional tags to apply to every resource"
    type = map(string)
}

locals {
    tags = merge(var.tags, {
            app: var.app
            env: var.env
            org: var.org
            repo: var.repo
        })
}

# -------------------------------------------------
# ----------- Module-specific variables -----------
# -------------------------------------------------

variable "github_org" {
    description = "GitHub organization name for commit links"
    type        = string
}

variable "github_oidc_provider_arn" {
    description = "ARN of the GitHub OIDC provider. If not provided, will assume it by convention."
    type        = string
    default     = ""
}
