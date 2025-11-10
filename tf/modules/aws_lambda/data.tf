# Read DNS resources from coreinfra shared parameters
data "aws_ssm_parameter" "primary_hosted_zone_id" {
  name = "/coreinfra/shared/primary_hosted_zone_id"
}

data "aws_ssm_parameter" "primary_acm_certificate_arn" {
  name = "/coreinfra/shared/primary_acm_certificate_arn"
}

# Get the domain name from the hosted zone
data "aws_route53_zone" "primary" {
  zone_id = data.aws_ssm_parameter.primary_hosted_zone_id.value
}

# Look up default KMS key by alias
data "aws_kms_key" "default" {
  key_id = "alias/${local.conventional_coreinfra_default_kms_key_alias}"
}
