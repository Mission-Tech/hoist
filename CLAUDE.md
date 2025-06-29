# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Hoist** is the Mission Tech Application Bootstrapping Service - an infrastructure-as-code project that provides Terraform modules for quickly deploying containerized AWS Lambda functions with proper CI/CD integration.

## Architecture

The project consists of two main Terraform modules:

1. **`tf/modules/aws_lambda/`** - Main deployment module that creates:
   - ECR repository for Lambda container images
   - IAM roles and policies for CI/CD systems to push images
   - Lifecycle policies to manage image retention (keeps last 10 images)
   - Container image scanning on push

2. **`tf/modules/aws_lambda_meta/`** - Provides the minimum IAM permissions needed to apply the aws_lambda module

### Key Design Patterns

- **Container-based Lambda**: Uses ECR for storing Lambda container images rather than zip deployments
- **CI/CD Ready**: Includes IAM policies specifically for CI systems (like GitHub Actions) to deploy
- **Least Privilege**: IAM policies are scoped to specific resources using variable interpolation
- **Lifecycle Management**: ECR repositories automatically clean up old images

## Development Commands

Currently, there are no build/test/lint commands defined. The project contains:
- Terraform infrastructure code (no specific Terraform commands documented yet)
- Go module initialized (go.mod with Go 1.22.1) but no Go source code present

## Important Files

- `tf/modules/aws_lambda/variables.tf` - Defines all configurable inputs for the Lambda module
- `tf/modules/aws_lambda/iam_for_ci_runtime.tf` - CI/CD permissions for ECR push operations
- `tf/modules/aws_lambda_meta/iam_to_apply_this_module.tf` - Terraform execution permissions

## Module Usage Pattern

When using these modules, typically you would:
1. First apply the `aws_lambda_meta` module to get the necessary IAM permissions
2. Then apply the `aws_lambda` module with appropriate variables for your Lambda function

## Variables Required

Key variables for the aws_lambda module:
- `environment` - Environment name (e.g., dev, staging, prod)
- `aws_account_id` - AWS account ID
- `aws_region` - AWS region
- `repository_name` - ECR repository name
- `ci_role_name` - IAM role name for CI/CD system