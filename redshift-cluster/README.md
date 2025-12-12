```markdown
# terraform-aws-redshift-cluster (module)

A reusable, production-oriented Terraform module that provisions an Amazon Redshift cluster into an existing VPC, securely stores cluster credentials in AWS Secrets Manager (and updates that secret with endpoint/port/JDBC after creation), configures logging to S3 or CloudWatch, encrypts logs with KMS, creates an IAM role for Redshift with least-privilege policies, and (optionally) enables automatic Secrets Manager rotation via a Lambda rotation handler.

This module targets the Terraform AWS Provider v6.25.0 (compatible with 6.x). See "Provider" below.

---

Table of contents
- Features
- Quick start
- Example usage
- Inputs (variables)
- Outputs
- Resources created
- Secrets Manager rotation design & implementation
- IAM & KMS security considerations
- Logging options (S3 vs CloudWatch)
- VPC & Lambda configuration
- Troubleshooting & common errors
- Testing / validation
- Extending the module
- Changelog / notes

---

Features
- Deploy Redshift cluster into existing subnets and security groups.
- Create (or use existing) Redshift subnet group.
- Store credentials in AWS Secrets Manager; automatically update secret after cluster creation with host, port, jdbc, dbname.
- Optional Secrets Manager rotation via a Lambda rotation handler (single-user rotation flow).
- Logging destination selection: S3 (create or use existing bucket) or CloudWatch.
- Create S3 log bucket with server-side encryption (KMS), object_ownership = BucketOwnerEnforced (disable ACLs).
- Create KMS key (or use existing) and apply a tightened key policy allowing the Redshift role, rotation Lambda role and service principals to use the key.
- Create IAM role for Redshift cluster, with least-privilege permissions to read the Secrets Manager secret, write logs to S3 (or CloudWatch), and use KMS for encryption/decryption.
- CloudWatch monitoring: sample CPU alarm and optional CloudWatch log group.
- Configurable maintenance window and tags.
- Defensive Terraform patterns for optional resources (conditional creation, safe indexing).

---

Quick start

1. Add the module to your root configuration:

module "redshift" {
  source = "path/to/modules/redshift-cluster"

  cluster_identifier = "example-redshift-01"
  database_name      = "analytics"
  master_username    = "rs_admin"

  subnet_ids         = ["subnet-aaa", "subnet-bbb"]            # existing VPC subnets
  security_group_ids = ["sg-aaa"]                            # existing SGs for cluster

  log_destination    = "s3"                                  # "s3" or "cloudwatch"
  create_s3_bucket   = true
  s3_key_prefix      = "redshift/logs/"

  rotation_enabled   = true
  rotation_schedule_days = 30

  tags = {
    Environment = "dev"
    Owner       = "platform"
  }

  region = "us-east-1"
}

2. terraform init && terraform plan && terraform apply

Notes:
- If you want the rotation Lambda inside your VPC, pass lambda_subnet_ids and lambda_security_group_ids. If left empty (default), the Lambda runs publicly (no ENIs).
- If you want to use an existing KMS key, pass kms_key_id; the module will not attempt to patch that key's policy.

---

Example (full)

See the included example under `examples/basic/` for a complete, runnable reference. It demonstrates S3 logging, created S3 bucket, rotation enabled, and sample tag usage.

---

Inputs (selected / important)

- cluster_identifier (string) - required
- database_name (string) - default "dev"
- master_username (string) - default "admin"
- master_password (string, sensitive) - optional; if empty the module generates a validated password.
  - Validation: 8..64 chars, must include at least one uppercase, one lowercase, and one digit; must not contain these characters: `/ @ " \ '` or space.
- generate_password (bool) - defaults to true
- node_type (string) - default "dc2.large"
- cluster_type (string) - "single-node" or "multi-node"
- number_of_nodes (number) - used when cluster_type = "multi-node"
- subnet_ids (list(string)) - required: existing VPC subnets
- security_group_ids (list(string)) - required: SGs for cluster
- cluster_subnet_group_name (string) - optional: use an existing Redshift subnet group
- log_destination (string) - "s3" or "cloudwatch" (default "s3")
- create_s3_bucket (bool) - if true (and log_destination="s3") module creates an S3 bucket
- s3_bucket_name (string) - existing bucket name when create_s3_bucket=false
- s3_key_prefix (string) - prefix for Redshift logs
- kms_key_id (string) - existing KMS key ARN/ID to use (module will not create or patch policy)
- kms_key_alias (string) - optional alias for created key
- rotation_enabled (bool) - enable Secrets Manager rotation via Lambda (default true)
- rotation_schedule_days (number) - days between automatic rotations (default 30)
- lambda_subnet_ids (list(string)) - optional: put rotation Lambda in VPC
- lambda_security_group_ids (list(string)) - optional: SGs for Lambda ENIs (must provide with lambda_subnet_ids)
- enable_cloudwatch_alarms (bool) - create example CloudWatch alarms
- preferred_maintenance_window (string) - maintenance window string, if enabled
- tags (map(string)) - resource tags
- region (string) - optional - provider region can alternatively be set in the root provider

See variables.tf for the full list and comments.

---

Outputs

- cluster_endpoint - Redshift endpoint (host)
- cluster_port - port (usually 5439)
- cluster_jdbc_url - jdbc:redshift://host:port/dbname
- secret_arn - ARN of the Secrets Manager secret (credentials + endpoint)
- redshift_role_arn - ARN of the IAM role attached to Redshift
- s3_log_bucket_name - S3 bucket name used for logs (if s3 chosen)
- kms_key_arn - ARNs of created/used KMS key

---

Resources created (summary)

Depending on inputs/flags the module may create:
- aws_redshift_cluster
- aws_redshift_subnet_group (optional)
- aws_secretsmanager_secret
- aws_secretsmanager_secret_version (updated after cluster creation)
- aws_lambda_function (rotation) + aws_iam_role + inline policy + aws_lambda_permission
- aws_secretsmanager_secret_rotation
- aws_kms_key (optional) + aws_kms_alias
- aws_s3_bucket (optional)
- aws_s3_bucket_policy
- aws_iam_role (redshift) + aws_iam_policy + aws_iam_role_policy_attachment
- aws_cloudwatch_log_group & aws_cloudwatch_metric_alarm (if chosen)

---

Secrets Manager rotation design

- The module includes a simple rotation Lambda (python3.11) implementing the single-user rotation flow:
  - createSecret: generate a new password and store as AWSPENDING
  - setSecret: call Redshift ModifyCluster to set the new password
  - testSecret: basic testing (cluster available)
  - finishSecret: promote AWSPENDING to AWSCURRENT
- Rotation is configured to use the published Lambda version ARN. Terraform creates the Lambda, publishes a version, attaches a resource policy (aws_lambda_permission) that allows the principal `secretsmanager.amazonaws.com` to invoke that published version, and then creates aws_secretsmanager_secret_rotation referencing the versioned Lambda ARN.
- The Lambda role is granted tightened permissions scoped to:
  - the specific secret ARN (Secrets Manager)
  - the specific Redshift cluster ARN (ModifyCluster/DescribeClusters)
  - the selected KMS key ARN (if created/used)
  - CloudWatch logs limited to the Lambda's own log group
- Important: the rotation Lambda uses ModifyCluster which may briefly affect cluster availability. This is a design trade-off for rotating the master user password. Test carefully and consider maintenance windows and client reconnection behavior.

---

IAM & KMS security considerations

- Redshift IAM role:
  - Has permissions to read the specific Secrets Manager secret.
  - Has S3 PutObject/List permission scoped to the log bucket / prefix (if using S3).
  - Has KMS usage permissions scoped to the created KMS key ARN (if the module created it), allowing encrypt/decrypt/generateDataKey etc.
- KMS key policy:
  - If the module creates a key (default), the key policy explicitly:
    - Gives account root administrative control.
    - Grants the Redshift IAM role and rotation Lambda role permissions to use the key.
    - Grants the Redshift and Lambda service principals permission to use the key (conditioned on the account id).
- If you supply an existing kms_key_id, the module will not patch that key's policy. If you want the module to manage the existing key's policy, enable/ask for an optional behavior (not enabled by default due to risk of unintended policy replacement).
- S3 bucket policy:
  - Grants the Redshift role and the `redshift.amazonaws.com` service principal PutObject/List permissions on the bucket and objects.
  - object_ownership = "BucketOwnerEnforced" disables ACLs to avoid ACL-based failures when Redshift writes logs.

---

Logging options

- S3 (recommended for long-term log storage)
  - Module can create a bucket encrypted with the selected KMS key.
  - The bucket is configured with server-side encryption using AWS KMS.
  - The module disables ACLs (BucketOwnerEnforced) to avoid cross-account or ACL issues.
- CloudWatch Logs
  - The module can create a Log Group and grants the Redshift role permissions scoped to that Log Group.
  - Note: in some accounts / regions Redshift -> CloudWatch logging requires additional configuration; validate in your target region.

Which to choose?
- Use S3 when you want durable, lifecycle-manageable logs (and integration with analytics / lifecycle rules).
- Use CloudWatch for real-time monitoring and metrics streaming.

---

VPC & Lambda configuration

- The rotation Lambda runs outside a VPC by default (recommended unless the Lambda requires access to resources inside your VPC).
- If you need the rotation Lambda inside a VPC (for example to reach a private Redshift cluster endpoint), pass `lambda_subnet_ids` and `lambda_security_group_ids` together. Both must be provided or neither.
- Placing the Lambda in a VPC will create ENIs and requires appropriate subnet and SG configuration to allow outbound HTTPS to Secrets Manager and permissions to use KMS & Redshift APIs. Ensure NAT gateway or VPC endpoints for Secrets Manager/Logs/KMS if required.

---

Troubleshooting & common errors

1. Secrets Manager cannot invoke Lambda (AccessDeniedException)
   - Cause: Lambda resource-based policy missing or not matching the exact Lambda version ARN used by rotation.
   - Fix: Module attaches `aws_lambda_permission` with `qualifier = aws_lambda_function.rotation.version` and uses the versioned ARN when creating the rotation resource. Ensure Terraform creates the Lambda and permission before the rotation resource (module already enforces depends_on).

2. "A previous rotation isn't complete"
   - Cause: A rotation run left an AWSPENDING version (Lambda failed before finishSecret).
   - Recovery:
     - Inspect versions: `aws secretsmanager list-secret-version-ids --secret-id <secret-arn> --region <region>`
     - Promote pending to current (if safe) or remove AWSPENDING stage.
     - Example to promote:
       aws secretsmanager update-secret-version-stage \
         --secret-id <secret-arn> \
         --version-stage AWSCURRENT \
         --move-to-version-id <pending-version-id> \
         --remove-from-version-id <current-version-id> \
         --region <region>

3. Invalid master password (Redshift CreateCluster rejected)
   - Cause: Redshift enforces allowed characters. Module's generator avoids `/ @ " \ '` and spaces. If you provide a password, ensure it matches the module validation: 8-64 chars, includes at least one upper, one lower, one digit, and no forbidden characters.

4. Invalid index / empty tuple when referencing optional resources
   - Cause: Terraform code attempted to index [0] of a resource with zero instances.
   - Fix: Module uses defensive patterns (try/for/expression) to safely handle optional resources.

5. Lambda vpc_config missing required fields error
   - Cause: Terraform expects `vpc_config` security_group_ids when vpc_config is declared.
   - Fix: Module only includes dynamic vpc_config if both lambda_subnet_ids and lambda_security_group_ids were supplied.

6. KMS key usage errors
   - If you use an existing KMS key and the Lambda/Redshift role cannot perform encrypt/decrypt, you must update the KMS key policy to allow these principals. The module-managed key policy already includes the required principals when the module creates a key.

---

Testing & validation

- Run terraform plan/apply in a sandbox first.
- Validate:
  - Cluster enters AVAILABLE state
  - Secrets Manager secret contains AWSCURRENT with username/password and host/port/jdbc (secret version updated after cluster created)
  - If rotation enabled: trigger manual rotation and inspect CloudWatch logs for the rotation Lambda and ensure new AWSCURRENT versions get promoted
  - S3 logs appear in the S3 bucket prefix if log_destination="s3" (bucket/prefix must be set)
  - CloudWatch CPU metric alarm should appear if enabled

Manual rotation test:
- Trigger: aws secretsmanager rotate-secret --secret-id <secret-arn> --region <region>
- Monitor: CloudWatch logs for the rotation Lambda and Secrets Manager secret version stages.

---

Extending the module

- Rotation Lambda:
  - The provided rotation handler is minimal. For a production-ready rotation consider:
    - Robust error handling and retries
    - Connection testing using a DB driver (packaging layer for psycopg2/pg8000)
    - Better audit/logging and alerting
- KMS policy:
  - If you want the module to patch an *existing* KMS key policy, add an optional boolean to let the module manage that policy (be mindful: re-writing existing policies can be sensitive).
- Multi-cluster support:
  - This module currently manages resources for one cluster. For many clusters, instantiate the module multiple times (with unique identifiers).

---

Changelog / important notes

- Target provider: hashicorp/aws >= 6.25.0, <7.0.0
- Terraform >= 1.1 recommended
- The module uses aws_lambda_permission with a version qualifier and aws_secretsmanager_secret_rotation referencing the versioned Lambda ARN to avoid `Secrets Manager cannot invoke the specified Lambda function` errors.

---

Security recommendations (must-read)

- Limit IAM policies further in production: tighten KMS, Redshift and Secrets Manager ARNs where possible.
- Consider using a dedicated KMS key for Redshift cluster and a separate key for S3 logs if stricter separation is required.
- Review the rotation Lambda's IAM role and reduce broad permissions (`DescribeClusters` etc.) where possible.
- Protect access to the Secrets Manager secret by limiting who/what can call GetSecretValue (and add monitoring for secret retrieval).

---

Contact / Support

If you find an issue or want the module adjusted for your environment (e.g., multi-account, cross-region, or stricter policies), open an issue or PR and include:
- Terraform & provider versions
- A plan/apply error (with non-sensitive parts)
- Whether you use an existing KMS key or the module-managed key

---

License

Add your project's license here.

---
```