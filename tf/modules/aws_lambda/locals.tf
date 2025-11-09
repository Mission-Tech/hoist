# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Local variables
locals {
  org = "missiontech"

  # Custom domain configuration
  subdomain             = coalesce(var.public_app_name, var.app)
  custom_domain_name    = "${local.subdomain}.${data.aws_route53_zone.primary.name}"
}