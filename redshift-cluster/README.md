```markdown
# terraform-aws-redshift-cluster (module)

This Terraform module provisions an Amazon Redshift cluster into an existing VPC (using provided subnet IDs and security group IDs), configures secure storage of the cluster credentials in AWS Secrets Manager (and automatically updates the secret after cluster creation to include endpoint, port and JDBC URL), creates an IAM role for Redshift with permissions to read the secret and write logs, configures S3 or CloudWatch for Redshift logs, creates/enforces a KMS key for encryption, and adds automatic rotation of the Secrets Manager secret via a Lambda rotation function.

This version of the module targets the Terraform AWS provider v6.25.0 and uses the logging block syntax compatible with that provider (logging { enable, bucket_name, s3_key_prefix }).

Features
- Create or use an existing S3 bucket encrypted with KMS for Redshift logs (object_ownership set to BucketOwnerEnforced to disable ACLs)
- Create or use existing KMS key for logs and cluster encryption
- Create IAM role for Redshift with permissions to read the Secrets Manager secret, write to the S3 bucket, and use KMS for encryption/decryption
- Create Secrets Manager secret for cluster credentials and automatically update it after the cluster is created with endpoint, port, and jdbc URL
- Configure Secrets Manager rotation with a Lambda function (rotation handler included)
- Optionally store logs in CloudWatch Logs (creates log group and sample metrics/alarms)
- CloudWatch monitoring (sample CPU alarm)
- Ability to provide an existing Redshift subnet group or let the module create one

Important notes and caveats
- The included rotation Lambda uses the Redshift ModifyCluster API (via boto3) to change the master user password. Rotation using this method will perform a cluster modify and may cause brief disruptions; test thoroughly in non-production.
- The rotation Lambda in this module is a minimal example; in production you should harden, test, and extend the rotation function (for example adding retries, stronger secrets handling, and more robust testing).
- The module attempts to be compatible with AWS provider v6.25.0. If your provider version differs, you may need to adjust minor attribute names.
- The module generates a random master password by default; you may override it.

Structure
- main.tf: Core resources (KMS, S3 bucket, Redshift cluster, Redshift subnet group, IAM role/policies, Secrets Manager secret + version update).
- cloudwatch.tf: CloudWatch log group and sample alarms.
- secrets_rotation.tf: Lambda rotation function resources (archive, lambda, role, secret rotation).
- iam.tf: IAM policy documents used.
- variables.tf / outputs.tf: Inputs and outputs.

1. Logging block:
   - This module uses the logging {} block with enable, bucket_name and s3_key_prefix which is compatible with terraform-provider-aws v6.x.
   - If you choose `log_destination = "cloudwatch"`, this module will create a CloudWatch Log Group and CloudWatch metric alarm(s). Direct out-of-the-box Redshift -> CloudWatch Logs export may require additional account/console configuration in some regions/for some Redshift features; validate in your account.

2. Secrets Manager rotation:
   - The included Lambda rotation handler is a minimal example implementing the single-user rotation flow by calling Redshift ModifyCluster to change the master password.
   - ModifyCluster will update the master password and may briefly affect the cluster; test carefully.
   - The rotation Lambda assumes it has appropriate IAM permissions (attached by the module). In production you should tighten the resource ARNs for least privilege.
   - The rotation function is packaged using data.archive_file; if you extend the function and add dependencies, you must package those dependencies into the lambda zip (or use layers).

3. KMS:
   - The module supports using an existing KMS key by passing `kms_key_id`. Otherwise it creates one and uses it for both cluster and S3 encryption.
   - Ensure KMS key policy in your account allows Redshift (service principal) and the Redshift IAM role to use the key. The module's KMS resource is created with default policy for the account root; you may need to add service principals per your security posture.

4. S3:
   - object_ownership = "BucketOwnerEnforced" disables ACLs which is recommended for modern S3 usage and required so Redshift can put objects without ACL conflicts.
   - Bucket names are generated with the account id appended - you may want to override (or provide a pre-created bucket via s3_bucket_name).

5. Testing:
   - Test the module in a sandbox/non-prod environment.
   - Verify rotation, log delivery, and IAM permissions.

If you'd like, I can:
- Harden the rotation Lambda with retries and a test connection using psycopg2 (packaged into a Lambda layer).
- Split KMS keys: one for cluster encryption, one for S3 logs.
- Tighten IAM policy ARNs for the rotation Lambda and Redshift role.

See example usage in ../../examples/basic (example root module included in this submission).
```
