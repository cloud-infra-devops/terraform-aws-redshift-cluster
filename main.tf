module "redshift" {
  source = "../../modules/redshift-cluster"

  cluster_identifier = "example-redshift-01"
  database_name      = "analytics"
  master_username    = "rs_admin"

  node_type       = "dc2.large"
  cluster_type    = "single-node"
  number_of_nodes = 1

  # Replace these with your actual existing subnets & security groups
  subnet_ids         = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
  security_group_ids = ["sg-0123456789abcdef0"]

  log_destination  = "s3"
  create_s3_bucket = true
  s3_key_prefix    = "redshift/logs/"

  enable_cloudwatch_alarms        = true
  cloudwatch_alarm_cpu_threshold  = 80

  enable_maintenance_window       = true
  preferred_maintenance_window    = "sun:23:00-mon:01:00"

  rotation_enabled  = true
  rotation_schedule_days = 30

  tags = {
    Environment = "dev"
    Owner       = "cloud-infra"
    Project     = "analytics-platform"
  }

  region = "us-east-1"
}