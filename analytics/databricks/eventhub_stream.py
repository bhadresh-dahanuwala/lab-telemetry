# Databricks notebook source
# MAGIC %md
# MAGIC # Event Hubs to Databricks (Structured Streaming)
# MAGIC This notebook connects to Azure Event Hubs using its Kafka-compatible endpoint, streams the raw JSON payloads, parses them, and can write them into a Delta Lake table.

# COMMAND ----------

from pyspark.sql.functions import col, from_json
from pyspark.sql.types import StructType, StructField, StringType, DoubleType

# ==========================================
# 1. Configuration
# ==========================================
import os

# IMPORTANT: Replace these with your actual names from the Azure Portal
EVENT_HUB_NAMESPACE = "evhns-dev-ozjr7qenbbjhm"
EVENT_HUB_NAME = "telemetry-events"
STORAGE_ACCOUNT_NAME = "dlsdevozjr7qenbbjhm" 
CONTAINER_NAME = "telemetry-bronze"

# Read secrets securely from Cluster Environment Variables
# (Configure these in your Databricks Cluster -> Advanced Options -> Environment Variables)
CONNECTION_STRING = os.environ.get("EVENT_HUB_CONN_STR", "")
STORAGE_ACCOUNT_KEY = os.environ.get("STORAGE_ACCOUNT_KEY", "")

if not CONNECTION_STRING or not STORAGE_ACCOUNT_KEY:
    raise ValueError("Missing secrets! Please add EVENT_HUB_CONN_STR and STORAGE_ACCOUNT_KEY to your cluster environment variables.")

# Configure Spark to authenticate with ADLS Gen2
spark.conf.set(f"fs.azure.account.key.{STORAGE_ACCOUNT_NAME}.dfs.core.windows.net", STORAGE_ACCOUNT_KEY)

# Kafka SASL configuration string
EH_SASL = f'kafkashaded.org.apache.kafka.common.security.plain.PlainLoginModule required username="$ConnectionString" password="{CONNECTION_STRING}";'

# COMMAND ----------

# ==========================================
# 2. Read Stream from Event Hub
# ==========================================
kafka_options = {
  "kafka.bootstrap.servers": f"{EVENT_HUB_NAMESPACE}.servicebus.windows.net:9093",
  "subscribe": EVENT_HUB_NAME,
  "kafka.sasl.mechanism": "PLAIN",
  "kafka.security.protocol": "SASL_SSL",
  "kafka.sasl.jaas.config": EH_SASL,
  "kafka.request.timeout.ms": "60000",
  "kafka.session.timeout.ms": "30000",
  "startingOffsets": "earliest" # Read from the beginning of the stream
}

# Connect to the stream
raw_stream_df = spark.readStream \
  .format("kafka") \
  .options(**kafka_options) \
  .load()

# COMMAND ----------

# ==========================================
# 3. Parse the JSON Payload
# ==========================================
# Event Hubs sends the payload in the "value" column as binary.
# We must cast it to a string, then apply a schema to extract the fields.

json_schema = StructType([
    StructField("device_id", StringType(), True),
    StructField("temperature", DoubleType(), True)
])

parsed_stream_df = raw_stream_df \
  .withColumn("body_string", col("value").cast("string")) \
  .withColumn("data", from_json(col("body_string"), json_schema)) \
  .select(
      col("data.device_id").alias("device_id"),
      col("data.temperature").alias("temperature"),
      col("timestamp").alias("event_enqueued_utc")
  )

# COMMAND ----------

# ==========================================
# 4. View or Save the Stream
# ==========================================
# The "Right Way": Store checkpoints safely in your Azure Data Lake!
checkpoint_path = f"abfss://{CONTAINER_NAME}@{STORAGE_ACCOUNT_NAME}.dfs.core.windows.net/checkpoints/telemetry_display"

display(parsed_stream_df, checkpointLocation=checkpoint_path)

# To save the stream permanently as a Delta Table, uncomment this block:
# parsed_stream_df.writeStream \
#   .format("delta") \
#   .outputMode("append") \
#   .option("checkpointLocation", f"abfss://{CONTAINER_NAME}@{STORAGE_ACCOUNT_NAME}.dfs.core.windows.net/checkpoints/telemetry_silver") \
#   .table("telemetry_silver")
