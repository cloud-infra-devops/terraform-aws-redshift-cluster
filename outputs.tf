output "redshift_endpoint" {
  value = module.redshift.cluster_endpoint
}

output "redshift_jdbc" {
  value = module.redshift.cluster_jdbc_url
}

output "redshift_secret_arn" {
  value = module.redshift.secret_arn
}