output "redshift_endpoint" {
  value = module.redshift.cluster_endpoint
}

output "redshift_jdbc" {
  value = module.redshift.cluster_jdbc_url
}

output "redshift_cluster_arn" {
  value = module.redshift.cluster_arn
}

output "redshift_cluster_identifier" {
  value = module.redshift.cluster_identifier
}

output "redshift_cluster_endpoint" {
  value = module.redshift.cluster_endpoint
}

output "redshift_cluster_hostname" {
  value = module.redshift.cluster_hostname
}

output "redshift_cluster_dns_name" {
  value = module.redshift.cluster_dns_name
}

output "redshift_cluster_subnet_group_name" {
  value = module.redshift.cluster_subnet_group_name
}

output "aws_secrets_manager_id" {
  value = module.redshift.secrets_manager_name
}

output "aws_secrets_manager_arn" {
  value = module.redshift.secrets_manager_arn
}

output "post_cluster_secrets_manager_version_id" {
  value = module.redshift.secret_post_cluster_version_id
}
