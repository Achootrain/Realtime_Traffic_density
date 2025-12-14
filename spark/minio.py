import os
import sys
from pyspark.sql import SparkSession
from pyspark.sql.functions import from_json, col, create_map, lit
from pyspark.sql.types import StructType, StructField, StringType, IntegerType, DoubleType

# ==========================================
# 1. Cấu hình Spark Session & Hadoop S3A
# ==========================================
spark = (
    SparkSession.builder
    .appName("TrafficAnalyticsSpark")
    .getOrCreate()
)

spark.sparkContext.setLogLevel("WARN")

def load_s3_config(sc):
    """
    Cấu hình hệ thống file Hadoop để kết nối với MinIO nội bộ Kubernetes
    """
    conf = sc._jsc.hadoopConfiguration()
    conf.set("fs.s3a.access.key", "minioadmin")
    conf.set("fs.s3a.secret.key", "minioadmin")
    conf.set("fs.s3a.path.style.access", "true")
    conf.set("fs.s3a.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem")
    # Địa chỉ Service nội bộ của MinIO trong namespace hugedata
    conf.set("fs.s3a.endpoint", "http://minio.hugedata.svc.cluster.local:9000")
    conf.set("fs.s3a.connection.ssl.enabled", "false")
    
    # Tối ưu hóa commit cho S3 (giúp ghi file nhanh hơn)
    conf.set("fs.s3a.committer.name", "directory")
    conf.set("fs.s3a.committer.staging.conflict-mode", "append")

# Load cấu hình
load_s3_config(spark.sparkContext)

# ==========================================
# 2. Lấy biến môi trường (Environment Variables)
# ==========================================
kafka_bootstrap = os.environ.get("KAFKA_BOOTSTRAP_SERVERS", "kafka.hugedata.svc.cluster.local:9092")
kafka_topic = os.environ.get("KAFKA_TOPIC", "traffic")
kafka_group_id = os.environ.get("KAFKA_GROUP_ID", "spark-traffic-group")
bucket_name = os.environ.get("MINIO_BUCKET", "traffic-data")

print(f"[INFO] Config: Servers={kafka_bootstrap}, Topic={kafka_topic}, Group={kafka_group_id}, Bucket={bucket_name}")

# ==========================================
# 3. Định nghĩa Schema (Khớp với Producer)
# ==========================================
# Producer gửi JSON dạng phẳng (Flat JSON), không lồng ghép
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
    .option("kafka.group.id", kafka_group_id)  # Quan trọng cho Scaling
    .option("startingOffsets", "earliest")     # Đọc từ đầu nếu là group mới
    .option("failOnDataLoss", "false")
    .load()
)

# Parse JSON từ binary value
df_parsed = df_raw.selectExpr("CAST(value AS STRING)").select(
    from_json(col("value"), input_schema).alias("data")
).select("data.*")

# ==========================================
# 5. Biến đổi dữ liệu (Transformation)
# ==========================================
# Gom các cột đếm riêng lẻ thành một cột Map để cấu trúc gọn gàng hơn khi lưu trữ
df_transformed = df_parsed.select(
    col("time").alias("timestamp"),  # Đổi tên cho chuẩn
    col("camera_id"),
    col("latitude"),
    col("longitude"),
    col("camera"),
    # Tạo cột 'counts' dạng Map<String, Integer>
    create_map(
        lit("car"), col("car_count"),
        lit("bus"), col("bus_count"),
        lit("truck"), col("truck_count"),
        lit("motorcycle"), col("motorcycle_count")
    ).alias("counts"),
    col("total_count")
)

# ==========================================
# 6. Ghi dữ liệu (Write Stream)
# ==========================================

# Đường dẫn S3 output
s3_output_path = f"s3a://{bucket_name}/traffic_stream"
# Checkpoint phải riêng biệt cho từng Group ID để tránh xung đột offset
s3_checkpoint_path = f"s3a://{bucket_name}/checkpoints/{kafka_group_id}/traffic_stream"

print("[INFO] Starting Write Streams...")

# Query 1: Ghi xuống MinIO (Parquet)
# Sử dụng cơ chế try-except để fallback nếu MinIO chưa sẵn sàng (Logic yêu cầu của bài toán)
try:
    s3_query = (
        df_transformed.writeStream
        .outputMode("append")
        .format("parquet")
        .option("path", s3_output_path)
        .option("checkpointLocation", s3_checkpoint_path)
        .trigger(processingTime="10 seconds")
        .start()
    )
    print(f"[SUCCESS] S3 Stream started at {s3_output_path}")
except Exception as e:
    print(f"[ERROR] Failed to start S3 stream: {e}")
    print("[WARN] Fallback to Local Container Filesystem...")
    
    local_path = "/tmp/spark-data/traffic_stream"
    local_checkpoint = f"/tmp/spark-data/checkpoints/{kafka_group_id}"
    
    s3_query = (
        df_transformed.writeStream
        .outputMode("append")
        .format("parquet")
        .option("path", local_path)
        .option("checkpointLocation", local_checkpoint)
        .trigger(processingTime="10 seconds")
        .start()
    )
    print(f"[INFO] Fallback Stream started at {local_path}")

# Query 2: In ra Console để debug (Giúp xem logs qua lệnh kubectl logs)
console_query = (
    df_transformed.writeStream
    .format("console")
    .option("truncate", "false")
    .trigger(processingTime="5 seconds")
    .start()
)

# Chờ chương trình chạy liên tục
spark.streams.awaitAnyTermination()