module "redshift" {
  source = "./redshift-cluster"

  cluster_identifier = "duke-iam-redshift-cluster"
  database_name      = "analytics"
  master_username    = "rs_admin"

  # Replace these with your actual existing subnets & security groups
  vpc_id             = "vpc-07b3e9e8021bfb088"
  vpc_cidr           = "172.16.0.0/16"
  subnet_ids         = ["subnet-0260bb197628ace27", "subnet-0d316885c8257bf12"]
  security_group_ids = ["sg-0de16399c9a9f8f6e"]

  use_existing_lambda_rotator_sg             = true
  use_existing_vpce_sg                       = true
  existing_vpce_security_group_ids           = ["sg-0de16399c9a9f8f6e"]
  existing_lambda_rotator_security_group_ids = ["sg-0de16399c9a9f8f6e"]


  tags = {
    Environment = "sbx"
    Owner       = "cloud-infra-devops"
    Project     = "analytics-platform"
  }
}
