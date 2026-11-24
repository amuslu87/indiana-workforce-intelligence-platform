"""Local allowlisted Windows execution bridge."""

import datetime as dt
import json
import logging
import os
import re
import subprocess
import time
from pathlib import Path

ROOT = Path(r"C:\Projects\IndianaWorkforceIntelligence")
BRIDGE = ROOT / "orchestration" / "airflow" / "bridge"

REQUESTS = BRIDGE / "requests"
PROCESSING = BRIDGE / "processing"
RESULTS = BRIDGE / "results"

PYTHON = Path(r"C:\Users\amusl\anaconda3\python.exe")

# Only read-only connectivity testing is enabled initially.
ALLOWED_JOBS = {
    "connectivity_test": [
        str(PYTHON),
        "-c",
        (
            "import pyodbc; "
            "c=pyodbc.connect("
            "'DRIVER={ODBC Driver 18 for SQL Server};"
            "SERVER=Matt;"
            "DATABASE=IndianaWorkforceDW;"
            "Trusted_Connection=yes;"
            "Encrypt=yes;"
            "TrustServerCertificate=yes;', timeout=10); "
            "print(c.execute("
            "'SELECT DB_NAME(), COUNT(*) "
            "FROM serving.vw_Unemployment'"
            ").fetchone()); "
            "c.close()"
        )
    ]
}

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s"
)

log = logging.getLogger("windows_agent")


def utc_now():
    return dt.datetime.now(dt.timezone.utc).isoformat()


def write_result(job_id, result):
    target = RESULTS / f"{job_id}.json"
    temporary = RESULTS / f"{job_id}.tmp"

    temporary.write_text(
        json.dumps(result, indent=2),
        encoding="utf-8"
    )

    os.replace(temporary, target)


def process_request(request):
    job_id = request.stem

    if not re.fullmatch(r"[a-f0-9]{32}", job_id):
        log.warning("Ignoring invalid request filename")
        return

    if request.is_symlink():
        log.warning("Ignoring symbolic link")
        return

    if (RESULTS / f"{job_id}.json").exists():
        return

    claimed = PROCESSING / request.name

    if claimed.exists():
        return

    try:
        request.rename(claimed)
    except OSError:
        return

    result = {
        "job_id": job_id,
        "started_utc": utc_now(),
        "status": "FAILED"
    }

    try:
        if claimed.stat().st_size > 4096:
            raise ValueError("Request exceeds size limit")

        payload = json.loads(
            claimed.read_text(encoding="utf-8")
        )

        if not isinstance(payload, dict):
            raise ValueError("Invalid request format")

        if set(payload) != {"job_id", "job_type"}:
            raise ValueError("Unexpected request fields")

        if payload["job_id"] != job_id:
            raise ValueError("Job identifier mismatch")

        job_type = payload["job_type"]

        if not isinstance(job_type, str):
            raise ValueError("Invalid job type")

        if job_type not in ALLOWED_JOBS:
            raise ValueError("Job type is not authorized")

        result["job_type"] = job_type

        log.info("Executing %s: %s", job_type, job_id)

        execution = subprocess.run(
            ALLOWED_JOBS[job_type],
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=60,
            shell=False
        )

        result["exit_code"] = execution.returncode
        result["stdout"] = execution.stdout[-2000:]
        result["stderr"] = execution.stderr[-2000:]

        if execution.returncode == 0:
            result["status"] = "SUCCESS"

    except Exception as exc:
        result["error"] = str(exc)

    result["ended_utc"] = utc_now()

    write_result(job_id, result)
    claimed.unlink()

    log.info("Job %s: %s", job_id, result["status"])


def main():
    for directory in (REQUESTS, PROCESSING, RESULTS):
        directory.mkdir(parents=True, exist_ok=True)

    log.info("Windows execution agent started")
    log.info("Allowed jobs: %s", list(ALLOWED_JOBS))
    log.info("Waiting for requests. Press Ctrl+C to stop.")

    while True:
        for request in sorted(REQUESTS.glob("*.json")):
            process_request(request)

        time.sleep(2)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        log.info("Execution agent stopped")
