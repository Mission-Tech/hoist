# Read DNS resources from coreinfra shared parameters
data "aws_ssm_parameter" "primary_hosted_zone_id" {
  name = "/coreinfra/shared/primary_hosted_zone_id"
}

# Get the domain name from the hosted zone
data "aws_route53_zone" "primary" {
  zone_id = data.aws_ssm_parameter.primary_hosted_zone_id.value
}
