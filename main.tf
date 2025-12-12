# Terraform configuration for deploying a Redshift cluster using a reusable module

# Example usage of the redshift-cluster module
module "redshift" {
  source = "./redshift-cluster"

  cluster_identifier = "duke-ima-redshift-cluster"
  database_name      = "analytics"
  master_username    = "rs_admin"

  # Replace these with your actual existing subnets & security groups
  vpc_id     = "vpc-07b3e9e8021bfb088"
  vpc_cidr   = "172.16.0.0/16"
  subnet_ids = ["subnet-0260bb197628ace27", "subnet-0d316885c8257bf12"]

  use_existing_redshift_sg       = true
  use_existing_lambda_rotator_sg = true
  use_existing_vpce_sg           = true
  # existing_vpce_security_group_ids = module.sg-module.vpc_endpoint_sg
  # existing_redshift_security_group_ids = module.sg-module.redshift_sg
  # existing_lambda_rotator_security_group_ids = module.sg-module.lambda_rotate_sql_server_sg

  tags = {
    Dept  = "Cloud-Infra-DevOps"
    Owner = "Duke-Energy"
  }
}



# module "redshift" {
#   source                          = "../modules/redshift"
#   cluster_identifier              = "duke-ima-redshift-module-demo"
#   vpc_id                          = "vpc-012f359c4dc24e453"                                  # must exist in Duke's AWS account
#   subnet_ids                      = ["subnet-029ec1d4cdccca4ec", "subnet-0613a41e7061d910e"] # must exist in Duke's AWS account
#   redshift_vpc_security_group_ids = module.sg-module.redshift_sg
#   db_name                         = "analytics"
#   master_username                 = "admin"
#   multi_az                        = false
#   # Let module create KMS key and log bucket
#   create_new_kms_key = true
#   create_log_bucket  = true

#   # monitoring
#   create_monitoring_alarm = true

#   tags = {
#     # Environment = "dev"
#     Dept  = "Cloud-Infra-DevOps"
#     Owner = "Duke-Energy"
#   }
# }
/*
# Example usage of the aurora postgresql module
module "aurora_postgres_cluster" {
  source                                     = "../modules/aurorapostgreSQL"
  name                                       = "duke-app"
  vpc_id                                     = "vpc-012f359c4dc24e453"
  vpc_cidr                                   = "172.16.0.0/16"
  allowed_other_ingress_cidrs                = ["10.0.0.0/8", "192.168.0.0/16"]
  use_existing_aurora_db_sg                  = false
  use_existing_lambda_rotator_sg             = false
  use_existing_vpce_sg                       = false
  existing_aurora_db_security_group_ids      = []
  existing_lambda_rotator_security_group_ids = []
  existing_vpce_security_group_ids           = []
  subnet_ids                                 = ["subnet-029ec1d4cdccca4ec", "subnet-0613a41e7061d910e", "subnet-055e36176ca7c018d"]
  vpc_endpoint_subnet_ids                    = ["subnet-029ec1d4cdccca4ec", "subnet-0613a41e7061d910e", "subnet-055e36176ca7c018d"]
  db_master_username                         = "postgreSQLdbAdmin"
  enable_auto_secrets_rotation               = true
  use_existing_kms_key                       = false
  existing_kms_key_arn                       = null
  tags = {
    Dept  = "Cloud-Infra-DevOps"
    Owner = "Duke-Energy"
  }
}
*/
# # use if you ever need to reference your account id in terraform.
# data "aws_caller_identity" "this" {}

# # use if you ever need to reference default_tags in terraform.
# data "aws_default_tags" "default_tags" {}

###########################################################################################################
# data sources for the awscore provider
# documentation:
#  - https://github.com/dukeenergy-corp/de-aws-core-provider/tree/master/docs/data-sources
###########################################################################################################

# data "awscore_account_attributes" "self" {
#   aws_account_id = var.aws_account_id
# }

# data "awscore_account_config" "self" {
#   aws_account_id = var.aws_account_id
# }

# data "awscore_common" "shared" {}

# KMS key for S3 bucket encryption
# module "s3_kms" {
#   source  = "app.terraform.io/dukeenergy-corp/kms-module/aws"
#   version = "1.0.4"
#   alias   = "alias/aim-automation-poc-${var.environment}-s3"
# }

# KMS key for Secrets Manager encryption
#  module "secrets_kms" {
#   source  = "app.terraform.io/dukeenergy-corp/kms-module/aws"
#   version = "1.0.4"
#   alias   = "alias/aim-automation-poc-${var.environment}-secrets"
# }

# Security group rules for all managed security groups
# module "security_group_rules" {
#   source  = "app.terraform.io/dukeenergy-corp/sg-rule-module/aws"
#   version = "~> 1.0"

#   security_group_names = {
#     mngd-rds-postgres-sg = module.aurora_sg.rds_postgres_sg
#     mngd-redshift-sg     = module.redshift_sg.redshift_sg
#   }

#   vpc_cidr       = var.vpc_cidr
#   aws_account_id = var.aws_account_id

#   depends_on = [module.aurora_sg, module.redshift_sg]
# }
