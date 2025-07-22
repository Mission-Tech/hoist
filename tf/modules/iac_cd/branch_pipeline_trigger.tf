# EventBridge rule to trigger branch pipeline on S3 uploads to ci-upload bucket
resource "aws_cloudwatch_event_rule" "branch_pipeline_trigger" {
    name        = "${var.org}-${var.app}-${local.env}-branch-pipeline-trigger"
    description = "Trigger branch pipeline on S3 object creation in ci-upload bucket"
    
    event_pattern = jsonencode({
        source = ["aws.s3"]
        "detail-type" = ["Object Created"]
        detail = {
            bucket = {
                name = [aws_s3_bucket.ci_upload.id]
            }
            object = {
                key = [{
                    prefix = "branch/"
                }]
            }
        }
    })
    
    tags = local.tags
}

# Target for the EventBridge rule - the branch pipeline
resource "aws_cloudwatch_event_target" "branch_pipeline" {
    rule     = aws_cloudwatch_event_rule.branch_pipeline_trigger.name
    arn      = aws_codepipeline.branch.arn
    role_arn = aws_iam_role.eventbridge_pipeline_trigger.arn
}

# IAM role for EventBridge to start the pipeline
resource "aws_iam_role" "eventbridge_pipeline_trigger" {
    name = "${var.org}-${var.app}-${local.env}-eventbridge-pipeline-trigger"
    
    assume_role_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Effect = "Allow"
                Principal = {
                    Service = "events.amazonaws.com"
                }
                Action = "sts:AssumeRole"
            }
        ]
    })
    
    tags = local.tags
}

# Policy for EventBridge to start the pipeline
resource "aws_iam_role_policy" "eventbridge_pipeline_trigger" {
    name = "start-pipeline"
    role = aws_iam_role.eventbridge_pipeline_trigger.id
    
    policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Effect = "Allow"
                Action = "codepipeline:StartPipelineExecution"
                Resource = aws_codepipeline.branch.arn
            }
        ]
    })
}