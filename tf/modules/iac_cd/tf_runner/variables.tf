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
    description = "Tags to apply to every resource"
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

variable "opentofu_version" {
    description = "Version of OpenTofu to use in Lambda functions"
    type        = string
}

variable "tools_account_id" {
    description = "AWS Account ID for the tools account"
    type        = string
}

variable "tools_codepipeline_role_arn" {
    description = "ARN of the CodePipeline role in the tools account that will invoke this Lambda"
    type        = string
}

variable "tfvars" {
    description = "Map of terraform variables to pass to the Lambda as environment variables"
    type        = map(string)
    default     = {}
}

variable "tfvars_sensitive" {
    description = "Map of sensitive terraform variables to store in Parameter Store"
    type        = map(string)
    default     = {}
    sensitive   = true
}

# Optional VPC configuration
variable "vpc_id" {
    description = "VPC ID for CodeBuild. If not provided, will try to look up by convention"
    type        = string
    default     = ""
}

variable "public_subnet_ids" {
    description = "Public subnet IDs for CodeBuild. If not provided, will try to look up by convention"
    type        = list(string)
    default     = []
}
