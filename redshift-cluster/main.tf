# NOTE: This is the updated main.tf for the module with tightened KMS key policy.
# It assumes data.aws_caller_identity.current and data.aws_region.current are available
# elsewhere in the module (they are declared in iam.tf / secrets_rotation.tf in this module).
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  use_existing_subnet_group = length(trimspace(var.cluster_subnet_group_name)) > 0
  use_existing_kms          = length(trimspace(var.kms_key_id)) > 0
  use_s3_logs               = var.log_destination == "s3"
  s3_bucket_to_use          = var.create_s3_bucket ? "" : var.s3_bucket_name
  effective_logging_bucket  = local.use_s3_logs ? (var.create_s3_bucket ? aws_s3_bucket.logs[0].bucket : var.s3_bucket_name) : ""
  master_password_provided  = length(trimspace(var.master_password)) > 0

  # account and region
  account_id = data.aws_caller_identity.current.account_id
  # region     = var.region != "" ? var.region : data.aws_region.current.name
  region = data.aws_region.current.region

  # rotation lambda role arn only present when rotation_enabled and role count > 0
  rotation_role_arn = var.enable_auto_secrets_rotation && length(aws_iam_role.lambda_exec) > 0 ? aws_iam_role.lambda_exec[0].arn : ""

  # list of IAM principals (Redshift role + optional rotation lambda role)
  iam_principals = compact([aws_iam_role.redshift.arn, local.rotation_role_arn])

  # Build a KMS key policy that:
  # - Allows account root full admin
  # - Allows the module-created Redshift role and optional rotation role to use the key
  # - Allows the Redshift and Lambda service principals to use the key (scoped by account)
  kms_key_policy = jsonencode({
    Version = "2012-10-17"
    Id      = "key-default-1"
    Statement = [
      {
        Sid       = "AllowAdministration"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${local.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowIAMPrincipalsUse"
        Effect    = "Allow"
        Principal = { AWS = local.iam_principals }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      },
      {
        Sid       = "AllowRedshiftServiceUse"
        Effect    = "Allow"
        Principal = { Service = "redshift.amazonaws.com" }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource  = "*"
        Condition = { StringEquals = { "aws:SourceAccount" = local.account_id } }
      },
      {
        Sid       = "AllowLambdaServiceUse"
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource  = "*"
        Condition = { StringEquals = { "aws:SourceAccount" = local.account_id } }
      }
    ]
  })
}

resource "random_id" "index" {
  byte_length = 2
}

resource "random_password" "master" {
  count = var.generate_password && !local.master_password_provided ? 1 : 0

  # Choose length between 16 and 32 by default (Redshift requires 8..64)
  length = 16

  # Ensure upper, lower and numeric characters are present (Redshift requires at least one of each)
  upper   = true
  lower   = true
  numeric = true

  # Provide a safe override of special characters that avoids Redshift-disallowed characters:
  # Forbidden characters per Redshift API: / @ "  space  \  '
  # So we intentionally exclude those from override.
  special          = true
  override_special = "!#$%&()*-_=+[]{}<>?.,:;~`|"
}

# Use generated password or provided one
locals {
  generated_master_password = length(random_password.master) > 0 ? random_password.master[0].result : ""
}

# Secrets Manager secret (no version yet)
resource "aws_secretsmanager_secret" "this" {
  name        = "${var.cluster_identifier}-${random_id.index.hex}"
  description = "Redshift cluster credentials for ${var.cluster_identifier}"
  tags = merge(var.tags, {
    "redshift-cluster" = var.cluster_identifier
  })
}

# KMS key for logs & cluster encryption (created if not provided)
resource "aws_kms_key" "kms_cmk_key" {
  depends_on              = [local.use_existing_kms]
  count                   = local.use_existing_kms ? 0 : 1
  description             = "KMS key for Redshift logs and cluster '${var.cluster_identifier}'"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  tags                    = var.tags

  # Apply the tightened policy
  policy = local.kms_key_policy
}

resource "aws_kms_alias" "logs_key_alias" {
  depends_on    = [aws_kms_key.kms_cmk_key]
  count         = local.use_existing_kms || length(trimspace(var.kms_key_alias)) == 0 ? 0 : 1
  name          = "alias/${var.kms_key_alias}"
  target_key_id = aws_kms_key.kms_cmk_key[0].key_id
}

# S3 bucket for logs (optional)
resource "aws_s3_bucket" "logs" {
  count = local.use_s3_logs && var.create_s3_bucket ? 1 : 0

  bucket = "${var.cluster_identifier}-redshift-logs-${data.aws_caller_identity.current.account_id}"
  acl    = "private"

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = local.use_existing_kms ? var.kms_key_id : aws_kms_key.kms_cmk_key[0].arn
        sse_algorithm     = "aws:kms"
      }
    }
  }

  force_destroy = var.force_destroy_s3_bucket

  tags = merge(var.tags, {
    "log-bucket-for" = var.cluster_identifier
  })
}

resource "aws_s3_bucket_ownership_controls" "logs_ownership" {
  depends_on = [aws_s3_bucket.logs]
  count      = local.use_s3_logs && var.create_s3_bucket ? 1 : 0
  bucket     = aws_s3_bucket.logs[0].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# S3 bucket policy allowing Redshift role and redshift service to PutObject and ListBucket
data "aws_iam_policy_document" "s3_bucket_policy" {
  count = local.use_s3_logs ? 1 : 0

  dynamic "statement" {
    for_each = [
      {
        sid        = "AllowRedshiftPutObject"
        principals = [aws_iam_role.redshift.arn]
        actions    = ["s3:PutObject", "s3:PutObjectAcl", "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts"]
        resources = [
          "${local.use_s3_logs && var.create_s3_bucket ? aws_s3_bucket.logs[0].arn : "arn:aws:s3:::${var.s3_bucket_name}"}/*"
        ]
      },
      {
        sid        = "AllowRedshiftServicePutObject"
        principals = ["redshift.amazonaws.com"]
        actions    = ["s3:PutObject", "s3:PutObjectAcl"]
        resources = [
          "${local.use_s3_logs && var.create_s3_bucket ? aws_s3_bucket.logs[0].arn : "arn:aws:s3:::${var.s3_bucket_name}"}/*"
        ]
      },
      {
        sid        = "AllowListBucketRole"
        principals = [aws_iam_role.redshift.arn]
        actions    = ["s3:ListBucket"]
        resources = [
          local.use_s3_logs && var.create_s3_bucket ? aws_s3_bucket.logs[0].arn : "arn:aws:s3:::${var.s3_bucket_name}"
        ]
      },
      {
        sid        = "AllowListBucketService"
        principals = ["redshift.amazonaws.com"]
        actions    = ["s3:ListBucket"]
        resources = [
          local.use_s3_logs && var.create_s3_bucket ? aws_s3_bucket.logs[0].arn : "arn:aws:s3:::${var.s3_bucket_name}"
        ]
      }
    ]
    content {
      sid    = statement.value.sid
      effect = "Allow"
      principals {
        type        = statement.value.principals[0] == "redshift.amazonaws.com" ? "Service" : "AWS"
        identifiers = statement.value.principals
      }
      actions   = statement.value.actions
      resources = statement.value.resources
    }
  }
}

resource "aws_s3_bucket_policy" "logs_policy" {
  count = local.use_s3_logs ? 1 : 0

  bucket = local.use_s3_logs && var.create_s3_bucket ? aws_s3_bucket.logs[0].id : var.s3_bucket_name
  policy = data.aws_iam_policy_document.s3_bucket_policy[0].json
}

# Create the Redshift subnet group if needed
resource "aws_redshift_subnet_group" "this" {
  count = local.use_existing_subnet_group ? 0 : 1

  name       = "${var.cluster_identifier}-subnet-group"
  subnet_ids = var.subnet_ids
  tags       = var.tags
}

# The Redshift cluster (provider v6.25.0 logging block)
resource "aws_redshift_cluster" "this" {
  cluster_identifier = var.cluster_identifier
  database_name      = var.database_name
  master_username    = var.master_username

  master_password = local.master_password_provided ? var.master_password : local.generated_master_password

  node_type       = var.node_type
  cluster_type    = var.cluster_type
  number_of_nodes = var.cluster_type == "multi-node" ? var.number_of_nodes : 1

  vpc_security_group_ids    = var.security_group_ids
  cluster_subnet_group_name = local.use_existing_subnet_group ? var.cluster_subnet_group_name : aws_redshift_subnet_group.this[0].id

  iam_roles = [aws_iam_role.redshift.arn]

  encrypted                           = true
  kms_key_id                          = var.kms_key_id != "" ? var.kms_key_id : (length(aws_kms_key.kms_cmk_key) > 0 ? aws_kms_key.kms_cmk_key[0].arn : null)
  allow_version_upgrade               = true
  apply_immediately                   = false
  enhanced_vpc_routing                = var.enhanced_vpc_routing
  automated_snapshot_retention_period = var.automated_snapshot_retention_period
  # Final snapshot behaviour for deletes/replacements
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : (var.final_snapshot_identifier != "" ? var.final_snapshot_identifier : null)
  tags                      = var.tags
  # Maintenance window
  preferred_maintenance_window = var.enable_maintenance_window ? var.preferred_maintenance_window : null

  lifecycle {
    # master_password rotations are done via secrets manager; prevent accidental re-creation from password rotation
    # allow external role attachments without forcing recreation
    ignore_changes = [iam_roles, master_password]
  }
}

# Redshift logging configuration (separate resource)
# resource "aws_redshift_logging" "this" {
#   depends_on           = [local.effective_logging_bucket, aws_redshift_cluster.this]
#   count                = local.use_s3_logs ? 1 : 0
#   cluster_identifier   = aws_redshift_cluster.this.cluster_identifier
#   log_destination_type = var.log_destination
#   bucket_name          = local.effective_logging_bucket != "" ? local.effective_logging_bucket : null
#   s3_key_prefix        = var.s3_key_prefix != "" ? var.s3_key_prefix : null
#   log_exports          = []
# }

# After cluster exists, create/update Secrets Manager secret version with full details (credentials + endpoint/jdbc)
resource "aws_secretsmanager_secret_version" "this" {
  depends_on = [aws_secretsmanager_secret.this, aws_redshift_cluster.this]
  secret_id  = aws_secretsmanager_secret.this.id
  secret_string = jsonencode({
    username = var.master_username
    password = local.master_password_provided ? var.master_password : local.generated_master_password
    engine   = "redshift"
    host     = aws_redshift_cluster.this.endpoint
    port     = aws_redshift_cluster.this.port
    dbname   = var.database_name
    jdbc     = "jdbc:redshift://${aws_redshift_cluster.this.endpoint}:/${var.database_name}"
  })
}
