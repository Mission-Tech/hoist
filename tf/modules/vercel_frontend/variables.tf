# ------------------------------------
# -----------  Common inputs -----------
# ------------------------------------

variable "app" {
  description = "Name of the application"
  type        = string
}

variable "env" {
  description = "Name of the environment (dev or prod)"
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

variable "public_app_name" {
  description = "Public-facing name for the app. Will appear as the subdomain for the custom domain (e.g., 'pantry' for pantry.missiontechdev.org)"
  type        = string
}

variable "domain_cname_value" {
  description = "Vercel domain to point to (e.g., 'cname.vercel-dns.com')"
  type        = string
}