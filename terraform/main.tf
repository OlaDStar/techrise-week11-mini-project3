terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }
}

# ================================================================
# PROVIDERS
# ================================================================

# AWS credentials should come from environment variables,
# AWS CLI configuration, or an IAM role.
provider "aws" {
  region = "us-east-1"
}

# Secondary region for Cross-Region Replication.
provider "aws" {
  alias  = "replica"
  region = "eu-west-1"
}

# ================================================================
# DATA SOURCES
# ================================================================

data "aws_caller_identity" "current" {}

# ================================================================
# RANDOM SUFFIX
# Prevents globally unique S3 bucket name collisions.
# ================================================================

resource "random_id" "suffix" {
  byte_length = 4
}

# ================================================================
# PRIMARY KMS KEY
# Used to encrypt payment data and SNS events in us-east-1.
# ================================================================

resource "aws_kms_key" "payments" {
  description         = "KMS key for QuickPayNG payment data"
  enable_key_rotation = true

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "EnableAccountPermissions"
        Effect = "Allow"

        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }

        Action   = "kms:*"
        Resource = "*"
      }
    ]
  })
}

# ================================================================
# REPLICA-REGION KMS KEY
# Used for resources deployed in eu-west-1.
# ================================================================

resource "aws_kms_key" "replica" {
  provider            = aws.replica
  description         = "KMS key for QuickPayNG replica resources"
  enable_key_rotation = true

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "EnableAccountPermissions"
        Effect = "Allow"

        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }

        Action   = "kms:*"
        Resource = "*"
      }
    ]
  })
}

# ================================================================
# PRIMARY PAYMENT S3 BUCKET
# ================================================================

resource "aws_s3_bucket" "payments" {
  bucket = "quickpayng-payment-data-${random_id.suffix.hex}"

  tags = {
    Name        = "QuickPayNG Payment Data"
    Environment = "Demo"
  }
}

# ================================================================
# PRIMARY BUCKET PUBLIC ACCESS PROTECTION
# ================================================================

resource "aws_s3_bucket_public_access_block" "payments" {
  bucket = aws_s3_bucket.payments.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

# ================================================================
# PRIMARY BUCKET VERSIONING
# ================================================================

resource "aws_s3_bucket_versioning" "payments" {
  bucket = aws_s3_bucket.payments.id

  versioning_configuration {
    status = "Enabled"
  }
}

# ================================================================
# PRIMARY BUCKET KMS ENCRYPTION
# ================================================================

resource "aws_s3_bucket_server_side_encryption_configuration" "payments" {
  bucket = aws_s3_bucket.payments.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.payments.arn
      sse_algorithm     = "aws:kms"
    }

    bucket_key_enabled = true
  }
}

# ================================================================
# ACCESS LOGGING BUCKET
# ================================================================

resource "aws_s3_bucket" "logs" {
  # Access logs are kept in the primary region for this demo.
  # Replicating audit logs is outside the lab scope.
  #checkov:skip=CKV_AWS_144:Access logs are kept in the primary region for this demo; replicating audit logs is outside the lab scope.

  # The bucket is an audit-log destination rather than an
  # application data source, so event notifications are not
  # required for this lab.
  #checkov:skip=CKV2_AWS_62:This bucket is an S3 access-log destination; event notifications are outside the lab scope.

  bucket = "quickpayng-access-logs-${random_id.suffix.hex}"

  tags = {
    Name        = "QuickPayNG S3 Access Logs"
    Environment = "Demo"
  }
}

# ================================================================
# LOG BUCKET PUBLIC ACCESS PROTECTION
# ================================================================

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket = aws_s3_bucket.logs.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

# ================================================================
# LOG BUCKET VERSIONING
# ================================================================

resource "aws_s3_bucket_versioning" "logs" {
  bucket = aws_s3_bucket.logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

# ================================================================
# LOG BUCKET KMS ENCRYPTION
# ================================================================

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.payments.arn
      sse_algorithm     = "aws:kms"
    }

    bucket_key_enabled = true
  }
}

# ================================================================
# S3 ACCESS LOGGING
# ================================================================

resource "aws_s3_bucket_logging" "payments" {
  bucket = aws_s3_bucket.payments.id

  target_bucket = aws_s3_bucket.logs.id
  target_prefix = "payment-data-access/"
}

# ================================================================
# PRIMARY BUCKET LIFECYCLE
# ================================================================

resource "aws_s3_bucket_lifecycle_configuration" "payments" {
  bucket = aws_s3_bucket.payments.id

  rule {
    id     = "payment-data-lifecycle"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = 365
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# ================================================================
# LOG BUCKET LIFECYCLE
# ================================================================

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    id     = "access-log-lifecycle"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = 365
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# ================================================================
# PRIMARY SNS EVENT TOPIC
# ================================================================

resource "aws_sns_topic" "payment_events" {
  name              = "quickpayng-payment-events"
  kms_master_key_id = aws_kms_key.payments.arn
}

# ================================================================
# SNS TOPIC POLICY
# Allows only the primary S3 bucket to publish.
# ================================================================

resource "aws_sns_topic_policy" "allow_s3" {
  arn = aws_sns_topic.payment_events.arn

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "AllowS3Publish"
        Effect = "Allow"

        Principal = {
          Service = "s3.amazonaws.com"
        }

        Action   = "SNS:Publish"
        Resource = aws_sns_topic.payment_events.arn

        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_s3_bucket.payments.arn
          }
        }
      }
    ]
  })
}

# ================================================================
# PRIMARY S3 EVENT NOTIFICATIONS
# ================================================================

resource "aws_s3_bucket_notification" "payments" {
  bucket = aws_s3_bucket.payments.id

  topic {
    topic_arn = aws_sns_topic.payment_events.arn

    events = [
      "s3:ObjectCreated:*",
      "s3:ObjectRemoved:*"
    ]
  }

  depends_on = [
    aws_sns_topic_policy.allow_s3
  ]
}

# ================================================================
# REPLICA S3 BUCKET
# ================================================================

resource "aws_s3_bucket" "payments_replica" {
  provider = aws.replica

  bucket = "quickpayng-payment-replica-${random_id.suffix.hex}"

  tags = {
    Name        = "QuickPayNG Payment Data Replica"
    Environment = "Demo"
  }
}

# ================================================================
# REPLICA PUBLIC ACCESS PROTECTION
# ================================================================

resource "aws_s3_bucket_public_access_block" "payments_replica" {
  provider = aws.replica
  bucket   = aws_s3_bucket.payments_replica.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

# ================================================================
# REPLICA VERSIONING
# Required for S3 Cross-Region Replication.
# ================================================================

resource "aws_s3_bucket_versioning" "payments_replica" {
  provider = aws.replica
  bucket   = aws_s3_bucket.payments_replica.id

  versioning_configuration {
    status = "Enabled"
  }
}

# ================================================================
# REPLICA KMS ENCRYPTION
# ================================================================

resource "aws_s3_bucket_server_side_encryption_configuration" "payments_replica" {
  provider = aws.replica
  bucket   = aws_s3_bucket.payments_replica.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.replica.arn
      sse_algorithm     = "aws:kms"
    }

    bucket_key_enabled = true
  }
}

# ================================================================
# REPLICA LIFECYCLE
# ================================================================

resource "aws_s3_bucket_lifecycle_configuration" "payments_replica" {
  provider = aws.replica
  bucket   = aws_s3_bucket.payments_replica.id

  rule {
    id     = "replica-lifecycle"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = 365
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# ================================================================
# REPLICA LOGGING DESTINATION
# ================================================================

resource "aws_s3_bucket" "replica_logs" {
  provider = aws.replica

  # This bucket is an audit-log destination. Replicating the
  # audit-log destination itself is outside the lab scope.
  #checkov:skip=CKV_AWS_144:Replica audit logs are kept in the replica region; further replication is outside the lab scope.

  # Event notifications are not required for this dedicated
  # S3 access-log destination in this lab.
  #checkov:skip=CKV2_AWS_62:This bucket is an S3 access-log destination; event notifications are outside the lab scope.

  bucket = "quickpayng-replica-logs-${random_id.suffix.hex}"

  tags = {
    Name        = "QuickPayNG Replica Access Logs"
    Environment = "Demo"
  }
}

# ================================================================
# REPLICA LOG BUCKET PUBLIC ACCESS PROTECTION
# ================================================================

resource "aws_s3_bucket_public_access_block" "replica_logs" {
  provider = aws.replica
  bucket   = aws_s3_bucket.replica_logs.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

# ================================================================
# REPLICA LOG BUCKET VERSIONING
# ================================================================

resource "aws_s3_bucket_versioning" "replica_logs" {
  provider = aws.replica
  bucket   = aws_s3_bucket.replica_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

# ================================================================
# REPLICA LOG BUCKET KMS ENCRYPTION
# ================================================================

resource "aws_s3_bucket_server_side_encryption_configuration" "replica_logs" {
  provider = aws.replica
  bucket   = aws_s3_bucket.replica_logs.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.replica.arn
      sse_algorithm     = "aws:kms"
    }

    bucket_key_enabled = true
  }
}

# ================================================================
# REPLICA LOG BUCKET LIFECYCLE
# ================================================================

resource "aws_s3_bucket_lifecycle_configuration" "replica_logs" {
  provider = aws.replica
  bucket   = aws_s3_bucket.replica_logs.id

  rule {
    id     = "replica-access-log-lifecycle"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = 365
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# ================================================================
# REPLICA S3 ACCESS LOGGING
# ================================================================

resource "aws_s3_bucket_logging" "payments_replica" {
  provider = aws.replica

  bucket = aws_s3_bucket.payments_replica.id

  target_bucket = aws_s3_bucket.replica_logs.id
  target_prefix = "payment-replica-access/"
}

# ================================================================
# REPLICA SNS EVENT TOPIC
# ================================================================

resource "aws_sns_topic" "replica_events" {
  provider = aws.replica

  name              = "quickpayng-replica-events"
  kms_master_key_id = aws_kms_key.replica.arn
}

# ================================================================
# REPLICA SNS TOPIC POLICY
# ================================================================

resource "aws_sns_topic_policy" "replica_events" {
  provider = aws.replica
  arn      = aws_sns_topic.replica_events.arn

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "AllowS3Publish"
        Effect = "Allow"

        Principal = {
          Service = "s3.amazonaws.com"
        }

        Action   = "SNS:Publish"
        Resource = aws_sns_topic.replica_events.arn

        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_s3_bucket.payments_replica.arn
          }
        }
      }
    ]
  })
}

# ================================================================
# REPLICA S3 EVENT NOTIFICATIONS
# ================================================================

resource "aws_s3_bucket_notification" "payments_replica" {
  provider = aws.replica

  bucket = aws_s3_bucket.payments_replica.id

  topic {
    topic_arn = aws_sns_topic.replica_events.arn

    events = [
      "s3:ObjectCreated:*",
      "s3:ObjectRemoved:*"
    ]
  }

  depends_on = [
    aws_sns_topic_policy.replica_events
  ]
}

# ================================================================
# S3 REPLICATION IAM ROLE
# ================================================================

resource "aws_iam_role" "s3_replication" {
  name = "quickpayng-s3-replication-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "s3.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })
}

# ================================================================
# S3 REPLICATION IAM POLICY
# ================================================================

resource "aws_iam_role_policy" "s3_replication" {
  role = aws_iam_role.s3_replication.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket"
        ]

        Resource = aws_s3_bucket.payments.arn
      },
      {
        Effect = "Allow"

        Action = [
          "s3:GetObjectVersion",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectLegalHold",
          "s3:GetObjectRetention",
          "s3:GetObjectVersionTagging"
        ]

        Resource = "${aws_s3_bucket.payments.arn}/*"
      },
      {
        Effect = "Allow"

        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags"
        ]

        Resource = "${aws_s3_bucket.payments_replica.arn}/*"
      }
    ]
  })
}

# ================================================================
# CROSS-REGION REPLICATION
# ================================================================

resource "aws_s3_bucket_replication_configuration" "payments" {
  bucket = aws_s3_bucket.payments.id
  role   = aws_iam_role.s3_replication.arn

  depends_on = [
    aws_s3_bucket_versioning.payments,
    aws_s3_bucket_versioning.payments_replica
  ]

  rule {
    id     = "payment-data-replication"
    status = "Enabled"

    destination {
      bucket        = aws_s3_bucket.payments_replica.arn
      storage_class = "STANDARD"
    }
  }
}
