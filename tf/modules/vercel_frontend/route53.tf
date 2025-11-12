# Route53 CNAME record to point custom domain to Vercel
resource "aws_route53_record" "frontend" {
  zone_id = data.aws_ssm_parameter.primary_hosted_zone_id.value
  name    = local.custom_domain_name
  type    = "CNAME"
  ttl     = 300
  records = [var.domain_cname_value]
}
