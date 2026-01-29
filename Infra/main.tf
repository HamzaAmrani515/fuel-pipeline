terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ---------------------------
# S3
# ---------------------------
resource "aws_s3_bucket" "fuel" {
  bucket        = var.bucket_name
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "fuel" {
  bucket                  = aws_s3_bucket.fuel.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "fuel" {
  bucket = aws_s3_bucket.fuel.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Upload du script Glue dans S3 (automatique)
resource "aws_s3_object" "glue_script" {
  bucket = aws_s3_bucket.fuel.id
  key    = "scripts/fuel_ingest.py"
  source = "${path.module}/glue/fuel_ingest.py"
  etag   = filemd5("${path.module}/glue/fuel_ingest.py")
}

# ---------------------------
# SNS (alerts)
# ---------------------------
resource "aws_sns_topic" "alerts" {
  name = var.sns_topic_name
}

# ---------------------------
# IAM - Lambda
# ---------------------------
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_role" {
  name               = "${var.project_name}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.project_name}-lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      # Logs
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      },
      # S3 write raw
      {
        Effect = "Allow",
        Action = [
          "s3:PutObject",
          "s3:AbortMultipartUpload",
          "s3:ListBucket"
        ],
        Resource = [
          aws_s3_bucket.fuel.arn,
          "${aws_s3_bucket.fuel.arn}/*"
        ]
      },
      # Start Glue
      {
        Effect = "Allow",
        Action = [
          "glue:StartJobRun"
        ],
        Resource = "*"
      },
      # SNS publish (optionnel)
      {
        Effect = "Allow",
        Action = ["sns:Publish"],
        Resource = aws_sns_topic.alerts.arn
      }
    ]
  })
}

# Package Lambda (zip)
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda.zip"
}

resource "aws_lambda_function" "fuel_ingest" {
  function_name = "${var.project_name}-ingest"
  role          = aws_iam_role.lambda_role.arn
  handler       = "main.lambda_handler"
  runtime       = "python3.11"
  timeout       = 60
  memory_size   = 256

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      BUCKET        = var.bucket_name
      GLUE_JOB_NAME = var.glue_job_name
      SNS_TOPIC_ARN = aws_sns_topic.alerts.arn
      SOURCE_API_URL = var.source_api_url
      RAW_PREFIX     = var.raw_prefix
    }
  }
}

# ---------------------------
# IAM - Glue
# ---------------------------
data "aws_iam_policy_document" "glue_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "glue_role" {
  name               = "${var.project_name}-glue-role"
  assume_role_policy = data.aws_iam_policy_document.glue_assume.json
}

resource "aws_iam_role_policy" "glue_policy" {
  name = "${var.project_name}-glue-policy"
  role = aws_iam_role.glue_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      # S3 read/write
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ],
        Resource = [
          aws_s3_bucket.fuel.arn,
          "${aws_s3_bucket.fuel.arn}/*"
        ]
      },
      # CloudWatch Logs
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      },
      # SNS publish
      {
        Effect = "Allow",
        Action = ["sns:Publish"],
        Resource = aws_sns_topic.alerts.arn
      }
    ]
  })
}

resource "aws_glue_job" "fuel_job" {
  name     = var.glue_job_name
  role_arn = aws_iam_role.glue_role.arn

  glue_version = "5.0"
  number_of_workers = 2
  worker_type       = "G.1X"

  command {
    name            = "glueetl"
    python_version  = "3"
    script_location = "s3://${var.bucket_name}/${aws_s3_object.glue_script.key}"
  }

  default_arguments = {
    "--bucket"        = var.bucket_name
    "--raw_prefix"    = var.raw_prefix
    "--curated_prefix"= var.curated_prefix
    "--sns_topic_arn" = aws_sns_topic.alerts.arn
    "--TempDir"       = "s3://${var.bucket_name}/tmp/"
    "--job-language"  = "python"
  }
}

# ---------------------------
# EventBridge -> Lambda (schedule)
# ---------------------------
resource "aws_cloudwatch_event_rule" "schedule" {
  name                = "${var.project_name}-schedule"
  schedule_expression = var.schedule_expression
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.schedule.name
  target_id = "lambda"
  arn       = aws_lambda_function.fuel_ingest.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.fuel_ingest.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.schedule.arn
}
