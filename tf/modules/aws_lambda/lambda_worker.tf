# Worker Lambda - processes jobs from SQS queue
resource "aws_lambda_function" "worker" {
  function_name = "${var.app}-${var.env}-worker"
  role          = aws_iam_role.lambda_execution.arn

  # Use the same Docker image as the main app, but with different entrypoint
  package_type = "Image"
  # Use the most recent image by digest (same as main Lambda)
  image_uri    = "${aws_ecr_repository.lambda_repository.repository_url}@${data.aws_ecr_image.latest.image_digest}"
  image_config {
    command = ["/worker"]
  }

  # Timeout must match worker timeout_seconds config in AppConfig
  # See: backend/internal/config/jobs.go WorkerConfig.TimeoutSeconds
  # See: backend/docs/configuration.md jobs.worker.timeout_seconds
  timeout = 360 # 6 minutes

  # 1769 MB gives exactly 1 full vCPU in Lambda
  # https://docs.aws.amazon.com/lambda/latest/dg/configuration-memory.html
  memory_size = 1769

  environment {
    variables = {
      # Worker reads from AppConfig just like main app
      # Configuration handled by AppConfig Lambda Extension
      hoist_app = var.app
      hoist_env = var.env
    }
  }

  vpc_config {
    subnet_ids         = local.private_subnet_ids
    security_group_ids = [aws_security_group.lambda.id]
  }

  tags = {
    Application = var.app
    Environment = var.env
    Module      = "aws_lambda"
    Description = "Worker Lambda for background jobs in ${var.app}-${var.env}"
  }

  lifecycle {
    # Ignore changes to image_uri since the deploy Lambda will manage updates
    ignore_changes = [image_uri]
  }
}

# SQS trigger for worker Lambda
resource "aws_lambda_event_source_mapping" "worker_sqs_trigger" {
  event_source_arn = aws_sqs_queue.jobs.arn
  function_name    = aws_lambda_function.worker.arn

  batch_size                         = 1 # Process one job at a time
  maximum_batching_window_in_seconds = 0 # No batching delay

  # Scale down to zero when queue is empty
  scaling_config {
    maximum_concurrency = 10 # Max 10 workers running concurrently
  }

  function_response_types = ["ReportBatchItemFailures"]
}
