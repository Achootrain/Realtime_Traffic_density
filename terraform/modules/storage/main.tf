# ===========================================
# Storage Module — S3 Bucket
# ===========================================

resource "aws_s3_bucket" "traffic_data" {
  bucket = var.s3_bucket_name

  tags = {
    Name = "${var.project_name}-data"
  }
}

# Block all public access
resource "aws_s3_bucket_public_access_block" "traffic_data" {
  bucket = aws_s3_bucket.traffic_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "traffic_data" {
  bucket = aws_s3_bucket.traffic_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Lifecycle — transition to Glacier after N days
resource "aws_s3_bucket_lifecycle_configuration" "traffic_data" {
  bucket = aws_s3_bucket.traffic_data.id

  rule {
    id     = "traffic-stream-to-glacier"
    status = "Enabled"

    # Only transition data partitions, NOT _spark_metadata/
    filter {
      prefix = "traffic_stream/date_part="
    }

    transition {
      days          = var.glacier_transition_days
      storage_class = "GLACIER"
    }
  }

  rule {
    id     = "athena-results-cleanup"
    status = "Enabled"

    filter {
      prefix = "athena_results/"
    }

    expiration {
      days = 7
    }
  }
}

# Versioning (optional, disabled by default to save cost)
resource "aws_s3_bucket_versioning" "traffic_data" {
  bucket = aws_s3_bucket.traffic_data.id

  versioning_configuration {
    status = "Suspended"
  }
}
