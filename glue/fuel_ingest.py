import sys
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql.functions import current_timestamp, input_file_name

args = getResolvedOptions(sys.argv, ["JOB_NAME", "bucket", "raw_prefix", "curated_prefix"])

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args["JOB_NAME"], args)

bucket = args["bucket"]
raw_prefix = args["raw_prefix"].rstrip("/") + "/"
curated_prefix = args["curated_prefix"].rstrip("/") + "/"

raw_path = f"s3://{bucket}/{raw_prefix}"
curated_path = f"s3://{bucket}/{curated_prefix}"


df = spark.read.json(raw_path)


df2 = (
    df.withColumn("_ingested_at", current_timestamp())
      .withColumn("_source_file", input_file_name())
)


(df2.write
    .mode("append")
    .format("parquet")
    .save(curated_path))

job.commit()
