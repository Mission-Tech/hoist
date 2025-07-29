# SNS topic for manual approval notifications
resource "aws_sns_topic" "manual_approval" {
    name = "${var.org}-${var.app}-${local.env}-manual-approval"
    tags = local.tags
}

# Lambda function for manual approval notifications
resource "aws_lambda_function" "manual_approval_notification" {
    function_name = "${var.org}-${var.app}-${local.env}-manual-approval-notification"
    role         = aws_iam_role.lambda_manual_approval.arn
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

    filename         = data.archive_file.lambda_manual_approval.output_path
    source_code_hash = data.archive_file.lambda_manual_approval.output_base64sha256

    tags = local.tags
}

# Lambda execution role for manual approval
resource "aws_iam_role" "lambda_manual_approval" {
    name = "${var.org}-${var.app}-${local.env}-lambda-manual-approval"
    
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

# Attach basic execution role
resource "aws_iam_role_policy_attachment" "lambda_manual_approval_basic" {
    role       = aws_iam_role.lambda_manual_approval.name
    policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Policy for manual approval Lambda to access pipeline details
resource "aws_iam_role_policy" "lambda_manual_approval" {
    name = "manual-approval-policy"
    role = aws_iam_role.lambda_manual_approval.id
    
    policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Effect = "Allow"
                Action = [
                    "codepipeline:GetPipeline",
                    "codepipeline:GetPipelineExecution",
                    "codepipeline:ListActionExecutions"
                ]
                Resource = [
                    aws_codepipeline.main.arn,
                    "${aws_codepipeline.main.arn}/*"
                ]
            },
            {
                Effect = "Allow"
                Action = "codebuild:BatchGetBuilds"
                Resource = "*"  # CodeBuild doesn't support resource-level permissions for BatchGetBuilds
            },
            {
                Effect = "Allow"
                Action = [
                    "s3:GetObject",
                    "s3:ListBucket"
                ]
                Resource = [
                    "${aws_s3_bucket.tf_artifacts.arn}/*",
                    aws_s3_bucket.tf_artifacts.arn
                ]
            },
            {
                Effect = "Allow"
                Action = [
                    "kms:Decrypt",
                    "kms:DescribeKey"
                ]
                Resource = var.pipeline_artifacts_kms_key_arn
            }
        ]
    })
}

# SNS topic subscription to Slack webhook Lambda
resource "aws_sns_topic_subscription" "manual_approval_slack" {
    topic_arn = aws_sns_topic.manual_approval.arn
    protocol  = "lambda"
    endpoint  = aws_lambda_function.manual_approval_notification.arn
}

# Permission for SNS to invoke the manual approval Lambda
resource "aws_lambda_permission" "manual_approval_sns" {
    statement_id  = "AllowSNSInvoke"
    action        = "lambda:InvokeFunction"
    function_name = aws_lambda_function.manual_approval_notification.function_name
    principal     = "sns.amazonaws.com"
    source_arn    = aws_sns_topic.manual_approval.arn
}

# Lambda deployment package for manual approval
data "archive_file" "lambda_manual_approval" {
    type        = "zip"
    output_path = "${path.module}/.terraform/lambda-manual-approval.zip"

    source {
        content  = <<-EOF
import json
import urllib3
import os
from datetime import datetime

http = urllib3.PoolManager()

def lambda_handler(event, context):
    print(f"Manual approval event: {json.dumps(event)}")
    
    try:
        # Parse SNS message
        message = json.loads(event['Records'][0]['Sns']['Message'])
        print(f"SNS message: {json.dumps(message)}")
        
        # Extract pipeline information
        region = message.get('region', 'us-east-1')
        pipeline_name = message.get('codePipelineName', 'Unknown Pipeline')
        pipeline_execution_id = message.get('codePipelineExecutionId', 'Unknown')
        action_name = message.get('actionName', 'Manual Approval')
        approval_token = message.get('token', '')
        custom_data = message.get('customData', 'Please review and approve.')
        
        # Send Slack notification
        send_manual_approval_slack(
            pipeline_name=pipeline_name,
            execution_id=pipeline_execution_id,
            action_name=action_name,
            approval_token=approval_token,
            custom_data=custom_data,
            region=region
        )
        
        return {'statusCode': 200, 'body': 'Manual approval notification sent'}
        
    except Exception as e:
        print(f"Error in lambda_handler: {str(e)}")
        import traceback
        traceback.print_exc()
        raise e

def send_manual_approval_slack(pipeline_name, execution_id, action_name, approval_token, custom_data, region):
    webhook_url = os.environ.get('SLACK_WEBHOOK_URL')
    if not webhook_url:
        print("No Slack webhook URL configured")
        return
    
    # Build message blocks
    blocks = []
    
    # Header
    header_text = "⏸️ Production Deployment Approval Required"
    blocks.append({
        "type": "header",
        "text": {
            "type": "plain_text",
            "text": header_text
        }
    })
    
    # Get execution details to show what happened in dev/tools
    try:
        import boto3
        codepipeline = boto3.client('codepipeline')
        s3 = boto3.client('s3')
        import zipfile
        import io
        
        # Get pipeline execution details
        execution = codepipeline.get_pipeline_execution(
            pipelineName=pipeline_name,
            pipelineExecutionId=execution_id
        )
        
        # Get action executions to find completed apply actions
        action_executions = codepipeline.list_action_executions(
            pipelineName=pipeline_name,
            filter={'pipelineExecutionId': execution_id}
        )
        
        # Helper function to extract summary from build artifacts
        def extract_summary_from_build(build_id, env_name):
            try:
                codebuild = boto3.client('codebuild')
                builds = codebuild.batch_get_builds(ids=[build_id])['builds']
                if not builds:
                    print(f"No build found for ID: {build_id}")
                    return None
                    
                build = builds[0]
                artifacts = build.get('artifacts', {})
                location = artifacts.get('location', '')
                
                if not location.startswith('arn:aws:s3:::'):
                    print(f"Unexpected artifact location format: {location}")
                    return None
                    
                s3_path = location.replace('arn:aws:s3:::', '')
                bucket, key = s3_path.split('/', 1)
                
                # Get the zip artifact and extract summary
                obj = s3.get_object(Bucket=bucket, Key=key)
                zip_data = obj['Body'].read()
                
                with zipfile.ZipFile(io.BytesIO(zip_data)) as zip_file:
                    target_filename = f"hoist_summary_{env_name}.json"
                    for file_path in zip_file.namelist():
                        if file_path.endswith(target_filename):
                            summary_content = zip_file.read(file_path).decode('utf-8')
                            return json.loads(summary_content)
                
                print(f"{target_filename} not found in artifact")
                return None
                
            except Exception as e:
                print(f"Error extracting summary for {env_name}: {e}")
                return None
        
        # Extract results from dev/tools applies and prod plan
        dev_tools_results = []
        prod_plan_summary = None
        
        for action in action_executions.get('actionExecutionDetails', []):
            action_name = action.get('actionName', '')
            status = action.get('status', '')
            
            # Skip non-succeeded actions
            if status != 'Succeeded':
                continue
                
            # Get build ID from action output
            output = action.get('output', {})
            execution_result = output.get('executionResult', {})
            build_id = execution_result.get('externalExecutionId', '')
            
            if not build_id:
                print(f"No build ID found for action {action_name}")
                continue
            
            # Process ApplyDev and ApplyTools
            if action_name in ['ApplyDev', 'ApplyTools']:
                env = action_name.replace('Apply', '').lower()
                summary = extract_summary_from_build(build_id, env)
                if summary:
                    dev_tools_results.append({
                        'env': env,
                        'create': summary.get('create', 0),
                        'update': summary.get('update', 0),
                        'delete': summary.get('delete', 0)
                    })
            
            # Process PlanProd
            elif action_name == 'PlanProd':
                summary = extract_summary_from_build(build_id, 'prod')
                if summary:
                    prod_plan_summary = {
                        'create': summary.get('create', 0),
                        'update': summary.get('update', 0),
                        'delete': summary.get('delete', 0)
                    }
        
        # Build status message
        status_parts = []
        
        # Show dev/tools results
        if dev_tools_results:
            status_parts.append("*✅ Applied to Dev/Tools:*")
            for result in dev_tools_results:
                env = result['env'].upper()
                changes = []
                if result['create'] > 0:
                    changes.append(f"+{result['create']} create")
                if result['update'] > 0:
                    changes.append(f"~{result['update']} update")
                if result['delete'] > 0:
                    changes.append(f"-{result['delete']} delete")
                change_str = f" ({', '.join(changes)})" if changes else " (no changes)"
                status_parts.append(f"  • {env}{change_str}")
        
        # Show prod plan
        if prod_plan_summary:
            status_parts.append("")
            status_parts.append("*📋 Proposed for Production:*")
            changes = []
            if prod_plan_summary['create'] > 0:
                changes.append(f"+{prod_plan_summary['create']} create")
            if prod_plan_summary['update'] > 0:
                changes.append(f"~{prod_plan_summary['update']} update")
            if prod_plan_summary['delete'] > 0:
                changes.append(f"-{prod_plan_summary['delete']} delete")
            change_str = f" ({', '.join(changes)})" if changes else " (no changes)"
            status_parts.append(f"  • PROD{change_str}")
        
        status_text = "\\n".join(status_parts) if status_parts else custom_data
        
    except Exception as e:
        print(f"Error getting execution details: {e}")
        status_text = custom_data
    
    # Pipeline info and status
    pipeline_url = f"https://console.aws.amazon.com/codesuite/codepipeline/pipelines/{pipeline_name}/executions/{execution_id}/timeline?region={region}"
    blocks.append({
        "type": "section",
        "text": {
            "type": "mrkdwn",
            "text": f"*Pipeline:* <{pipeline_url}|{pipeline_name}>\\n\\n{status_text}"
        }
    })
    
    # Approval actions
    blocks.append({
        "type": "actions",
        "elements": [
            {
                "type": "button",
                "text": {
                    "type": "plain_text",
                    "text": "📋 Review Pipeline"
                },
                "url": pipeline_url,
                "style": "primary"
            },
            {
                "type": "button",
                "text": {
                    "type": "plain_text",
                    "text": "🚀 Open Console to Approve"
                },
                "url": f"https://console.aws.amazon.com/codesuite/codepipeline/pipelines/{pipeline_name}/executions/{execution_id}/timeline?region={region}#approval",
                "style": "danger"
            }
        ]
    })
    
    # Instructions
    blocks.append({
        "type": "context",
        "elements": [
            {
                "type": "mrkdwn",
                "text": f"⚠️ *Action Required:* Review the production changes and approve/reject in the AWS Console"
            }
        ]
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