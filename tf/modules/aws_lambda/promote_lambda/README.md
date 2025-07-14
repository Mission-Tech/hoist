# Promote Lambda Function

This Lambda function promotes deployments from dev to prod by validating the latest successful dev deployment and triggering a corresponding prod deployment with the same container.

## How It Works

1. **Assumes cross-account role** in dev account
2. **Finds latest successful CodeDeploy deployment** in dev
3. **Extracts container info** (image tag and SHA256) from the deployment
4. **Verifies same container exists in prod ECR** with matching SHA256
5. **Triggers manual deployment Lambda** in prod with the validated container

## Configuration

Environment variables:
- `APP_NAME`: Application name
- `ENV_NAME`: Environment name (prod)
- `DEV_ACCOUNT_ID`: Dev AWS account ID
- `MANUAL_DEPLOY_FUNCTION_NAME`: Manual deploy Lambda function name
- `AWS_REGION`: AWS region

## Usage

Invoke with:
```json
{
  "release_tag": "v1.2.0"
}
```

Returns success with deployment details or error if validation fails.

## Cross-Account Setup

**Dev account**: Creates cross-account role trusting prod promote Lambda
**Prod account**: Creates promote Lambda with permission to assume dev role

## Testing

```bash
# Navigate to the promote lambda directory
cd tf/modules/aws_lambda/promote_lambda

# Create and activate virtual environment
python3 -m venv venv
source venv/bin/activate

# Install test dependencies
pip install -r requirements_test.txt

# Run the tests
python test_promote.py
```

Expected output: `Ran 15 tests in 0.019s OK`

## IAM Permissions

**Dev cross-account role**: CodeDeploy read, S3 read (AppSpec), Lambda read, ECR read
**Prod promote Lambda**: STS assume role, ECR read, Lambda invoke