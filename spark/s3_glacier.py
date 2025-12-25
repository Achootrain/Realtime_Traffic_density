import os
import sys
import time
from pyspark.sql import SparkSession
from pyspark.sql.functions import from_json, col, create_map, lit, to_timestamp, to_date
from pyspark.sql.types import StructType, StructField, StringType, IntegerType, DoubleType

# ==========================================
# 1. Cấu hình Spark Session
# ==========================================
spark = (
    SparkSession.builder
    .appName("TrafficAnalyticsSpark-S3Glacier")
    # Các package Kafka và AWS sẽ được load từ file YAML config
    .getOrCreate()
)

spark.sparkContext.setLogLevel("WARN")

# ==========================================
# 2. Lấy biến môi trường & Credentials
# ==========================================
print("[DEBUG] Environment Variables Keys:", list(os.environ.keys()))

def get_credentials():
    # 1. Try Environment Variables
    ak = os.environ.get("AWS_ACCESS_KEY_ID")
    sk = os.environ.get("AWS_SECRET_ACCESS_KEY")
    if ak and sk:
        return ak, sk, "Environment Variables"

    # 2. Try Volume Mount (Secrets)
    try:
        with open("/etc/secrets/aws-credentials/access_key_id", "r") as f:
            ak = f.read().strip()
        with open("/etc/secrets/aws-credentials/secret_access_key", "r") as f:
            sk = f.read().strip()
        if ak and sk:
            return ak, sk, "Volume Mount"
    except Exception as e:
        print(f"[DEBUG] Failed to read from volume: {e}")

    return None, None, None

aws_access_key, aws_secret_key, source = get_credentials()

if aws_access_key and aws_secret_key:
    # Set in Runtime Config (for tasks/executors if they pick it up via SQLConf)
    spark.conf.set("spark.hadoop.fs.s3a.access.key", aws_access_key)
    spark.conf.set("spark.hadoop.fs.s3a.secret.key", aws_secret_key)
    spark.conf.set("spark.hadoop.fs.s3a.aws.credentials.provider", "org.apache.hadoop.fs.s3a.SimpleAWSCredentialsProvider")
    
    # Set in Driver's Hadoop Config (immediate effect for Driver file operations)
    try:
        sc = spark.sparkContext
        sc._jsc.hadoopConfiguration().set("fs.s3a.access.key", aws_access_key)
        sc._jsc.hadoopConfiguration().set("fs.s3a.secret.key", aws_secret_key)
        sc._jsc.hadoopConfiguration().set("fs.s3a.aws.credentials.provider", "org.apache.hadoop.fs.s3a.SimpleAWSCredentialsProvider")
        print(f"[INFO] AWS Credentials loaded from {source} and set in Hadoop Config")
    except Exception as e:
        print(f"[WARN] Failed to set Hadoop config on Driver directly: {e}")
else:
    print("[WARN] AWS Credentials NOT FOUND! S3A will likely fail.")
kafka_bootstrap = os.environ.get("KAFKA_BOOTSTRAP_SERVERS", "kafka.traffic.svc.cluster.local:9092")
kafka_topic = os.environ.get("KAFKA_TOPIC", "traffic")
kafka_group_id = os.environ.get("KAFKA_GROUP_ID", "spark-s3-glacier-group")

# AWS Settings
bucket_name = os.environ.get("S3_BUCKET")
region = os.environ.get("AWS_REGION", "us-east-1")

if not bucket_name:
    print("[ERROR] S3_BUCKET env var is missing!")
    sys.exit(1)

print(f"[INFO] Config: Servers={kafka_bootstrap}, Topic={kafka_topic}, Bucket={bucket_name}")

# ==========================================
# 3. Định nghĩa Schema Input
# ==========================================
input_schema = StructType([
    StructField("time", StringType()),
    StructField("camera_id", StringType()),
    StructField("latitude", DoubleType()),
    StructField("longitude", DoubleType()),
    StructField("camera", StringType()),
    StructField("car_count", IntegerType()),
    StructField("bus_count", IntegerType()),
    StructField("truck_count", IntegerType()),
    StructField("motorcycle_count", IntegerType()),
    StructField("total_count", IntegerType())
])

# ==========================================
# 4. Đọc dữ liệu từ Kafka (Read Stream)
# ==========================================
df_raw = (
    spark.readStream
    .format("kafka")
    .option("kafka.bootstrap.servers", kafka_bootstrap)
    .option("subscribe", kafka_topic)
    .option("kafka.group.id", kafka_group_id)
    .option("startingOffsets", "earliest")
    .option("failOnDataLoss", "false")
    .load()
)

df_parsed = df_raw.selectExpr("CAST(value AS STRING)").select(
    from_json(col("value"), input_schema).alias("data")
).select("data.*")

# ==========================================
# 5. Biến đổi dữ liệu (Transformation)
# ==========================================
df_transformed = df_parsed.select(
    col("time").alias("timestamp_str"),
    col("camera_id"),
    col("latitude"),
    col("longitude"),
    col("camera"),
    create_map(
        lit("car"), col("car_count"),
        lit("bus"), col("bus_count"),
        lit("truck"), col("truck_count"),
        lit("motorcycle"), col("motorcycle_count")
    ).alias("counts"),
    col("total_count")
) \
.withColumn("timestamp", to_timestamp(col("timestamp_str"))) \
.withColumn("date_part", to_date(col("timestamp"))) 
# ^^^ Tạo cột date_part để chia thư mục trên S3

# ==========================================
# 6. Ghi dữ liệu lên AWS S3 (Write Stream)
# ==========================================
s3_output_path = f"s3a://{bucket_name}/traffic_stream"
s3_checkpoint_path = f"s3a://{bucket_name}/checkpoints/{kafka_group_id}"

print(f"[INFO] Writing to: {s3_output_path}")

try:
    s3_query = (
        df_transformed
        # [QUAN TRỌNG] Gom thành 1 file duy nhất mỗi batch để tiết kiệm phí request Glacier
        .coalesce(1) 
        .writeStream
        .outputMode("append")
        .format("parquet")
        # [QUAN TRỌNG] Chia thư mục theo ngày (year-month-day)
        .partitionBy("date_part") 
        .option("path", s3_output_path)
        .option("checkpointLocation", s3_checkpoint_path)
        # Trigger 5 phút/lần để file đủ lớn (~100MB nếu traffic nhiều)
        .trigger(processingTime="300 seconds")
        .start()
    )
    print(f"[SUCCESS] S3 Stream started.")
except Exception as e:
    print(f"[ERROR] Failed to start S3 stream: {e}")
    sys.exit(1)

# Console query removed for production memory optimization

# Restart loop every 12 hours (43200 seconds)
# Spark will exit after timeout, and K8s RestartPolicy=Always will respawn it.
timeout_seconds = 43200
print(f"[INFO] Application set to restart after {timeout_seconds} seconds")

# Returns True if query terminated (error/finished), False if timeout
terminated = spark.streams.awaitAnyTermination(timeout=timeout_seconds)

if not terminated:
    print("[INFO] Reached timeout. Stopping stream gracefully...")
    s3_query.stop()
    # Đợi một chút cho các thread đóng hẳn
    time.sleep(5)
    spark.stop()
    print("[INFO] Spark Session stopped. Exiting process.")
    sys.exit(0) # Thoát code 0 để K8s biết là tắt chủ động
else:
    print("[ERROR] Stream crashed or stopped unexpectedly!")
    sys.exit(1) # Thoát code 1 để K8s báo lỗi