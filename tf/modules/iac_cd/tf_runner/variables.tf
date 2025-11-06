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

variable "root_module_dir" {
    description = "Directory path to the root terraform module (e.g., 'tf/app' for dev/prod, 'tf/tools' for tools)"
    type        = string
}

variable "enable_auto_apply" {
    description = "Whether to create the auto-apply CodeBuild project (should be false for production)"
    type        = bool
    default     = false
}

variable "pipeline_artifacts_kms_key_arn" {
    description = <<-EOF
      KMS key ARN for pipeline artifacts. If not provided, will read from /coreinfra/shared parameter store.

      Coreinfra passes this directly to avoid circular dependency (it both creates the parameter AND needs
      to create grants in the same apply). Apps like gometheus omit this and read from parameter store.
    EOF
    type        = string
    default     = null
}
