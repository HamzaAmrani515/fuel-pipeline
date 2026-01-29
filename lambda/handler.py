import os
import json
import boto3
import urllib.request
from datetime import datetime, timezone

s3 = boto3.client("s3")
glue = boto3.client("glue")

def _utc_run_id() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")

def handler(event, context):
    bucket = os.environ["BUCKET"]
    glue_job_name = os.environ["GLUE_JOB_NAME"]
    source_api_url = os.environ["SOURCE_API_URL"]

    run_id = _utc_run_id()

    # 1) Fetch API (JSON)
    req = urllib.request.Request(
        source_api_url,
        headers={"User-Agent": "fuel-pipeline/1.0"}
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        payload = resp.read().decode("utf-8")

    data = json.loads(payload)
    results = data.get("results", [])
    if not results:
        raise Exception("API returned 0 results. Check SOURCE_API_URL / where / limit.")

    # 2) Write RAW to S3
    raw_key = f"raw/run_id={run_id}/fuel_raw_{run_id}.json"
    s3.put_object(
        Bucket=bucket,
        Key=raw_key,
        Body=payload.encode("utf-8"),
        ContentType="application/json"
    )

    # 3) Start Glue Job (transform RAW -> CURATED)
    input_path = f"s3://{bucket}/{raw_key}"
    output_path = f"s3://{bucket}/curated/run_id={run_id}/"

    glue_resp = glue.start_job_run(
        JobName=glue_job_name,
        Arguments={
            "--INPUT_PATH": input_path,
            "--OUTPUT_PATH": output_path,
            "--RUN_ID": run_id
        }
    )

    return {
        "statusCode": 200,
        "run_id": run_id,
        "raw_s3_path": input_path,
        "curated_s3_path": output_path,
        "glue_job_run_id": glue_resp.get("JobRunId")
    }
