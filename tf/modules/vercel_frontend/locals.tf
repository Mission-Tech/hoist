# Local variables
locals {
  org = "missiontech"

  # Custom domain configuration
  custom_domain_name = "${var.public_app_name}.${data.aws_route53_zone.primary.name}"
}
