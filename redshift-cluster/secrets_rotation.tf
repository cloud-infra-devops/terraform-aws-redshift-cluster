# Archive Lambda code
data "archive_file" "rotation_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda/rotation.zip"

  source {
    content  = file("${path.module}/lambda/rotation_handler.py")
    filename = "rotation_handler.py"
  }
  # requirements or additional packages are not packaged here; using pure-boto3 in Lambda runtime (boto3 is available in the Lambda runtime)
}

# IAM role for Lambda rotation function
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "rotation_lambda" {
  count              = var.rotation_enabled ? 1 : 0
  name               = "${var.cluster_identifier}-rotation-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "rotation_lambda_policy" {
  count = var.rotation_enabled ? 1 : 0

  statement {
    sid    = "AllowWriteLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.cluster_identifier}-rotation-lambda:*"]
  }

  statement {
    sid    = "AllowSecretsManager"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:PutSecretValue",
      "secretsmanager:DescribeSecret",
      "secretsmanager:UpdateSecretVersionStage"
    ]
    resources = [aws_secretsmanager_secret.this.arn]
  }

  statement {
    sid    = "AllowRedshiftModify"
    effect = "Allow"
    actions = [
      "redshift:ModifyCluster",
      "redshift:DescribeClusters"
    ]
    resources = ["*"] # ModifyCluster requires the cluster identifier; using * reduces complexity — tighten for production
  }

  statement {
    sid    = "AllowKMS"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:Encrypt",
      "kms:GenerateDataKey"
    ]
    resources = var.kms_key_id != "" ? [var.kms_key_id] : (length(aws_kms_key.logs_key) > 0 ? [aws_kms_key.logs_key[0].arn] : [])
  }
}

resource "aws_iam_role_policy" "rotation_lambda_policy_attach" {
  count  = var.rotation_enabled ? 1 : 0
  name   = "${var.cluster_identifier}-rotation-lambda-policy"
  role   = aws_iam_role.rotation_lambda[0].id
  policy = data.aws_iam_policy_document.rotation_lambda_policy[0].json
}

resource "aws_lambda_function" "rotation" {
  depends_on = [aws_iam_role_policy.rotation_lambda_policy_attach]
  count      = var.rotation_enabled ? 1 : 0

  filename         = data.archive_file.rotation_zip.output_path
  source_code_hash = data.archive_file.rotation_zip.output_base64sha256
  function_name    = "${var.cluster_identifier}-secrets-rotation"
  handler          = "rotation_handler.lambda_handler"
  runtime          = "python3.12"
  role             = aws_iam_role.rotation_lambda[0].arn
  timeout          = 300
  publish          = true
  architectures    = ["x86_64"]
  ephemeral_storage {
    size = 1024
  }
  environment {
    variables = {
      CLUSTER_IDENTIFIER = var.cluster_identifier
      SECRET_ARN         = aws_secretsmanager_secret.this.arn
      REGION             = data.aws_region.current.region
    }
  }
}

# Secrets Manager rotation configuration (single-user rotation strategy)
resource "aws_secretsmanager_secret_rotation" "rotation" {
  depends_on          = [aws_lambda_function.rotation]
  count               = var.rotation_enabled ? 1 : 0
  secret_id           = aws_secretsmanager_secret.this.id
  rotation_lambda_arn = aws_lambda_function.rotation[0].arn
  rotation_rules {
    automatically_after_days = var.rotation_schedule_days
  }
}
