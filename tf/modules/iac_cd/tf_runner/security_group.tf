# VPC and subnet datasources for CodeBuild VPC configuration
data "aws_vpc" "main" {
  filter {
    name   = "tag:Name"
    values = [local.conventional_coreinfra_vpc_name]
  }
}

data "aws_ssm_parameter" "public_subnet_ids" {
  name = "/coreinfra/shared/public_subnet_ids"
}

locals {
  conventional_coreinfra_vpc_name = "${var.org}-${var.env}"
  public_subnet_ids               = split(",", data.aws_ssm_parameter.public_subnet_ids.value)
}

# Security group for CodeBuild terraform runner
# This security group is used by all CodeBuild projects (plan, apply, apply_auto)
# to access VPC resources like RDS databases during terraform operations.
#
# Specifically, this is needed for:
# - croft_base module: The bootstrap process that grants rds_iam role to the master user
# - croft_app module: Creating per-app databases and roles via the postgresql provider
resource "aws_security_group" "terraform_runner" {
  name        = "${var.org}-${var.app}-${var.env}-terraform-runner"
  description = "Security group for terraform runner CodeBuild projects - allows access to VPC resources"
  vpc_id      = data.aws_vpc.main.id

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${var.org}-${var.app}-${var.env}-terraform-runner"
  })
}
