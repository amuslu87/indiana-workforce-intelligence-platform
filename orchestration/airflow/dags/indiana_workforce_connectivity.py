from datetime import datetime, timedelta, timezone
from pathlib import Path
import json
import logging
import os
import time
import uuid

from airflow.sdk import dag, task

BRIDGE = Path("/opt/airflow/bridge")


@dag(
    dag_id="indiana_workforce_connectivity",
    description="Validate secure Windows execution bridge",
    start_date=datetime(2026, 1, 1, tzinfo=timezone.utc),
    schedule=None,
    catchup=False,
    max_active_runs=1,
    default_args={
        "owner": "workforce_architecture",
        "retries": 0,
        "execution_timeout": timedelta(minutes=3)
    },
    tags=["indiana", "integration", "security"]
)
def connectivity_pipeline():

    @task
    def submit_request():
        job_id = uuid.uuid4().hex

        payload = {
            "job_id": job_id,
            "job_type": "connectivity_test"
        }

        requests = BRIDGE / "requests"

        temporary = requests / f"{job_id}.tmp"
        target = requests / f"{job_id}.json"

        temporary.write_text(
            json.dumps(payload),
            encoding="utf-8"
        )

        os.replace(temporary, target)

        logging.info("Submitted job: %s", job_id)

        return job_id

    @task
    def await_result(job_id):
        result_file = BRIDGE / "results" / f"{job_id}.json"

        deadline = time.monotonic() + 120

        while time.monotonic() < deadline:
            if result_file.exists():
                result = json.loads(
                    result_file.read_text(encoding="utf-8")
                )

                if result.get("job_id") != job_id:
                    raise RuntimeError("Result identifier mismatch")

                if result.get("status") != "SUCCESS":
                    raise RuntimeError(
                        f"Windows job failed: {result}"
                    )

                logging.info(
                    "Windows SQL result: %s",
                    result.get("stdout")
                )

                return result

            time.sleep(2)

        raise TimeoutError("Windows execution agent did not respond")

    @task
    def verify_connectivity(result):
        logging.info(
            "Secure connectivity verified: %s",
            result["stdout"]
        )

    verify_connectivity(await_result(submit_request()))


connectivity_pipeline()
