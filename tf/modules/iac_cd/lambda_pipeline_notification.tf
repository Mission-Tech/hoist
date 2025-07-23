# EventBridge-triggered Lambda for pipeline notifications
resource "aws_lambda_function" "pipeline_notification" {
    function_name = "${var.org}-${var.app}-${local.env}-pipeline-notification"
    role         = aws_iam_role.lambda_pipeline_notification.arn
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

    filename         = data.archive_file.lambda_pipeline_notification.output_path
    source_code_hash = data.archive_file.lambda_pipeline_notification.output_base64sha256

    tags = local.tags
}

# Lambda execution role
resource "aws_iam_role" "lambda_pipeline_notification" {
    name = "${var.org}-${var.app}-${local.env}-lambda-pipeline-notification"
    
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
resource "aws_iam_role_policy_attachment" "lambda_pipeline_notification_basic" {
    role       = aws_iam_role.lambda_pipeline_notification.name
    policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Policy for pipeline notification Lambda
resource "aws_iam_role_policy" "lambda_pipeline_notification" {
    name = "pipeline-notification-policy"
    role = aws_iam_role.lambda_pipeline_notification.id
    
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
                    aws_codepipeline.branch.arn,
                    "${aws_codepipeline.branch.arn}/*"
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

# EventBridge rule for pipeline execution state changes
resource "aws_cloudwatch_event_rule" "pipeline_execution_notification" {
    name        = "${var.org}-${var.app}-${local.env}-pipeline-notification"
    description = "Trigger notification on pipeline execution completion"
    
    event_pattern = jsonencode({
        source = ["aws.codepipeline"]
        detail-type = ["CodePipeline Pipeline Execution State Change"]
        detail = {
            pipeline = [aws_codepipeline.branch.name]
            state = ["SUCCEEDED", "FAILED", "STOPPED"]
        }
    })
    
    tags = local.tags
}

# EventBridge target
resource "aws_cloudwatch_event_target" "pipeline_notification" {
    rule = aws_cloudwatch_event_rule.pipeline_execution_notification.name
    arn  = aws_lambda_function.pipeline_notification.arn
}

# Permission for EventBridge to invoke Lambda
resource "aws_lambda_permission" "pipeline_notification" {
    statement_id  = "AllowEventBridgeInvoke"
    action        = "lambda:InvokeFunction"
    function_name = aws_lambda_function.pipeline_notification.function_name
    principal     = "events.amazonaws.com"
    source_arn    = aws_cloudwatch_event_rule.pipeline_execution_notification.arn
}

# Lambda deployment package
data "archive_file" "lambda_pipeline_notification" {
    type        = "zip"
    output_path = "${path.module}/.terraform/lambda-pipeline-notification.zip"

    source {
        content  = <<-EOF
import json
import boto3
import os
import urllib3
import re
from datetime import datetime

codepipeline = boto3.client('codepipeline')
codebuild = boto3.client('codebuild')
s3 = boto3.client('s3')
http = urllib3.PoolManager()

def lambda_handler(event, context):
    print(f"Event: {json.dumps(event)}")
    
    try:
        detail = event['detail']
        pipeline_name = detail['pipeline']
        execution_id = detail['execution-id']
        state = detail['state']
        
        print(f"Getting execution details for pipeline: {pipeline_name}, execution: {execution_id}")
        
        # Get action executions for this pipeline execution
        action_executions_response = codepipeline.list_action_executions(
            pipelineName=pipeline_name,
            filter={
                'pipelineExecutionId': execution_id
            }
        )
        
        action_executions = action_executions_response.get('actionExecutionDetails', [])
        print(f"Number of action executions: {len(action_executions)}")
        
        # Find all plan actions and their results
        results = {}
        
        for action in action_executions:
            stage_name = action.get('stageName', '')
            action_name = action.get('actionName', '')
            print(f"Found action: {action_name} in stage: {stage_name}")
            
            if stage_name == 'TerraformPlan' and action_name.startswith('Plan'):
                env = action_name.replace('Plan', '').lower()
                print(f"Processing plan action for environment: {env}")
                
                status = action.get('status', 'Unknown')
                print(f"Action status: {status}")
                
                # Initialize result
                results[env] = {
                    'success': status == 'Succeeded',
                    'status': status,
                    'create': 0,
                    'update': 0,
                    'delete': 0,
                    'build_id': '',
                    'error_message': action.get('errorDetails', {}).get('message', '') if action.get('errorDetails') else ''
                }
                
                # Get the output details
                output = action.get('output', {})
                print(f"Action output keys for {env}: {list(output.keys())}")
                print(f"Full output for {env}: {json.dumps(output)}")
                
                # The externalExecutionId is in executionResult, not directly in output
                execution_result = output.get('executionResult', {})
                external_execution_id = execution_result.get('externalExecutionId', '')
                print(f"External execution ID for {env}: {external_execution_id}")
                
                if external_execution_id:
                    build_id = external_execution_id
                    results[env]['build_id'] = build_id
                    print(f"Found build ID: {build_id}")
                    
                    try:
                        # Get build details
                        builds = codebuild.batch_get_builds(ids=[build_id])['builds']
                        if builds:
                            build = builds[0]
                            results[env]['account_id'] = build['arn'].split(':')[4]
                            
                            # Find the primary artifact (CODEPIPELINE type)
                            artifacts = build.get('artifacts', {})
                            if artifacts.get('location'):
                                # Extract S3 location from artifact
                                # Format: arn:aws:s3:::bucket/path
                                location = artifacts['location']
                                print(f"Artifact location: {location}")
                                if location.startswith('arn:aws:s3:::'):
                                    s3_path = location.replace('arn:aws:s3:::', '')
                                    bucket, key = s3_path.split('/', 1)
                                    
                                    # Get hoist_summary.json from the zip artifact
                                    try:
                                        print(f"Getting zip artifact from s3://{bucket}/{key}")
                                        obj = s3.get_object(Bucket=bucket, Key=key)
                                        
                                        # The artifact is a zip file, we need to extract hoist_summary.json from it
                                        import zipfile
                                        import io
                                        
                                        zip_data = obj['Body'].read()
                                        with zipfile.ZipFile(io.BytesIO(zip_data)) as zip_file:
                                            print(f"Looking for hoist_summary_{env}.json in zip for {env}")
                                            
                                            # Find hoist_summary_{env}.json anywhere in the zip
                                            summary_file = None
                                            target_filename = f"hoist_summary_{env}.json"
                                            for file_path in zip_file.namelist():
                                                if file_path.endswith(target_filename):
                                                    summary_file = file_path
                                                    break
                                            
                                            if summary_file:
                                                print(f"Found {target_filename} at {summary_file}")
                                                summary_content = zip_file.read(summary_file).decode('utf-8')
                                                summary = json.loads(summary_content)
                                                print(f"Raw {target_filename} content for {env}: {json.dumps(summary)}")
                                                
                                                # Use the structured counts from buildspec
                                                results[env]['create'] = summary.get('create', 0)
                                                results[env]['update'] = summary.get('update', 0)
                                                results[env]['delete'] = summary.get('delete', 0)
                                                print(f"Extracted counts for {env}: create={results[env]['create']}, update={results[env]['update']}, delete={results[env]['delete']}")
                                            else:
                                                print(f"{target_filename} not found in zip for {env}")
                                        
                                    except Exception as e:
                                        print(f"Error reading summary for {env}: {e}")
                    except Exception as e:
                        print(f"Error getting build details for {env}: {e}")
    
        print(f"Final results: {json.dumps(results)}")
        
        # Send Slack notification
        send_slack_notification(
            pipeline_name=pipeline_name,
            execution_id=execution_id,
            state=state,
            results=results,
            region=event['region']
        )
        
        return {'statusCode': 200, 'body': 'Notification sent'}
        
    except Exception as e:
        print(f"Error in lambda_handler: {str(e)}")
        import traceback
        traceback.print_exc()
        
        # Send a basic notification even if we can't get details
        try:
            webhook_url = os.environ.get('SLACK_WEBHOOK_URL')
            if webhook_url:
                basic_msg = {
                    "text": f"Pipeline {event['detail']['pipeline']} {event['detail']['state']} (Error getting details: {str(e)})"
                }
                http.request('POST', webhook_url, body=json.dumps(basic_msg), headers={'Content-Type': 'application/json'})
        except:
            pass
        
        raise e


def send_slack_notification(pipeline_name, execution_id, state, results, region):
    print(f"send_slack_notification called with pipeline_name={pipeline_name}, execution_id={execution_id}, state={state}, region={region}")
    print(f"Results: {json.dumps(results)}")
    
    webhook_url = os.environ.get('SLACK_WEBHOOK_URL')
    if not webhook_url:
        print("No Slack webhook URL configured")
        return
    
    # Build message blocks
    blocks = []
    
    # Header
    status_emoji = "✅" if state == "SUCCEEDED" else "❌"
    header_text = f"{status_emoji} Pipeline {state.title()}"
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
            "text": f"*Pipeline:* <{pipeline_url}|{pipeline_name}>"
        }
    })
    
    # Environment results
    if not results:
        blocks.append({
            "type": "section",
            "text": {
                "type": "mrkdwn",
                "text": "_No environment results found. Check CloudWatch logs for details._"
            }
        })
    
    for env in ['dev', 'prod', 'tools']:
        if env in results:
            result = results[env]
            
            # Build resource change summary
            changes = []
            if result['create'] > 0:
                changes.append(f"+{result['create']} create")
            if result['update'] > 0:
                changes.append(f"~{result['update']} update")
            if result['delete'] > 0:
                changes.append(f"-{result['delete']} delete")
            
            change_summary = f" ({', '.join(changes)})" if changes else " (no changes)"
            
            # Determine emoji
            if result['status'] == 'Succeeded':
                env_emoji = "🔄" if changes else "✅"
            else:
                env_emoji = "❌"
            
            # Build text
            text = f"{env_emoji} *{env.upper()}*{change_summary}"
            if result.get('error_message'):
                text += f"\\n_{result['error_message']}_"
            
            section = {
                "type": "section",
                "text": {
                    "type": "mrkdwn",
                    "text": text
                }
            }
            
            # Add build link if available
            if result.get('build_id') and result.get('account_id'):
                build_parts = result['build_id'].split(':')
                if len(build_parts) == 2:
                    project_name = build_parts[0]
                    build_url = f"https://console.aws.amazon.com/codesuite/codebuild/{result['account_id']}/projects/{project_name}/build/{result['build_id']}?region={region}"
                    
                    section["accessory"] = {
                        "type": "button",
                        "text": {
                            "type": "plain_text",
                            "text": "View Build"
                        },
                        "url": build_url
                    }
            
            blocks.append(section)
    
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