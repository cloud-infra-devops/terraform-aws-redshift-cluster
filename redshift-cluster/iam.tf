data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["redshift.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "redshift" {
  name               = "${var.cluster_identifier}-redshift-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
  tags               = var.tags
}

data "aws_iam_policy_document" "redshift_policy" {
  statement {
    sid    = "AllowGetSecret"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]
    resources = [aws_secretsmanager_secret.this.arn]
  }

  statement {
    sid    = "AllowS3Logs"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:AbortMultipartUpload",
      "s3:ListBucket",
      "s3:GetBucketLocation"
    ]
    resources = concat(
      var.log_destination == "s3" && var.create_s3_bucket ? [aws_s3_bucket.logs[0].arn] : (var.log_destination == "s3" && !var.create_s3_bucket && var.s3_bucket_name != "" ? ["arn:aws:s3:::" + var.s3_bucket_name] : []),
      var.log_destination == "s3" && var.create_s3_bucket ? ["${aws_s3_bucket.logs[0].arn}/*"] : (var.log_destination == "s3" && !var.create_s3_bucket && var.s3_bucket_name != "" ? ["arn:aws:s3:::" + var.s3_bucket_name + "/*"] : [])
    )
  }

  statement {
    sid    = "AllowCWLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
      "logs:CreateLogGroup"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowUseOfKMSKey"
    effect = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey"
    ]
    resources = var.kms_key_id != "" ? [var.kms_key_id] : (length(aws_kms_key.logs_key) > 0 ? [aws_kms_key.logs_key[0].arn] : [])
  }
}

resource "aws_iam_policy" "redshift_policy" {
  name   = "${var.cluster_identifier}-redshift-policy"
  policy = data.aws_iam_policy_document.redshift_policy.json
  tags   = var.tags
}

resource "aws_iam_role_policy_attachment" "attach" {
  role       = aws_iam_role.redshift.name
  policy_arn = aws_iam_policy.redshift_policy.arn
}
