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
    header_text = "⏸️ Manual Approval Required"
    blocks.append({
        "type": "header",
        "text": {
            "type": "plain_text",
            "text": header_text
        }
    })
    
    # Pipeline info and link
    pipeline_url = f"https://console.aws.amazon.com/codesuite/codepipeline/pipelines/{pipeline_name}/executions/{execution_id}/timeline?region={region}"
    blocks.append({
        "type": "section",
        "text": {
            "type": "mrkdwn",
            "text": f"*Pipeline:* <{pipeline_url}|{pipeline_name}>\\n*Action:* {action_name}\\n*Message:* {custom_data}"
        }
    })
    
    # Approval buttons section
    blocks.append({
        "type": "section",
        "text": {
            "type": "mrkdwn",
            "text": "Please review the terraform plan above and take action:"
        },
        "accessory": {
            "type": "button",
            "text": {
                "type": "plain_text",
                "text": "Open Pipeline"
            },
            "url": pipeline_url,
            "style": "primary"
        }
    })
    
    # Instructions
    blocks.append({
        "type": "context",
        "elements": [
            {
                "type": "mrkdwn",
                "text": f"💡 *Approval Token:* `{approval_token}`\\nUse the AWS Console to approve or reject this pipeline execution."
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