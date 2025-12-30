import os
import time
import logging
import psycopg2
from psycopg2.extras import execute_values
from pyspark.sql import SparkSession
from pyspark.sql.functions import from_json, col, current_timestamp
from pyspark.sql.types import StructType, StructField, StringType, IntegerType, DoubleType

# -----------------------------------------------------------
# Spark session setup
# -----------------------------------------------------------
spark = (
    SparkSession.builder
    .appName("KafkaTrafficRealtimeApp")
    # Tối ưu hóa cho Structured Streaming
    .config("spark.sql.shuffle.partitions", "4")  # Giảm partition vì dữ liệu nhỏ
    .config("spark.streaming.stopGracefullyOnShutdown", "true")
    .getOrCreate()
)

spark.sparkContext.setLogLevel("WARN")

# ---------------------------------
# Logging setup
# ---------------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
logger = logging.getLogger("realtime_app")

# ---------------------------------
# Configuration
# ---------------------------------
KAFKA_BOOTSTRAP = os.environ.get("KAFKA_BOOTSTRAP_SERVERS", "kafka:9092")
KAFKA_TOPIC = os.environ.get("KAFKA_TOPIC", "traffic")
KAFKA_GROUP_ID = os.environ.get("KAFKA_GROUP_ID", "spark-realtime-group")
KAFKA_STARTING_OFFSETS = os.environ.get("KAFKA_STARTING_OFFSETS", "earliest")

TRIGGER_TIMESCALE = os.environ.get("TRIGGER_TIMESCALE", "10 seconds")

CHECKPOINT_BASE = os.environ.get("CHECKPOINT_BASE", "/app/data/checkpoint")
CHECKPOINT_TIMESCALE = os.path.join(CHECKPOINT_BASE, "traffic_timescaledb")

# TimescaleDB / Postgres Config
DB_HOST = os.environ.get("DB_HOST", "timescaledb.traffic.svc.cluster.local")
DB_PORT = os.environ.get("DB_PORT", "5432")
DB_NAME = os.environ.get("DB_NAME", "traffic")
DB_USER = os.environ.get("TIMESCALEDB_USER", "postgres")
DB_PASS = os.environ.get("TIMESCALEDB_PASSWORD", "postgres")
DB_TABLE = os.environ.get("TIMESCALEDB_TABLE", "traffic_metrics")

# ---------------------------------
# Schema Definition
# ---------------------------------
schema = StructType([
    StructField("time", StringType()),
    StructField("camera_id", StringType()),
    StructField("latitude", DoubleType()),
    StructField("longitude", DoubleType()),
    StructField("camera", StringType()),
    StructField("car_count", IntegerType()),
    StructField("bus_count", IntegerType()),
    StructField("truck_count", IntegerType()),
    StructField("motorcycle_count", IntegerType()),
    StructField("total_count", IntegerType()),
])

# ---------------------------------
# Read Stream from Kafka
# ---------------------------------
df = (
    spark.readStream
    .format("kafka")
    .option("kafka.bootstrap.servers", KAFKA_BOOTSTRAP)
    .option("subscribe", KAFKA_TOPIC)
    .option("kafka.group.id", KAFKA_GROUP_ID)
    .option("startingOffsets", KAFKA_STARTING_OFFSETS)
    .option("failOnDataLoss", "false")
    .option("maxOffsetsPerTrigger", 1000)  # Giới hạn số msg để tránh OOM
    .load()
)

# Parse JSON
df_parsed = (
    df.selectExpr("CAST(value AS STRING)")
    .select(from_json(col("value"), schema).alias("data"))
    .select("data.*")
    .where(col("camera_id").isNotNull())  # Lọc rác
)

# ---------------------------------
# Transform Data
# ---------------------------------
df_timescale = (
    df_parsed
    .withColumn("is_valid",
                (col("car_count") >= 0) & (col("bus_count") >= 0) &
                (col("truck_count") >= 0) & (col("motorcycle_count") >= 0))
    .filter(col("is_valid"))
    .select(
        col("time").cast("timestamp").alias("time"),
        col("camera_id"),
        col("camera").alias("camera_name"),
        col("latitude"),
        col("longitude"),
        col("car_count"),
        col("motorcycle_count"),
        col("bus_count"),
        col("truck_count"),
        col("total_count"),
        current_timestamp().alias("ingest_ts")
    )
)

# ---------------------------------
# Writers Logic (Using psycopg2 for Upsert)
# ---------------------------------
def write_to_timescaledb_upsert(batch_df, batch_id):
    """
    Writes batch to TimescaleDB using INSERT ON CONFLICT DO NOTHING.
    This prevents duplicate key errors and ensures consistency.
    """
    if batch_df.isEmpty():
        return

    # Cache data to prevent re-evaluation
    batch_df.persist()
    
    try:
        # 1. Deduplicate inside the batch (Spark side)
        deduped_df = batch_df.dropDuplicates(["time", "camera_id"])
        
        # 2. Convert to list of tuples for psycopg2
        rows = deduped_df.collect()
        if not rows:
            return

        # Prepare data structure for execute_values
        data_values = [
            (
                row.time, row.camera_id, row.camera_name, row.latitude, row.longitude,
                row.car_count, row.motorcycle_count, row.bus_count, row.truck_count,
                row.total_count, row.ingest_ts
            ) 
            for row in rows
        ]

        # 3. Connect and Execute Upsert
        conn = None
        try:
            conn = psycopg2.connect(
                host=DB_HOST,
                database=DB_NAME,
                user=DB_USER,
                password=DB_PASS,
                port=DB_PORT
            )
            cur = conn.cursor()

            query = f"""
                INSERT INTO {DB_TABLE} (
                    time, camera_id, camera_name, latitude, longitude,
                    car_count, motorcycle_count, bus_count, truck_count, 
                    total_count, ingest_ts
                ) VALUES %s
                ON CONFLICT (time, camera_id) DO NOTHING;
            """
            
            # Fast bulk insert
            execute_values(cur, query, data_values)
            conn.commit()
            
            logger.info(f"Batch {batch_id}: Upserted {len(data_values)} rows successfully.")

        except Exception as db_err:
            logger.error(f"Batch {batch_id}: DB Error: {db_err}")
            if conn: conn.rollback()
            # CRITICAL: Raise error to let Spark retry the batch
            raise db_err
        finally:
            if conn: conn.close()

    except Exception as e:
        logger.error(f"Batch {batch_id}: General Error: {e}")
        raise e
    finally:
        batch_df.unpersist()

# ---------------------------------
# Start Streaming
# ---------------------------------
try:
    timescale_query = (
        df_timescale.writeStream
        .outputMode("append")
        .queryName("timescale_sink")
        .foreachBatch(write_to_timescaledb_upsert)
        .option("checkpointLocation", CHECKPOINT_TIMESCALE)
        .trigger(processingTime=TRIGGER_TIMESCALE)
        .start()
    )
    logger.info("TimescaleDB (Upsert) stream started...")
    
    spark.streams.awaitAnyTermination()

except KeyboardInterrupt:
    logger.info("Stopping streams...")
    spark.stop()
except Exception as e:
    logger.critical(f"Main loop crashed: {e}")
    sys.exit(1)