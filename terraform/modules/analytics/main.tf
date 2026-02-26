# ===========================================
# Analytics Module — Glue Catalog + Athena
# ===========================================

# Glue Catalog Database
resource "aws_glue_catalog_database" "traffic" {
  name = "traffic_analytics"

  description = "Traffic analytics database for Athena queries"
}

# Glue Catalog Table — matches Parquet schema written by Spark S3 Glacier app
resource "aws_glue_catalog_table" "traffic_stream" {
  name          = "traffic_stream"
  database_name = aws_glue_catalog_database.traffic.name

  table_type = "EXTERNAL_TABLE"

  parameters = {
    "classification"  = "parquet"
    "parquet.compress" = "SNAPPY"
    EXTERNAL           = "TRUE"
  }

  storage_descriptor {
    location      = "s3://${var.s3_bucket_name}/traffic_stream/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
      parameters = {
        "serialization.format" = "1"
      }
    }

    # Schema matching s3_glacier.py output
    columns {
      name = "timestamp_str"
      type = "string"
    }

    columns {
      name = "camera_id"
      type = "string"
    }

    columns {
      name = "latitude"
      type = "double"
    }

    columns {
      name = "longitude"
      type = "double"
    }

    columns {
      name = "camera"
      type = "string"
    }

    columns {
      name = "counts"
      type = "map<string,int>"
    }

    columns {
      name = "total_count"
      type = "int"
    }

    columns {
      name = "timestamp"
      type = "timestamp"
    }
  }

  # Partition by date_part (written by Spark's .partitionBy("date_part"))
  partition_keys {
    name = "date_part"
    type = "date"
  }
}

# Athena Workgroup
resource "aws_athena_workgroup" "primary" {
  name = "${var.project_name}-workgroup"

  configuration {
    enforce_workgroup_configuration = false

    result_configuration {
      output_location = "s3://${var.s3_bucket_name}/athena_results/"
    }
  }

  tags = {
    Name = "${var.project_name}-athena-workgroup"
  }
}
