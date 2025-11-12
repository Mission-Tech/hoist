output "frontend_fqdn" {
  description = "The FQDN of the Route53 record"
  value       = aws_route53_record.frontend.fqdn
}
