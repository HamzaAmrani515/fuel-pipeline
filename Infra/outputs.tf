output "bucket" {
  value = var.bucket_name
}

output "sns_topic_arn" {
  value = aws_sns_topic.alerts.arn
}

output "lambda_name" {
  value = aws_lambda_function.fuel_ingest.function_name
}

output "glue_job_name" {
  value = aws_glue_job.fuel_job.name
}
