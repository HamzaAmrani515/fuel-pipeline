import os
import json
import uuid
import datetime
import urllib.request

import boto3

s3 = boto3.client("s3")
glue = boto3.client("glue")


def lambda_handler(event, context):
    bucket = os.environ["BUCKET"]
    job_name = os.environ["GLUE_JOB_NAME"]
    source_url = os.environ["SOURCE_API_URL"]
    raw_prefix = os.environ.get("RAW_PREFIX", "raw/fuel/")


    with urllib.request.urlopen(source_url, timeout=20) as resp:
        payload = resp.read().decode("utf-8")

    data = json.loads(payload)


    records = data.get("results", data)


    now = datetime.datetime.utcnow()
    ds = now.strftime("%Y-%m-%d")
    ts = now.strftime("%H%M%S")
    key = f"{raw_prefix}ingestion_date={ds}/{ts}_{uuid.uuid4().hex}.json"

    body = "\n".join(json.dumps(r, ensure_ascii=False) for r in records)
    s3.put_object(Bucket=bucket, Key=key, Body=body.encode("utf-8"))

    # 3) Lancer le Glue Job
    glue.start_job_run(
        JobName=job_name,
        Arguments={
            "--bucket": bucket,
            "--raw_prefix": raw_prefix,
            "--curated_prefix": "curated/fuel/",
        },
    )

    return {"status": "OK", "s3_raw_key": key, "glue_job": job_name}
