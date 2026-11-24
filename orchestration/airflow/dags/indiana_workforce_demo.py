from datetime import datetime, timedelta, timezone
import time
import logging

from airflow.sdk import dag, task


@dag(
    dag_id="indiana_workforce_demo",
    description="Workforce intelligence orchestration demonstration",
    start_date=datetime(2026, 1, 1, tzinfo=timezone.utc),
    schedule=None,
    catchup=False,
    max_active_runs=1,
    default_args={
        "owner": "workforce_architecture",
        "retries": 2,
        "retry_delay": timedelta(seconds=15),
        "execution_timeout": timedelta(minutes=5),
    },
    tags=["indiana", "workforce", "medallion", "demo"],
)
def workforce_pipeline():

    @task
    def start_pipeline():
        logging.info("Starting workforce pipeline")

    @task
    def ingest_laus():
        time.sleep(5)
        return {"source": "BLS_LAUS", "status": "SUCCESS"}

    @task
    def ingest_oews():
        time.sleep(8)
        return {"source": "BLS_OEWS", "status": "SUCCESS"}

    @task
    def ingest_idwd():
        time.sleep(6)
        return {"source": "IDWD", "status": "SUCCESS"}

    @task
    def validate_quality(laus, oews, idwd):
        results = [laus, oews, idwd]

        if not all(
            r["status"] == "SUCCESS" for r in results
        ):
            raise ValueError("Data quality validation failed")

        logging.info("All simulated sources passed validation")

        return {"approved": True}

    @task
    def publish_snapshot(validation):
        if not validation["approved"]:
            raise ValueError("Publication blocked")

        logging.info("Simulated snapshot published")

    @task
    def end_pipeline():
        logging.info("Workforce pipeline completed")

    start = start_pipeline()

    laus = ingest_laus()
    oews = ingest_oews()
    idwd = ingest_idwd()

    start >> [laus, oews, idwd]

    validation = validate_quality(laus, oews, idwd)
    publication = publish_snapshot(validation)

    publication >> end_pipeline()


workforce_pipeline()
