import sys
import re
import boto3
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.utils import getResolvedOptions
from awsglue.job import Job
from pyspark.sql.functions import input_file_name, regexp_extract

args = getResolvedOptions(sys.argv, [
    'JOB_NAME', 'bucket', 'raw_prefix', 'curated_prefix', 'sns_topic_arn'
])

bucket = args['bucket']
raw_prefix = args['raw_prefix']
curated_prefix = args['curated_prefix']
sns_topic_arn = args.get('sns_topic_arn', '')

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

raw_path = f"s3://{bucket}/{raw_prefix}"
curated_path = f"s3://{bucket}/{curated_prefix}"


df = (spark.read
      .option("recursiveFileLookup", "true")
      .json(raw_path))


df = df.withColumn(
    "ingestion_date",
    regexp_extract(input_file_name(), r"ingestion_date=([0-9]{4}-[0-9]{2}-[0-9]{2})", 1)
)


(df.write
   .mode("overwrite")
   .partitionBy("ingestion_date")
   .parquet(curated_path))


if sns_topic_arn:
    boto3.client("sns").publish(
        TopicArn=sns_topic_arn,
        Subject="Fuel pipeline curated updated",
        Message=f"CURATED written to: {curated_path}"
    )

job.commit()
