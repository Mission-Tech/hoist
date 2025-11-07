#!/bin/bash
set -euo pipefail

# ssm-to-tfvars.sh - Generate terraform -var arguments from SSM Parameter Store
#
# This script fetches parameters from SSM and outputs them as terraform -var flags
# that can be used in command substitution.
#
# Usage:
#   terraform plan $(./ssm-to-tfvars.sh <org> <app> <env>)
#   terraform apply $(./ssm-to-tfvars.sh missiontech hoist prod) tfplan
#
# Or save to a shell function in your ~/.bashrc or ~/.zshrc:
#   tf-ssm() {
#     terraform "$@" $(./scripts/ssm-to-tfvars.sh "$ORG" "$APP" "$ENV")
#   }

if [ $# -ne 3 ]; then
    echo "Usage: $0 <org> <app> <env>" >&2
    echo "" >&2
    echo "Example:" >&2
    echo "  terraform plan \$(./ssm-to-tfvars.sh mission-tech hoist prod)" >&2
    exit 1
fi

ORG="$1"
APP="$2"
ENV="$3"

# Construct the parameter store prefix
PARAMETER_STORE_PREFIX="/${ORG}/${APP}/${ENV}/tf_runner"

# Set AWS profile based on org and env
export AWS_PROFILE="${ORG}-${ENV}"

# Validate that AWS CLI is available
if ! command -v aws &> /dev/null; then
    echo "Error: aws CLI not found. Please install the AWS CLI." >&2
    exit 1
fi

# Log to stderr so it doesn't interfere with the output
echo "Using AWS profile: $AWS_PROFILE" >&2
echo "Loading parameters from: $PARAMETER_STORE_PREFIX" >&2

# Fetch parameters and convert to -var flags
AWS_PROFILE="$AWS_PROFILE" aws ssm get-parameters-by-path \
    --path "$PARAMETER_STORE_PREFIX" \
    --recursive \
    --with-decryption \
    --query 'Parameters[*].[Name,Value]' \
    --output text | while IFS=$'\t' read -r name value; do
        # Strip the prefix to get just the variable name
        var_name=$(echo "$name" | sed "s|$PARAMETER_STORE_PREFIX/||")
        echo "Loaded: $var_name" >&2
        # Output as -var flag with proper quoting
        printf -- '-var=%q ' "$var_name=$value"
    done

# Note: The trailing space is intentional for easy concatenation
