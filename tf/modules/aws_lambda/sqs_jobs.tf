# SQS queue for background jobs
resource "aws_sqs_queue" "jobs" {
  name = "${var.app}-${var.env}-jobs"

  # Visibility timeout should be > Lambda timeout to account for:
  # - Lambda cold start time
  # - Time for worker to mark job as failed in DB after timeout
  # Lambda timeout is 360s, so add 60s buffer = 420s (7 minutes)
  # See: backend/internal/config/jobs.go WorkerConfig.TimeoutSeconds
  visibility_timeout_seconds = 420 # 7 minutes (360s worker + 60s buffer)

  message_retention_seconds = 1209600 # 14 days
  receive_wait_time_seconds = 0

  tags = {
    Application = var.app
    Environment = var.env
    Module      = "aws_lambda"
    Description = "Job queue for ${var.app}-${var.env}"
  }
}

# IAM policy for accessing the jobs queue
resource "aws_iam_policy" "jobs_queue_access" {
  name        = "${var.app}-${var.env}-jobs-queue-access"
  description = "Allow app roles to publish and consume jobs"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl"
        ]
        Resource = aws_sqs_queue.jobs.arn
      }
    ]
  })

  tags = {
    Application = var.app
    Environment = var.env
    Module      = "aws_lambda"
  }
}

# Attach queue access policy to the Lambda execution role (used by both main app and worker)
resource "aws_iam_role_policy_attachment" "app_jobs_queue_access" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = aws_iam_policy.jobs_queue_access.arn
}
