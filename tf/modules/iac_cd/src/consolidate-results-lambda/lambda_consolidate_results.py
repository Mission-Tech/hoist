import json
import boto3
import os
import zipfile
import io
from typing import Dict, Any

codepipeline = boto3.client('codepipeline')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    """
    Lambda function to consolidate terraform plan results from multiple environments
    """
    print(f"Event: {json.dumps(event)}")
    
    # Extract CodePipeline job data
    job = event['CodePipeline.job']
    job_id = job['id']
    job_data = job['data']
    
    # Extract user parameters
    user_params = json.loads(job_data['actionConfiguration']['configuration']['UserParameters'])
    commit_sha = user_params['commit_sha']
    branch = user_params['branch']
    author = user_params['author']
    pr_number = user_params.get('pr_number', '')
    
    # Process all input artifacts
    results = {}
    all_success = True
    
    for artifact in job_data['inputArtifacts']:
        bucket = artifact['location']['s3Location']['bucketName']
        key = artifact['location']['s3Location']['objectKey']
        
        # Determine environment from artifact name
        environment = artifact['name'].replace('_plan_output', '')
        
        try:
            summary = download_and_parse_summary(bucket, key)
            results[environment] = summary
            if not summary['success']:
                all_success = False
        except Exception as e:
            print(f"Error processing {environment} results: {e}")
            codepipeline.put_job_failure_result(
                jobId=job_id,
                failureDetails={'message': f'Failed to process {environment} results: {str(e)}'}
            )
            return
    
    # Generate markdown summary
    markdown = generate_markdown_summary(
        commit_sha=commit_sha,
        branch=branch,
        author=author,
        pr_number=pr_number,
        results=results,
        all_success=all_success
    )
    
    # Create consolidated result
    consolidated = {
        'commit_sha': commit_sha,
        'branch': branch,
        'author': author,
        'pr_number': pr_number,
        'all_success': all_success,
        'results': results,
        'markdown_summary': markdown
    }
    
    # Post to GitHub if PR number is provided
    if pr_number:
        try:
            post_to_github(pr_number, markdown)
        except Exception as e:
            print(f"Failed to post to GitHub: {e}")
    
    # Send Slack notification if webhook is configured
    try:
        send_slack_notification(consolidated)
    except Exception as e:
        print(f"Failed to send Slack notification: {e}")
    
    # Report success
    codepipeline.put_job_success_result(jobId=job_id)
    
    return {
        'statusCode': 200,
        'body': json.dumps('Results consolidated successfully')
    }


def download_and_parse_summary(bucket: str, key: str) -> Dict[str, Any]:
    """Download and parse the summary.json from the artifact zip"""
    # Download the zip file
    obj = s3.get_object(Bucket=bucket, Key=key)
    zip_data = obj['Body'].read()
    
    # Open zip from memory
    with zipfile.ZipFile(io.BytesIO(zip_data), 'r') as zip_ref:
        # Read summary.json
        if 'summary.json' in zip_ref.namelist():
            with zip_ref.open('summary.json') as f:
                return json.load(f)
        else:
            raise Exception("summary.json not found in artifact")


def generate_markdown_summary(commit_sha: str, branch: str, author: str, 
                            pr_number: str, results: Dict[str, Any], 
                            all_success: bool) -> str:
    """Generate a markdown summary of the terraform plan results"""
    
    # Header
    status_emoji = "✅" if all_success else "❌"
    status_text = "All terraform plans succeeded" if all_success else "Some terraform plans failed"
    
    markdown = f"""## Terraform Plan Results {status_emoji}

**Status:** {status_text}
**Branch:** `{branch}`
**Commit:** `{commit_sha[:8]}`
**Author:** {author}

### Environment Results

| Environment | Account | Status | Details |
|-------------|---------|--------|----------|
"""
    
    # Add results for each environment
    for env in ['dev', 'prod', 'tools']:
        if env in results:
            result = results[env]
            status = "✅ Success" if result['success'] else "❌ Failed"
            details = "Plan completed successfully"
            
            if not result['success']:
                details = result.get('error', 'Plan failed')
            
            markdown += f"| {env} | {result['account_id']} | {status} | {details} |\n"
    
    markdown += "\n"
    
    # Add detailed output for failed plans
    has_failures = False
    for env, result in results.items():
        if not result['success'] and result.get('plan_output'):
            if not has_failures:
                markdown += "### Failed Plan Output\n\n"
                has_failures = True
            
            output = result['plan_output']
            if len(output) > 3000:
                output = output[:3000] + "\n... (truncated)"
            
            markdown += f"""<details>
<summary>{env} environment plan output</summary>

```
{output}
```
</details>

"""
    
    return markdown


def post_to_github(pr_number: str, comment: str) -> None:
    """Post a comment to the GitHub PR"""
    # This would use the GitHub API to post the comment
    # For now, we'll just log what we would post
    print(f"Would post to PR #{pr_number}:")
    print(comment)
    
    # TODO: Implement GitHub API integration
    # Would need:
    # - GitHub token from secrets manager or environment
    # - GitHub org/repo from environment variables
    # - Use requests or github library to post comment


def send_slack_notification(result: Dict[str, Any]) -> None:
    """Send a notification to Slack with the results"""
    webhook_url = os.environ.get('SLACK_WEBHOOK_URL')
    if not webhook_url:
        print("No Slack webhook URL configured")
        return
    
    # Build Slack message
    color = "good" if result['all_success'] else "danger"
    status = "succeeded" if result['all_success'] else "failed"
    
    slack_message = {
        "attachments": [{
            "color": color,
            "title": f"Terraform Plan {status}",
            "fields": [
                {"title": "Branch", "value": result['branch'], "short": True},
                {"title": "Author", "value": result['author'], "short": True},
                {"title": "Commit", "value": result['commit_sha'][:8], "short": True},
            ]
        }]
    }
    
    # Add environment statuses
    for env, env_result in result['results'].items():
        emoji = "✅" if env_result['success'] else "❌"
        slack_message["attachments"][0]["fields"].append({
            "title": f"{env.capitalize()} Environment",
            "value": f"{emoji} {env_result['account_id']}",
            "short": True
        })
    
    # TODO: Send to Slack webhook
    print(f"Would send to Slack:")
    print(json.dumps(slack_message, indent=2))