# CloudWatch log group (if using cloudwatch)
resource "aws_cloudwatch_log_group" "redshift_logs" {
  count = var.log_destination == "cloudwatch" ? 1 : 0

  name              = "/aws/redshift/${var.cluster_identifier}"
  retention_in_days = var.cw_logs_retention_days
  tags              = var.tags
}

resource "aws_cloudwatch_log_group" "lambda_rotation_logs" {
  count = var.enable_auto_secrets_rotation ? 1 : 0

  name              = "/aws/lambda/${var.cluster_identifier}-rotation-lambda"
  retention_in_days = var.cw_logs_retention_days
  tags              = var.tags
}

# Example CloudWatch alarm for CPU utilization
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${var.cluster_identifier}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/Redshift"
  period              = 300
  statistic           = "Average"
  threshold           = var.cloudwatch_alarm_cpu_threshold

  dimensions = {
    ClusterIdentifier = var.cluster_identifier
  }

  tags = var.tags
}
