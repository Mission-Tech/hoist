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
                    "${aws_codepipeline.branch.arn}/*",
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

# EventBridge rule for pipeline execution state changes
resource "aws_cloudwatch_event_rule" "pipeline_execution_notification" {
    name        = "${var.org}-${var.app}-${local.env}-pipeline-notification"
    description = "Trigger notification on pipeline execution completion"
    
    event_pattern = jsonencode({
        source = ["aws.codepipeline"]
        detail-type = ["CodePipeline Pipeline Execution State Change"]
        detail = {
            pipeline = [aws_codepipeline.branch.name, aws_codepipeline.main.name]
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
import zipfile
import io
from datetime import datetime

codepipeline = boto3.client('codepipeline')
codebuild = boto3.client('codebuild')
s3 = boto3.client('s3')
http = urllib3.PoolManager()

def extract_summary_from_build(build_id, env, s3_location):
    """Extract hoist_summary_{env}.json from build artifacts"""
    try:
        # Get S3 location from pipeline output
        bucket = s3_location.get('bucket', '')
        key = s3_location.get('key', '')
        
        if not bucket or not key:
            print(f"Invalid S3 location provided: {s3_location}")
            return None
            
        location = f"arn:aws:s3:::{bucket}/{key}"
        
        if not location:
            print(f"No artifact location for build {build_id}")
            return None
            
        if not location.startswith('arn:aws:s3:::'):
            print(f"Unexpected artifact location format: {location}")
            return None
            
        s3_path = location.replace('arn:aws:s3:::', '')
        bucket, key = s3_path.split('/', 1)
        
        print(f"Getting zip artifact from s3://{bucket}/{key}")
        obj = s3.get_object(Bucket=bucket, Key=key)
        zip_data = obj['Body'].read()
        
        with zipfile.ZipFile(io.BytesIO(zip_data)) as zip_file:
            target_filename = f"hoist_summary_{env}.json"
            for file_path in zip_file.namelist():
                if file_path.endswith(target_filename):
                    print(f"Found {target_filename} at {file_path}")
                    summary_content = zip_file.read(file_path).decode('utf-8')
                    # Extract account ID from bucket name pattern: org-app-env-accountid-purpose
                    bucket_parts = bucket.split('-')
                    account_id = None
                    if len(bucket_parts) >= 5 and bucket_parts[3].isdigit():
                        account_id = bucket_parts[3]
                    return json.loads(summary_content), account_id
        
        print(f"hoist_summary_{env}.json not found in artifact")
        return None
        
    except Exception as e:
        print(f"Error extracting summary for {env}: {e}")
        return None

def lambda_handler(event, context):
    print(f"Event: {json.dumps(event)}")
    
    try:
        detail = event['detail']
        pipeline_name = detail['pipeline']
        execution_id = detail['execution-id']
        state = detail['state']
        
        # Load pipeline configuration
        pipeline_config = json.loads(os.environ.get('PIPELINE_CONFIG', '{}'))
        
        # Determine which pipeline type this is
        if 'terraform-plan' in pipeline_name:
            config = pipeline_config.get('branch', {})
        else:
            config = pipeline_config.get('main', {})
        
        stages = config.get('stages', {})
        actions = config.get('actions', {})
        
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
            
            # Skip non-Plan/Apply actions (like Source)
            if not (action_name.startswith('Plan') or action_name.startswith('Apply')):
                continue
                
            if action_name.startswith('Plan'):
                env = action_name.replace('Plan', '').lower()
                operation = 'plan'
            elif action_name.startswith('Apply'):
                env = action_name.replace('Apply', '').lower()
                operation = 'apply'
            
            print(f"Processing {operation} action for environment: {env}")
            
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
            
            if not external_execution_id:
                print(f"No external execution ID for {env}, skipping artifact extraction")
                continue
                
            build_id = external_execution_id
            results[env]['build_id'] = build_id
            print(f"Found build ID: {build_id}")
            
            # Get S3 location from output artifacts
            output_artifacts = output.get('outputArtifacts', [])
            if not output_artifacts:
                print(f"No output artifacts for {env}")
                results[env]['error_message'] = 'No output artifacts found'
                continue
                
            # Get the first artifact's S3 location
            s3_location = output_artifacts[0].get('s3location', {})
            print(f"Getting zip artifact from s3://{s3_location.get('bucket', '')}/{s3_location.get('key', '')}")
            
            # Extract summary from build artifacts
            summary_result = extract_summary_from_build(build_id, env, s3_location)
            if summary_result:
                summary, account_id = summary_result
                results[env]['account_id'] = account_id
                results[env]['create'] = summary.get('create', 0)
                results[env]['update'] = summary.get('update', 0)
                results[env]['delete'] = summary.get('delete', 0)
                print(f"Extracted counts for {env}: create={results[env]['create']}, update={results[env]['update']}, delete={results[env]['delete']}")
    
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
            
            # Only show "no changes" if we're absolutely certain
            if result['status'] == 'Succeeded' and 'create' in result and 'update' in result and 'delete' in result:
                # We successfully got the data
                changes = []
                if result['create'] > 0:
                    changes.append(f"+{result['create']} create")
                if result['update'] > 0:
                    changes.append(f"~{result['update']} update")
                if result['delete'] > 0:
                    changes.append(f"-{result['delete']} delete")
                
                if changes:
                    change_summary = f" ({', '.join(changes)})"
                    env_emoji = "🔄"
                else:
                    change_summary = " (no changes)"
                    env_emoji = "✅"
            elif result['status'] == 'Failed':
                # Build explicitly failed
                env_emoji = "❌"
                change_summary = f" (build failed)"
                if result.get('error_message'):
                    change_summary = f" (failed: {result['error_message']})"
            else:
                # Something went wrong - we don't have the data we need
                env_emoji = "⚠️"
                error_msg = result.get('error_message', 'unable to extract plan data.')
                change_summary = f" (error: {error_msg})"
            
            # Build text
            text = f"{env_emoji} *{env.upper()}*{change_summary}"
            
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
