output "cluster_arn" {
  description = "The Redshift cluster ARN"
  value       = try(aws_redshift_cluster.this.arn, null)
}

output "cluster_identifier" {
  description = "The Redshift cluster identifier"
  value       = try(aws_redshift_cluster.this.cluster_identifier, null)
}

output "cluster_subnet_group_name" {
  description = "Redshift cluster subnet group name"
  value       = aws_redshift_cluster.this.cluster_subnet_group_name
}

output "cluster_endpoint" {
  description = "Redshift endpoint address"
  value       = try(aws_redshift_cluster.this.endpoint, null)
}

output "cluster_hostname" {
  description = "The hostname of the Redshift cluster"
  value = replace(
    try(aws_redshift_cluster.this.endpoint, ""),
    format(":%s", try(aws_redshift_cluster.this.port, "")),
    "",
  )
}

output "cluster_dns_name" {
  description = "The DNS name of the cluster"
  value       = try(aws_redshift_cluster.this.dns_name, null)
}

output "cluster_port" {
  description = "Redshift cluster port"
  value       = try(aws_redshift_cluster.this.port, "")
}

output "cluster_jdbc_url" {
  description = "JDBC connection URL"
  value       = "jdbc:redshift://${aws_redshift_cluster.this.endpoint}:/${var.database_name}"
}

output "redshift_role_arn" {
  description = "IAM Role ARN attached to Redshift"
  value       = aws_iam_role.redshift.arn
}

output "s3_log_bucket_name" {
  description = "S3 bucket name used to store Redshift logs (if created or provided)"
  value       = var.log_destination == "s3" ? (var.create_s3_bucket ? aws_s3_bucket.logs[0].bucket : var.s3_bucket_name) : ""
}

output "kms_key_id" {
  description = "KMS key id/arn used for encryption (if created or provided)"
  value       = aws_kms_key.kms_cmk_key[0].id
}

output "kms_key_arn" {
  description = "KMS key ARN used for logs/cluster"
  value       = var.kms_key_id != "" ? var.kms_key_id : (length(aws_kms_key.kms_cmk_key) > 0 ? aws_kms_key.kms_cmk_key[0].arn : "")
}

output "secrets_manager_name" {
  description = "Name(id) of the Secrets Manager secret that stores master credentials"
  value       = aws_secretsmanager_secret.this.id
}

output "secrets_manager_arn" {
  description = "ARN of the Secrets Manager secret that stores master credentials"
  value       = aws_secretsmanager_secret.this.arn
}

output "secret_post_cluster_version_id" {
  description = "Secrets Manager secret version id that includes endpoint and port (created after cluster)"
  value       = aws_secretsmanager_secret_version.this.version_id
  # sensitive   = true
}
