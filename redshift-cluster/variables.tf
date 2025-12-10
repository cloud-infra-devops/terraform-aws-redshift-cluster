variable "cluster_identifier" {
  description = "Identifier for the Redshift cluster"
  type        = string
}

variable "database_name" {
  description = "Initial DB name for the cluster"
  type        = string
  default     = "dev"
}

variable "master_username" {
  description = "Master username for the Redshift cluster"
  type        = string
  default     = "admin"
}

variable "master_password" {
  description = "Master password for the Redshift cluster. If empty, it will be generated."
  type        = string
  default     = ""
  sensitive   = true
}

variable "generate_password" {
  description = "When true and master_password is empty, a random password will be generated"
  type        = bool
  default     = true
}

variable "node_type" {
  description = "Redshift node type"
  type        = string
  default     = "dc2.large"
}

variable "cluster_type" {
  description = "Redshift cluster type (single-node or multi-node)"
  type        = string
  default     = "multi-node"
}

variable "number_of_nodes" {
  description = "Number of nodes (ignored for single-node)"
  type        = number
  default     = 2
}

variable "subnet_ids" {
  description = "List of subnet IDs in the existing VPC for Redshift subnet group"
  type        = list(string)
}

variable "security_group_ids" {
  description = "List of security group IDs to associate with the cluster"
  type        = list(string)
}

variable "cluster_subnet_group_name" {
  description = "Optional existing Redshift subnet group name. If empty, module will create one."
  type        = string
  default     = ""
}

variable "log_destination" {
  description = "Where to store Redshift logs. Valid values: 's3' or 'cloudwatch'"
  type        = string
  default     = "s3"
}

variable "create_s3_bucket" {
  description = "When true and log_destination is 's3', create the S3 bucket for logs"
  type        = bool
  default     = true
}

variable "s3_bucket_name" {
  description = "If create_s3_bucket is false and log_destination is 's3', this is the existing bucket name to use"
  type        = string
  default     = ""
}

variable "s3_key_prefix" {
  description = "Prefix within the S3 bucket for Redshift logs"
  type        = string
  default     = "redshift-logs/"
}

variable "enable_cloudwatch_alarms" {
  description = "Create sample CloudWatch alarms for common Redshift metrics"
  type        = bool
  default     = true
}

variable "cloudwatch_alarm_cpu_threshold" {
  description = "CPUUtilization alarm threshold percent"
  type        = number
  default     = 90
}

variable "kms_key_alias" {
  description = "Optional KMS Key alias to create/attach. If empty, a KMS key is created automatically. NOTE: If you provide kms_key_id, that will be used."
  type        = string
  default     = ""
}

variable "kms_key_id" {
  description = "Optional: existing KMS key ARN to use for Redshift and S3 bucket. If provided this will be used."
  type        = string
  default     = ""
}

variable "enable_maintenance_window" {
  description = "Whether to set a maintenance window using preferred_maintenance_window"
  type        = bool
  default     = false
}

variable "preferred_maintenance_window" {
  description = "Maintenance window in the form 'ddd:hh:MM-ddd:hh:MM' (example: sun:23:00-mon:01:30)"
  type        = string
  default     = "sun:23:00-sun:23:30"
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

variable "force_destroy_s3_bucket" {
  description = "When true, force destroy S3 bucket when destroying module"
  type        = bool
  default     = false
}

# variable "region" {
#   description = "AWS region (optional - can be inherited from provider)"
#   type        = string
#   default     = ""
# }

variable "rotation_enabled" {
  description = "Whether to enable Secrets Manager rotation using the provided Lambda rotation function"
  type        = bool
  default     = true
}

variable "rotation_schedule_days" {
  description = "Rotation schedule in days"
  type        = number
  default     = 180
}

variable "cw_logs_retention_days" {
  description = "cloudwatch logs retention period in days"
  type        = number
  default     = 1
}
