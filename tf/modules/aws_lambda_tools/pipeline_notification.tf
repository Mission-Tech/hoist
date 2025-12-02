# EventBridge-triggered Lambda for pipeline failure notifications
# Sends Slack notifications when the deployment pipeline succeeds, fails, or is stopped

# Lambda function for pipeline notifications
resource "aws_lambda_function" "pipeline_notification" {
  count            = local.slack_notifications_enabled ? 1 : 0
  function_name    = "${var.app}-tools-pipeline-notification"
  role             = aws_iam_role.pipeline_notification_lambda[0].arn
  handler          = "index.lambda_handler"
  runtime          = "python3.11"
  architectures    = ["arm64"]
  timeout          = 60
  memory_size      = 256

  environment {
    variables = {
      SLACK_WEBHOOK_URL = nonsensitive(data.aws_ssm_parameter.slack_cd_webhook[0].value)
      APP_NAME          = var.app
      GITHUB_ORG        = var.github_org
    }
  }

  filename         = data.archive_file.pipeline_notification_lambda[0].output_path
  source_code_hash = data.archive_file.pipeline_notification_lambda[0].output_base64sha256

  tags = {
    Application = var.app
    Environment = "tools"
    Module      = "aws_lambda_tools"
    Description = "Sends pipeline state change notifications to Slack"
  }
}

# IAM role for pipeline notification Lambda
resource "aws_iam_role" "pipeline_notification_lambda" {
  count = local.slack_notifications_enabled ? 1 : 0
  name  = "${var.app}-tools-pipeline-notification"

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

  tags = {
    Application = var.app
    Environment = "tools"
    Module      = "aws_lambda_tools"
    Description = "Role for pipeline notification Lambda"
  }
}

# Attach basic execution role
resource "aws_iam_role_policy_attachment" "pipeline_notification_lambda_basic" {
  count      = local.slack_notifications_enabled ? 1 : 0
  role       = aws_iam_role.pipeline_notification_lambda[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Policy for pipeline notification Lambda
resource "aws_iam_role_policy" "pipeline_notification_lambda" {
  count = local.slack_notifications_enabled ? 1 : 0
  name  = "pipeline-notification-policy"
  role  = aws_iam_role.pipeline_notification_lambda[0].id

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
          aws_codepipeline.deployment_pipeline.arn,
          "${aws_codepipeline.deployment_pipeline.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = "codebuild:BatchGetBuilds"
        # CodeBuild doesn't support resource-level permissions for BatchGetBuilds
        Resource = "*"
      }
    ]
  })
}

# EventBridge rule for pipeline execution state changes
resource "aws_cloudwatch_event_rule" "pipeline_execution_notification" {
  count       = local.slack_notifications_enabled ? 1 : 0
  name        = "${var.app}-tools-pipeline-notification"
  description = "Trigger notification on pipeline execution state changes (success, failure, stopped)"

  event_pattern = jsonencode({
    source      = ["aws.codepipeline"]
    detail-type = ["CodePipeline Pipeline Execution State Change"]
    detail = {
      pipeline = [aws_codepipeline.deployment_pipeline.name]
      state    = ["SUCCEEDED", "FAILED", "STOPPED"]
    }
  })

  tags = {
    Application = var.app
    Environment = "tools"
    Module      = "aws_lambda_tools"
    Description = "Pipeline notification rule"
  }
}

# EventBridge target
resource "aws_cloudwatch_event_target" "pipeline_notification" {
  count = local.slack_notifications_enabled ? 1 : 0
  rule  = aws_cloudwatch_event_rule.pipeline_execution_notification[0].name
  arn   = aws_lambda_function.pipeline_notification[0].arn
}

# Permission for EventBridge to invoke Lambda
resource "aws_lambda_permission" "pipeline_notification" {
  count         = local.slack_notifications_enabled ? 1 : 0
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.pipeline_notification[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.pipeline_execution_notification[0].arn
}

# Lambda deployment package
data "archive_file" "pipeline_notification_lambda" {
  count       = local.slack_notifications_enabled ? 1 : 0
  type        = "zip"
  output_path = "${path.module}/pipeline_notification_lambda.zip"

  source {
    content = <<-EOF
import json
import boto3
import os
import urllib3
from datetime import datetime

codepipeline = boto3.client('codepipeline')
codebuild = boto3.client('codebuild')
http = urllib3.PoolManager()

def lambda_handler(event, context):
    """Handle CodePipeline state change events and send Slack notifications"""

    print(f"Received event: {json.dumps(event)}")

    # Extract pipeline execution details
    detail = event['detail']
    pipeline_name = detail['pipeline']
    execution_id = detail['execution-id']
    state = detail['state']

    # Get app name from environment
    app_name = os.environ.get('APP_NAME', 'unknown')
    github_org = os.environ.get('GITHUB_ORG', 'unknown')

    # Get detailed execution info
    try:
        execution = codepipeline.get_pipeline_execution(
            pipelineName=pipeline_name,
            pipelineExecutionId=execution_id
        )

        # Get action executions to find failures
        action_executions = codepipeline.list_action_executions(
            pipelineName=pipeline_name,
            filter={'pipelineExecutionId': execution_id}
        )

        # Find failed actions
        failed_actions = []
        for action_exec in action_executions.get('actionExecutionDetails', []):
            if action_exec.get('status') == 'Failed':
                action_name = action_exec['actionName']
                stage_name = action_exec['stageName']

                # Get error details
                error_msg = "Unknown error"
                if 'output' in action_exec and 'executionResult' in action_exec['output']:
                    error_msg = action_exec['output']['executionResult'].get('externalExecutionSummary', error_msg)

                # Try to get CodeBuild details if this was a CodeBuild action
                codebuild_details = None
                if 'externalExecutionId' in action_exec.get('output', {}):
                    build_id = action_exec['output']['externalExecutionId']
                    try:
                        builds = codebuild.batch_get_builds(ids=[build_id])
                        if builds.get('builds'):
                            build = builds['builds'][0]
                            codebuild_details = {
                                'log_url': build.get('logs', {}).get('deepLink', 'No logs available'),
                                'phases': build.get('phases', [])
                            }
                    except Exception as e:
                        print(f"Could not get CodeBuild details: {e}")

                failed_actions.append({
                    'stage': stage_name,
                    'action': action_name,
                    'error': error_msg,
                    'codebuild': codebuild_details
                })

        # Build Slack message
        message = build_slack_message(
            app_name=app_name,
            pipeline_name=pipeline_name,
            execution_id=execution_id,
            state=state,
            failed_actions=failed_actions,
            github_org=github_org
        )

        # Send to Slack
        webhook_url = os.environ['SLACK_WEBHOOK_URL']
        response = http.request(
            'POST',
            webhook_url,
            body=json.dumps(message).encode('utf-8'),
            headers={'Content-Type': 'application/json'}
        )

        print(f"Slack response status: {response.status}")

        return {
            'statusCode': 200,
            'body': json.dumps('Notification sent successfully')
        }

    except Exception as e:
        print(f"Error processing notification: {str(e)}")
        raise


def build_slack_message(app_name, pipeline_name, execution_id, state, failed_actions, github_org):
    """Build Slack message payload"""

    # Determine color and emoji based on state
    if state == 'SUCCEEDED':
        color = 'good'
        emoji = ':white_check_mark:'
        title = f"{emoji} Pipeline Succeeded"
    elif state == 'FAILED':
        color = 'danger'
        emoji = ':x:'
        title = f"{emoji} Pipeline Failed"
    else:  # STOPPED
        color = 'warning'
        emoji = ':warning:'
        title = f"{emoji} Pipeline Stopped"

    # Pipeline execution URL
    region = os.environ.get('AWS_REGION', 'us-east-1')
    pipeline_url = f"https://console.aws.amazon.com/codesuite/codepipeline/pipelines/{pipeline_name}/executions/{execution_id}?region={region}"

    # Build fields
    fields = [
        {
            "title": "Application",
            "value": app_name,
            "short": True
        },
        {
            "title": "Pipeline",
            "value": f"<{pipeline_url}|{pipeline_name}>",
            "short": True
        },
        {
            "title": "State",
            "value": state,
            "short": True
        },
        {
            "title": "Execution ID",
            "value": execution_id[:8],
            "short": True
        }
    ]

    # Add failed action details
    if failed_actions:
        for failed in failed_actions:
            fields.append({
                "title": f"Failed: {failed['stage']} > {failed['action']}",
                "value": failed['error'][:500],  # Truncate long errors
                "short": False
            })

            # Add CodeBuild log link if available
            if failed.get('codebuild') and failed['codebuild'].get('log_url'):
                fields.append({
                    "title": "CodeBuild Logs",
                    "value": f"<{failed['codebuild']['log_url']}|View Logs>",
                    "short": False
                })

    return {
        "attachments": [
            {
                "color": color,
                "title": title,
                "fields": fields,
                "footer": f"{app_name} deployment pipeline",
                "ts": int(datetime.now().timestamp())
            }
        ]
    }
EOF
    filename = "index.py"
  }
}
