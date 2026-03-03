# ===========================================
# IAM Module — Service User for K8s Workloads
# ===========================================
# This user is used by Spark, Grafana, and other
# K8s apps for S3/Athena/Glue access.
#
# NOTE: Terraform and SSM deploy commands run under
# the admin user, NOT this service user.
# ===========================================

resource "aws_iam_user" "service" {
  name = "${var.project_name}-service"
  path = "/system/"

  tags = {
    Name = "${var.project_name}-service-user"
  }
}

resource "aws_iam_access_key" "service" {
  user = aws_iam_user.service.name
}

resource "aws_iam_user_policy" "service" {
  name = "${var.project_name}-service-policy"
  user = aws_iam_user.service.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3DataAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:AbortMultipartUpload",
          "s3:ListMultipartUploadParts",
        ]
        Resource = [
          "arn:aws:s3:::${var.s3_bucket_name}",
          "arn:aws:s3:::${var.s3_bucket_name}/*",
        ]
      },
      {
        Sid    = "AthenaAccess"
        Effect = "Allow"
        Action = [
          "athena:StartQueryExecution",
          "athena:StopQueryExecution",
          "athena:GetQueryExecution",
          "athena:GetQueryResults",
          "athena:GetWorkGroup",
          "athena:ListWorkGroups",
        ]
        Resource = "*"
      },
      {
        Sid    = "GlueAccess"
        Effect = "Allow"
        Action = [
          "glue:GetDatabase",
          "glue:GetDatabases",
          "glue:GetTable",
          "glue:GetTables",
          "glue:GetPartition",
          "glue:GetPartitions",
          "glue:BatchGetPartition",
          "glue:CreatePartition",
          "glue:BatchCreatePartition",
        ]
        Resource = "*"
      },
    ]
  })
}
