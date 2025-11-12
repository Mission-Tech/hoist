variable "app" {
  description = "Name of the application"
  type        = string
}

variable "env" {
  description = "Name of the environment (dev or prod)"
  type        = string
}

variable "public_app_name" {
  description = "Public-facing name for the app. Will appear as the subdomain for the custom domain (e.g., 'pantry' for pantry.missiontechdev.org)"
  type        = string
}

variable "domain_cname_value" {
  description = "Vercel domain to point to (e.g., 'cname.vercel-dns.com')"
  type        = string
}
