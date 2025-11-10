# AWS AppConfig Application
resource "aws_appconfig_application" "main" {
  name        = "${var.app}-${var.env}"
  description = "AppConfig application for ${var.app} in ${var.env} environment"

  tags = {
    Application = var.app
    Environment = var.env
    Module      = "aws_lambda"
  }
}

# AWS AppConfig Environment
resource "aws_appconfig_environment" "main" {
  application_id = aws_appconfig_application.main.id
  name           = var.env
  description    = "AppConfig environment for ${var.app}-${var.env}"

  tags = {
    Application = var.app
    Environment = var.env
    Module      = "aws_lambda"
  }
}

# AWS AppConfig Configuration Profile for unencrypted config
resource "aws_appconfig_configuration_profile" "config" {
  application_id = aws_appconfig_application.main.id
  name           = "config"
  description    = "Unencrypted configuration for ${var.app}-${var.env}"
  location_uri   = "hosted"
  type           = "AWS.Freeform"

  tags = {
    Application = var.app
    Environment = var.env
    Module      = "aws_lambda"
    ConfigType  = "unencrypted"
  }
}

# AWS AppConfig Configuration Profile for encrypted secrets
resource "aws_appconfig_configuration_profile" "secrets" {
  application_id = aws_appconfig_application.main.id
  name           = "secrets"
  description    = "Encrypted secrets for ${var.app}-${var.env}"
  location_uri   = "hosted"
  type           = "AWS.Freeform"

  # Use default KMS key from coreinfra for encryption
  kms_key_identifier = data.aws_kms_key.default.arn

  tags = {
    Application = var.app
    Environment = var.env
    Module      = "aws_lambda"
    ConfigType  = "encrypted"
  }
}

# AWS AppConfig Deployment Strategy
# Using a predefined strategy for quick rollout
resource "aws_appconfig_deployment_strategy" "main" {
  name                           = "${var.app}-${var.env}-quick"
  description                    = "Quick deployment strategy for ${var.app}-${var.env}"
  deployment_duration_in_minutes = 0
  growth_factor                  = 100
  replicate_to                   = "NONE"
  final_bake_time_in_minutes     = 0

  tags = {
    Application = var.app
    Environment = var.env
    Module      = "aws_lambda"
  }
}
