# Cleanup Lambda Function

This Lambda function automatically cleans up old ECR images and AppSpec files after successful CodeDeploy deployments, while protecting artifacts from recent successful deployments.

## Purpose

The cleanup Lambda solves a critical problem: preventing the deletion of artifacts needed for rollback to the last known good deployment state.

### The Problem It Solves

Without intelligent cleanup, you could face this disaster scenario:

1. You have 15 failed deployments in a row (v2 through v16)
2. Your last successful deployment was v1
3. A new successful deployment (v17) triggers cleanup
4. Simple cleanup logic deletes images 1-7 (keeping only the last 10)
5. **Disaster**: You've deleted v1, your last known good state!
6. You can no longer rollback to a working version

## How It Works

The cleanup Lambda:

1. **Triggered by**: EventBridge rule on successful CodeDeploy deployments
2. **Queries**: CodeDeploy history for the last 3 successful deployments
3. **Protects**: ECR images and AppSpec files from those successful deployments
4. **Retains**: The 10 most recent artifacts (configurable)
5. **Deletes**: Only old artifacts that aren't from successful deployments

## Configuration

Environment variables:
- `ECR_REPOSITORY_NAME`: ECR repository to clean
- `APPSPEC_BUCKET_NAME`: S3 bucket containing AppSpec files
- `CODEDEPLOY_APP_NAME`: CodeDeploy application name
- `CODEDEPLOY_GROUP_NAME`: CodeDeploy deployment group name
- `RETAIN_COUNT`: Number of recent artifacts to keep (default: 10)
- `SUCCESSFUL_DEPLOY_RETAIN`: Number of successful deployments to protect (default: 3)

## Protection Logic

### ECR Images
- Keeps the 10 most recent images
- PLUS protects all images from the last 3 successful deployments
- Extracts image tags from deployment descriptions using regex

### AppSpec Files
- Keeps the 10 most recent AppSpec files
- PLUS protects all AppSpec files from the last 3 successful deployments
- Gets S3 keys directly from deployment revision data

## Example Scenario

```
Current ECR images (newest first):
- v20 (current deployment)
- v19 (failed)
- v18 (failed)
- v17 (failed)
- v16 (failed)
- v15 (successful) ← Protected
- v14 (failed)
- v13 (failed)
- v12 (failed)
- v11 (failed)
- v10 (failed)
- v9 (failed)
- v8 (successful) ← Protected
- v7 (failed)
- v6 (failed)
- v5 (failed)
- v4 (failed)
- v3 (failed)
- v2 (failed)
- v1 (successful) ← Protected

Cleanup will:
- Keep v20-v11 (10 most recent)
- Keep v15, v8, v1 (successful deployments)
- Delete v10, v9, v7, v6, v5, v4, v3, v2 (old + not successful)
```

## Testing

Run the unit tests:

```bash
cd cleanup_lambda
python -m unittest test_cleanup.py -v
```

The tests use mocked boto3 clients to verify:
- Successful deployment artifact extraction
- Protection logic for ECR images
- Protection logic for AppSpec files
- Error handling
- Integration of all components

## IAM Permissions

The Lambda requires:
- ECR: `DescribeImages`, `ListImages`, `BatchDeleteImage`
- S3: `ListBucket`, `GetObject`, `DeleteObject`
- CodeDeploy: `ListDeployments`, `GetDeployment`
- CloudWatch Logs: Standard Lambda logging permissions

## Monitoring

The Lambda logs detailed information about:
- Number of successful deployments found
- Protected artifacts (with reasons)
- Artifacts deleted
- Any errors encountered

Check CloudWatch Logs for the function execution details.