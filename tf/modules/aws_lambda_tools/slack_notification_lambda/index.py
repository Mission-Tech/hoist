import json
import urllib3
import os

http = urllib3.PoolManager()

def handler(event, context):
    """Send CodePipeline manual approval notifications to Slack"""
    
    # Get Slack webhook URL from environment
    webhook_url = os.environ.get('SLACK_WEBHOOK_URL')
    if not webhook_url:
        print("No Slack webhook URL configured, skipping notification")
        return {"statusCode": 200, "body": "Skipped - no webhook"}
    
    # Parse SNS message
    sns_message = json.loads(event['Records'][0]['Sns']['Message'])
    
    # Extract pipeline information
    approval = sns_message.get('approval', {})
    pipeline_name = approval.get('pipelineName', 'Unknown')
    stage_name = approval.get('stageName', 'Unknown')
    custom_data = approval.get('customData', 'No details provided')
    
    # Get configuration from environment
    app_name = os.environ.get('APP_NAME', 'unknown')
    github_org = os.environ.get('GITHUB_ORG', 'unknown')
    
    # Extract deployment details from pipeline execution
    pipeline_execution_id = approval.get('pipelineExecutionId', '')
    
    # Extract approval review link
    region = sns_message.get('region', 'us-east-1')
    console_link = sns_message.get('consoleLink', 
        f"https://console.aws.amazon.com/codesuite/codepipeline/pipelines/{pipeline_name}/view")
    
    # Build GitHub repository link
    github_repo_link = f"https://github.com/{github_org}/{app_name}"
    
    # Build Slack message
    slack_message = {
        "text": f"🚀 Deployment approval needed for *{app_name}*",
        "blocks": [
            {
                "type": "section",
                "text": {
                    "type": "mrkdwn",
                    "text": f"*Application:* `{app_name}`\n*Pipeline:* `{pipeline_name}`\n*Stage:* {stage_name}\n*Details:* {custom_data}"
                }
            },
            {
                "type": "section",
                "text": {
                    "type": "mrkdwn",
                    "text": f"*Repository:* <{github_repo_link}|{github_org}/{app_name}>\n*Execution ID:* `{pipeline_execution_id}`"
                }
            },
            {
                "type": "actions",
                "elements": [
                    {
                        "type": "button",
                        "text": {
                            "type": "plain_text",
                            "text": "Review in AWS Console"
                        },
                        "url": console_link,
                        "style": "primary"
                    },
                    {
                        "type": "button",
                        "text": {
                            "type": "plain_text",
                            "text": "View Repository"
                        },
                        "url": github_repo_link
                    }
                ]
            }
        ]
    }
    
    # Send to Slack
    try:
        response = http.request(
            'POST',
            webhook_url,
            body=json.dumps(slack_message).encode('utf-8'),
            headers={'Content-Type': 'application/json'}
        )
        
        print(f"Slack notification sent: {response.status}")
        return {"statusCode": response.status, "body": response.data.decode('utf-8')}
    
    except Exception as e:
        print(f"Error sending Slack notification: {str(e)}")
        return {"statusCode": 500, "body": str(e)}