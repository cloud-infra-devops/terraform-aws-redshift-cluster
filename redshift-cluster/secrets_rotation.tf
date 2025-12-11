# Note: aws_lambda_permission must allow principal = "secretsmanager.amazonaws.com"
# and typically should restrict source_arn to the secret ARN. We attach the permission
# to the specific published Lambda version (qualifier) that we created.
locals {
  vpce_sg_ids           = var.use_existing_vpce_sg && length(var.existing_vpce_security_group_ids) > 0 ? var.existing_vpce_security_group_ids : [aws_security_group.vpce_sg[0].id]
  lambda_rotator_sg_ids = var.use_existing_lambda_rotator_sg && length(var.existing_lambda_rotator_security_group_ids) > 0 ? var.existing_lambda_rotator_security_group_ids : [aws_security_group.rotator_lambda_security_group[0].id]
}
# Security group for the VPC Interface Endpoint
resource "aws_security_group" "vpce_sg" {
  depends_on  = [var.security_group_ids]
  count       = var.use_existing_vpce_sg && length(var.existing_vpce_security_group_ids) > 0 ? 0 : 1
  name        = "${var.cluster_identifier}-secretsmanager-vpce-sg"
  description = "SG for Secrets Manager VPC endpoint interface"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.cluster_identifier}-vpce-sg" })
}
resource "aws_security_group_rule" "vpce_ingress" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = var.security_group_ids[0]
  security_group_id        = aws_security_group.vpce_sg.id
}
resource "aws_security_group_rule" "vpce_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.vpce_sg.id
}

# Security group for the Rotator Lambda Function
resource "aws_security_group" "rotator_lambda_security_group" {
  count  = var.use_existing_lambda_rotator_sg && length(var.existing_lambda_rotator_security_group_ids) > 0 ? 0 : 1
  name   = "rotator_lambda_security_group"
  vpc_id = var.vpc_id
  tags = {
    Name = "rotator_lambda_security_group"
  }
}
resource "aws_security_group_rule" "lambda_security_group_egress_rule1" {
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
  security_group_id = aws_security_group.rotator_lambda_security_group.id
}
resource "aws_security_group_rule" "lambda_security_group_egress_rule2" {
  type              = "egress"
  from_port         = var.port
  to_port           = var.port
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
  security_group_id = aws_security_group.rotator_lambda_security_group.id
}
resource "aws_security_group_rule" "lambda_security_group_ingress_rule" {
  type              = "ingress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = [var.vpc_cidr]
  security_group_id = aws_security_group.rotator_lambda_security_group.id
}

# VPC endpoint for Secrets Manager to keep rotation traffic inside VPC
resource "aws_vpc_endpoint" "secretsmanager-vpce" {
  vpc_id             = var.vpc_id
  service_name       = "com.amazonaws.${data.aws_region.current.region}.secretsmanager"
  vpc_endpoint_type  = "Interface"
  subnet_ids         = var.subnet_ids
  security_group_ids = local.vpce_sg_ids
  # private_dns_enabled = true
  tags = merge(var.tags, { Name = "${var.cluster_identifier}-sm-vpce" })
}

# IAM role used by Lambda rotation function (least privilege)
resource "aws_iam_role" "lambda_rotator_assume_role" {
  name = "${var.cluster_identifier}-secret-rotation-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "lambda.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
  tags = merge(var.tags, { Name = "${var.cluster_identifier}-rotation-role" })
}

# Managed policy attachments and a minimal inline policy restricted to the secret and redshift cluster
resource "aws_iam_role_policy" "lambda_rotator_inline_policy" {
  name = "${var.cluster_identifier}-rotation-inline"
  role = aws_iam_role.lambda_rotator_assume_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "AllowSecretAccess"
        Effect = "Allow"
        Action = [
          "secretsmanager:DescribeSecret",
          "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue",
          "secretsmanager:UpdateSecretVersionStage"
        ]
        Resource = aws_secretsmanager_secret.this.arn
      },
      {
        Sid    = "AllowKMSForSecret"
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = ["${var.kms_key_id != "" ? var.kms_key_id : (length(aws_kms_key.kms_cmk_key) > 0 ? aws_kms_key.kms_cmk_key[0].arn : "")}"]
      },
      # {
      #   Sid    = "AllowRDSPasswordUpdate"
      #   Effect = "Allow"
      #   Action = [
      #     "rds:ModifyDBCluster",
      #     "rds:DescribeDBClusters"
      #   ]
      #   Resource = aws_rds_cluster.this.arn
      # },
      {
        Sid    = "AllowNetworkingToSecretsManager"
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = ["arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${aws_lambda_function.rotation[0].function_name}:*"]
      }
    ]
  })
}

data "archive_file" "rotation_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda/rotation.zip"

  source {
    content  = file("${path.module}/rotation_handler.py")
    filename = "rotation_handler.py"
  }
}

# IAM role for Lambda rotation function (created with assume role only)
# data "aws_iam_policy_document" "lambda_assume" {
#   statement {
#     actions = ["sts:AssumeRole"]
#     principals {
#       type        = "Service"
#       identifiers = ["lambda.amazonaws.com"]
#     }
#   }
# }

# resource "aws_iam_role" "rotation_lambda" {
#   count              = var.enable_auto_secrets_rotation ? 1 : 0
#   name               = "${var.cluster_identifier}-rotation-lambda-role"
#   assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
#   tags               = var.tags
# }

# AWS managed single-user rotation Lambda function code via Lambda ARN or deploying from AWS provided blueprint
# Here we use the AWS managed rotation function hosted as a Lambda in your account via a published blueprint package.

resource "aws_iam_role" "lambda_exec" {
  count = var.enable_auto_secrets_rotation ? 1 : 0
  name  = "${var.cluster_identifier}-lambda-exec-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "lambda.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
  tags = merge(var.tags, { Name = "${var.cluster_identifier}-lambda-exec" })
}

resource "aws_iam_role_policy_attachment" "lambda_vpc_access_attachment" {
  role       = aws_iam_role.lambda_exec[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}
resource "aws_iam_role_policy_attachment" "lambda_basic_exec_policy_attachment" {
  role       = aws_iam_role.lambda_exec[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
# resource "aws_iam_role_policy_attachment" "lambda_custom_exec_policy_attachment" {
#   role       = aws_iam_role.lambda_exec[0].name
#   policy_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/${var.cluster_identifier}-rotation-lambda-policy"
# }

# # Allow Lambda access to VPC for Secrets Manager VPC Endpoint
# resource "aws_iam_role_policy" "lambda_vpc" {
#   name = "${var.cluster_identifier}-lambda-vpc"
#   role = aws_iam_role.lambda_exec[0].id
#   policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [
#       {
#         Effect = "Allow",
#         Action = [
#           "ec2:CreateNetworkInterface",
#           "ec2:DescribeNetworkInterfaces",
#           "ec2:DeleteNetworkInterface"
#         ],
#         Resource = "*"
#       },
#       {
#         Sid    = "AllowKMSForLambdaEnv",
#         Effect = "Allow",
#         Action = [
#           "kms:Decrypt",
#           "kms:Encrypt",
#           "kms:GenerateDataKey",
#           "kms:DescribeKey"
#         ],
#         Resource = ["${var.kms_key_id != "" ? var.kms_key_id : (length(aws_kms_key.kms_cmk_key) > 0 ? aws_kms_key.kms_cmk_key[0].arn : "")}"]
#       }
#     ]
#   })
# }

# Tight inline policy attached to the Lambda role (existing from earlier)
data "aws_iam_policy_document" "rotation_lambda_policy" {
  count = var.enable_auto_secrets_rotation ? 1 : 0

  dynamic "statement" {
    for_each = [
      {
        sid       = "AllowNetworking"
        actions   = ["ec2:CreateNetworkInterface", "ec2:DescribeNetworkInterfaces", "ec2:DeleteNetworkInterface"]
        resources = ["*"]
      },
      {
        sid       = "AllowLambdaWriteLogs"
        actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        resources = ["arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${aws_lambda_function.rotation[0].function_name}:*"]
      },
      {
        sid       = "AllowSecretsManager"
        actions   = ["secretsmanager:GetSecretValue", "secretsmanager:PutSecretValue", "secretsmanager:DescribeSecret", "secretsmanager:UpdateSecretVersionStage"]
        resources = ["arn:aws:secretsmanager:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:secret:${var.cluster_identifier}-${random_id.index.hex}"]
      },
      {
        sid       = "AllowRedshiftModify"
        actions   = ["redshift:ModifyCluster", "redshift:DescribeClusters"]
        resources = ["arn:aws:redshift:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:cluster:${var.cluster_identifier}"]
      },
      {
        sid       = "AllowKMS"
        actions   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
        resources = var.kms_key_id != "" ? [var.kms_key_id] : (length(aws_kms_key.kms_cmk_key) > 0 ? [aws_kms_key.kms_cmk_key[0].arn] : [])
      }
    ]
    content {
      sid       = statement.value.sid
      effect    = "Allow"
      actions   = statement.value.actions
      resources = statement.value.resources
    }
  }
}

resource "aws_iam_role_policy" "rotation_lambda_policy_attachment" {
  # ensure the lambda exists before attaching the inline policy so we can reference its name in the policy document
  depends_on = [aws_lambda_function.rotation]
  count      = var.enable_auto_secrets_rotation ? 1 : 0
  name       = "${var.cluster_identifier}-rotation-lambda-policy"
  role       = aws_iam_role.lambda_exec[0].id
  policy     = data.aws_iam_policy_document.rotation_lambda_policy[0].json
}
# Determine if Lambda should be deployed in VPC
locals {
  lambda_has_vpc = length(var.subnet_ids) > 0 && length(var.existing_lambda_rotator_security_group_ids) > 0
}

# Create the Lambda function
resource "aws_lambda_function" "rotation" {
  depends_on = [aws_iam_role.lambda_exec]
  count      = var.enable_auto_secrets_rotation ? 1 : 0

  filename         = data.archive_file.rotation_zip.output_path
  source_code_hash = data.archive_file.rotation_zip.output_base64sha256
  function_name    = "${var.cluster_identifier}-secrets-rotation"
  handler          = "rotation_handler.lambda_handler"
  runtime          = "python3.12"
  role             = aws_iam_role.lambda_exec[0].arn
  timeout          = 300
  publish          = true
  architectures    = ["x86_64"]
  ephemeral_storage {
    size = 1024
  }
  dynamic "vpc_config" {
    for_each = local.lambda_has_vpc ? [1] : []
    content {
      subnet_ids         = var.subnet_ids
      security_group_ids = local.lambda_rotator_sg_ids
    }
  }
  environment {
    variables = {
      CLUSTER_IDENTIFIER = var.cluster_identifier
      SECRET_ARN         = aws_secretsmanager_secret.this.arn
      REGION             = data.aws_region.current.region
    }
  }
}

# Grant Secrets Manager permission to invoke the Lambda function.
# Restrict invocation to the specific secret by using source_arn.
resource "aws_lambda_permission" "allow_secretsmanager_invoke" {
  # Ensure this permission is created only after the function is published
  depends_on = [aws_lambda_function.rotation]
  count      = var.enable_auto_secrets_rotation ? 1 : 0

  statement_id  = "AllowSecretsManagerInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.rotation[0].function_name
  principal     = "secretsmanager.amazonaws.com"
  source_arn    = aws_secretsmanager_secret.this.arn
  # Qualifier targets the published version created by publish = true above.
  qualifier = aws_lambda_function.rotation[0].version
}

# Use the published version ARN (function ARN + ":" + version) for rotation configuration.
resource "aws_secretsmanager_secret_rotation" "rotation" {
  depends_on = [
    aws_lambda_permission.allow_secretsmanager_invoke,
    aws_lambda_function.rotation
  ]
  count = var.enable_auto_secrets_rotation ? 1 : 0

  secret_id = aws_secretsmanager_secret.this.id
  # IMPORTANT: use the versioned Lambda ARN so Secrets Manager invokes the exact version the permission covers
  rotation_lambda_arn = "${aws_lambda_function.rotation[0].arn}:${aws_lambda_function.rotation[0].version}"
  rotation_rules {
    automatically_after_days = var.rotation_schedule_days
  }
}

# Resource policy for the secret limiting access to rotation role and account root
resource "aws_secretsmanager_secret_policy" "secret_policy" {
  secret_arn = aws_secretsmanager_secret.this.arn
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "AllowRotationRoleAccess"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.lambda_exec[0].arn
        }
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:PutSecretValue",
          "secretsmanager:UpdateSecretVersionStage"
        ]
        Resource = aws_secretsmanager_secret.this.arn
      },
      {
        Sid    = "AllowAccountAdminRead"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = aws_secretsmanager_secret.this.arn
      }
    ]
  })
}
