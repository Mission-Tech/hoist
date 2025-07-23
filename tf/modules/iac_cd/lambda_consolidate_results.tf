# Simple Lambda execution role for consolidate results
resource "aws_iam_role" "lambda_consolidate_simple" {
    name = "${var.org}-${var.app}-${local.env}-lambda-consolidate"
    
    assume_role_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Action = "sts:AssumeRole"
                Effect = "Allow"
                Principal = {
                    Service = "lambda.amazonaws.com"
                }
            }
        ]
    })
    
    tags = local.tags
}

# Policy for Lambda basic execution
resource "aws_iam_role_policy_attachment" "lambda_consolidate_basic" {
    role       = aws_iam_role.lambda_consolidate_simple.name
    policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Policy for consolidate results Lambda
resource "aws_iam_role_policy" "lambda_consolidate_simple" {
    name = "consolidate-results-policy"
    role = aws_iam_role.lambda_consolidate_simple.id
    
    policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Effect = "Allow"
                Action = "s3:GetObject"
                Resource = "${aws_s3_bucket.tf_artifacts.arn}/*"
            },
            {
                Effect = "Allow"
                Action = [
                    "codepipeline:PutJobSuccessResult",
                    "codepipeline:PutJobFailureResult"
                ]
                Resource = "*"
            },
            {
                Effect = "Allow"
                Action = [
                    "logs:DescribeLogStreams",
                    "logs:GetLogEvents"
                ]
                Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/*"
            }
        ]
    })
}

# Simple inline Lambda function
resource "aws_lambda_function" "consolidate_simple" {
    function_name = "${var.org}-${var.app}-tools-consolidate"
    role         = aws_iam_role.lambda_consolidate_simple.arn
    handler      = "index.lambda_handler"
    runtime      = "python3.11"
    architectures = ["arm64"]
    timeout      = 60
    memory_size  = 256

    environment {
        variables = {
            SLACK_WEBHOOK_URL = var.slack_cd_webhook_url
        }
    }

    filename         = data.archive_file.lambda_consolidate_simple.output_path
    source_code_hash = data.archive_file.lambda_consolidate_simple.output_base64sha256

    tags = local.tags
}

# Create the Lambda deployment package
data "archive_file" "lambda_consolidate_simple" {
    type        = "zip"
    output_path = "${path.module}/.terraform/lambda-consolidate.zip"

    source {
        content  = <<-EOF
import json
import boto3
import os
import zipfile
import io
import urllib3
import re

s3 = boto3.client('s3')
codepipeline = boto3.client('codepipeline')
http = urllib3.PoolManager()

def lambda_handler(event, context):
    print(f"Event: {json.dumps(event)}")
    
    # Extract CodePipeline job data
    job = event['CodePipeline.job']
    job_id = job['id']
    job_data = job['data']
    
    # Process input artifacts to get plan results
    results = {}
    all_success = True
    
    for artifact in job_data['inputArtifacts']:
        bucket = artifact['location']['s3Location']['bucketName']
        key = artifact['location']['s3Location']['objectKey']
        
        # Extract environment from artifact name (e.g., "dev_plan_output" -> "dev")
        env = artifact['name'].replace('_plan_output', '')
        
        try:
            # Download and parse the summary from the artifact
            obj = s3.get_object(Bucket=bucket, Key=key)
            zip_data = obj['Body'].read()
            
            with zipfile.ZipFile(io.BytesIO(zip_data), 'r') as zip_ref:
                if 'summary.json' in zip_ref.namelist():
                    with zip_ref.open('summary.json') as f:
                        summary = json.load(f)
                        results[env] = {
                            'success': summary.get('success', False),
                            'plan_output': summary.get('plan_output', '')
                        }
                        if not summary.get('success', False):
                            all_success = False
                            
                        # Extract resource changes from plan output
                        plan_output = summary.get('plan_output', '')
                        added = len(re.findall(r'will be created', plan_output))
                        changed = len(re.findall(r'will be updated in-place', plan_output))
                        destroyed = len(re.findall(r'will be destroyed', plan_output))
                        
                        results[env]['added'] = added
                        results[env]['changed'] = changed
                        results[env]['destroyed'] = destroyed
                else:
                    print(f"No summary.json found in {env} artifact")
                    results[env] = {
                        'success': False,
                        'added': 0,
                        'changed': 0,
                        'destroyed': 0,
                        'plan_output': 'No summary.json found'
                    }
                    all_success = False
                    
        except Exception as e:
            print(f"Error processing {env}: {str(e)}")
            # Check if it's a missing artifact (build failed)
            if 'NoSuchKey' in str(e):
                results[env] = {
                    'success': False,
                    'added': 0,
                    'changed': 0,
                    'destroyed': 0,
                    'plan_output': 'Build failed - no artifact produced'
                }
            else:
                results[env] = {
                    'success': False,
                    'added': 0,
                    'changed': 0,
                    'destroyed': 0,
                    'plan_output': f'Error: {str(e)}'
                }
            all_success = False
    
    # Send Slack notification
    try:
        send_slack_notification(results, all_success, context.aws_request_id)
    except Exception as e:
        print(f"Failed to send Slack notification: {e}")
    
    # Report success to CodePipeline
    codepipeline.put_job_success_result(jobId=job_id)
    
    return {'statusCode': 200, 'body': 'Success'}


def send_slack_notification(results, all_success, execution_id):
    webhook_url = os.environ.get('SLACK_WEBHOOK_URL')
    if not webhook_url:
        print("No Slack webhook URL configured")
        return
    
    # Build message blocks
    blocks = []
    
    # Header
    status_emoji = "✅" if all_success else "❌"
    header_text = f"{status_emoji} Terraform Plan {'Succeeded' if all_success else 'Failed'}"
    blocks.append({
        "type": "header",
        "text": {
            "type": "plain_text",
            "text": header_text
        }
    })
    
    # Environment results
    for env in ['dev', 'prod', 'tools']:
        if env in results:
            result = results[env]
            env_emoji = "✅" if result['success'] else "❌"
            
            # Build resource change summary
            changes = []
            if result['added'] > 0:
                changes.append(f"+{result['added']}")
            if result['changed'] > 0:
                changes.append(f"~{result['changed']}")
            if result['destroyed'] > 0:
                changes.append(f"-{result['destroyed']}")
            
            change_summary = f" ({', '.join(changes)})" if changes else " (no changes)"
            
            blocks.append({
                "type": "section",
                "text": {
                    "type": "mrkdwn",
                    "text": f"{env_emoji} *{env.upper()}*{change_summary}"
                },
                "accessory": {
                    "type": "button",
                    "text": {
                        "type": "plain_text",
                        "text": "View Logs"
                    },
                    "url": f"https://console.aws.amazon.com/codesuite/codebuild/projects?region=us-east-1"
                }
            })
    
    # Send to Slack
    slack_message = {"blocks": blocks}
    
    response = http.request(
        'POST',
        webhook_url,
        body=json.dumps(slack_message),
        headers={'Content-Type': 'application/json'}
    )
    
    if response.status != 200:
        raise Exception(f"Slack request failed with status {response.status}: {response.data}")
EOF
        filename = "index.py"
    }
}
