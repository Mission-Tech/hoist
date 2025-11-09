# Route53 record to point custom domain to API Gateway
resource "aws_route53_record" "api" {
  zone_id = data.aws_ssm_parameter.primary_hosted_zone_id.value
  name    = local.custom_domain_name
  type    = "A"

  alias {
    name                   = aws_api_gateway_domain_name.main.regional_domain_name
    zone_id                = aws_api_gateway_domain_name.main.regional_zone_id
    evaluate_target_health = false
  }
}
