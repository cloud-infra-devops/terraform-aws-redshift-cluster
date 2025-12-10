module "redshift" {
  source = "./redshift-cluster"

  cluster_identifier = "example-redshift-01"
  database_name      = "analytics"
  master_username    = "rs_admin"

  # Replace these with your actual existing subnets & security groups
  subnet_ids         = ["subnet-0260bb197628ace27", "subnet-0d316885c8257bf12"]
  security_group_ids = ["sg-0de16399c9a9f8f6e"]

  enable_cloudwatch_alarms       = true
  cloudwatch_alarm_cpu_threshold = 80

  enable_maintenance_window    = true
  preferred_maintenance_window = "sun:23:00-mon:01:00"

  rotation_enabled       = true
  rotation_schedule_days = 1

  tags = {
    Environment = "dev"
    Owner       = "cloud-infra-devops"
    Project     = "analytics-platform"
  }
}
