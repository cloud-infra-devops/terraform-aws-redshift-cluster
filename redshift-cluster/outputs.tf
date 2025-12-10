output "cluster_endpoint" {
  description = "Redshift cluster endpoint"
  value       = aws_redshift_cluster.this.endpoint
}

output "cluster_port" {
  description = "Redshift cluster port"
  value       = aws_redshift_cluster.this.port
}

output "cluster_jdbc_url" {
  description = "JDBC connection URL"
  value       = "jdbc:redshift://${aws_redshift_cluster.this.endpoint}:${aws_redshift_cluster.this.port}/${var.database_name}"
}

output "secret_arn" {
  description = "ARN of the Secrets Manager secret containing credentials + endpoint"
  value       = aws_secretsmanager_secret.this.arn
}

output "redshift_role_arn" {
  description = "IAM Role ARN attached to Redshift"
  value       = aws_iam_role.redshift.arn
}

output "s3_log_bucket_name" {
  description = "S3 bucket name used to store Redshift logs (if created or provided)"
  value       = var.log_destination == "s3" ? (var.create_s3_bucket ? aws_s3_bucket.logs[0].bucket : var.s3_bucket_name) : ""
}

output "kms_key_arn" {
  description = "KMS key ARN used for logs/cluster"
  value       = var.kms_key_id != "" ? var.kms_key_id : (length(aws_kms_key.logs_key) > 0 ? aws_kms_key.logs_key[0].arn : "")
}