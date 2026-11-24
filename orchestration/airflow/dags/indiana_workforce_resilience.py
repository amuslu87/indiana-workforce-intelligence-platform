from datetime import datetime, timedelta, timezone
import logging
import time

from airflow.sdk import dag, task, Param, get_current_context


@dag(
    dag_id="indiana_workforce_resilience",
    description="Test retries, quality gates and failure isolation",
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
    params={
        "scenario": Param(
            "normal",
            type="string",
            enum=[
                "normal",
                "transient_failure",
                "quality_failure"
            ]
        )
    },
    tags=["indiana", "resilience", "governance", "test"],
)
def resilience_pipeline():

    @task
    def start_pipeline():
        context = get_current_context()
        scenario = context["params"]["scenario"]
        logging.info("Scenario: %s", scenario)
        return scenario

    @task
    def ingest_laus(scenario):
        context = get_current_context()
        attempt = context["ti"].try_number

        logging.info("LAUS ingestion attempt: %s", attempt)

        if scenario == "transient_failure" and attempt == 1:
            raise ConnectionError(
                "Simulated temporary API connection failure"
            )

        time.sleep(3)

        return {
            "source": "BLS_LAUS",
            "rows": 132,
            "rejected": 0
        }

    @task
    def ingest_oews(scenario):
        time.sleep(5)

        return {
            "source": "BLS_OEWS",
            "rows": 784,
            "rejected": 10 if scenario == "quality_failure" else 0
        }

    @task
    def ingest_idwd(scenario):
        time.sleep(4)

        return {
            "source": "IDWD",
            "rows": 893,
            "rejected": 0
        }

    @task(retries=0)
    def validate_quality(laus, oews, idwd):
        results = [laus, oews, idwd]

        received = sum(r["rows"] for r in results)
        rejected = sum(r["rejected"] for r in results)

        logging.info("Rows received: %s", received)
        logging.info("Rows rejected: %s", rejected)

        if rejected > 0:
            raise ValueError(
                f"Blocking quality failure: {rejected} rejected records"
            )

        return {
            "approved": True,
            "accepted": received
        }

    @task
    def publish_snapshot(validation):
        if not validation["approved"]:
            raise ValueError("Publication blocked")

        logging.info(
            "SIMULATION: Published %s validated records",
            validation["accepted"]
        )

    @task
    def end_pipeline():
        logging.info("Pipeline completed successfully")

    scenario = start_pipeline()

    laus = ingest_laus(scenario)
    oews = ingest_oews(scenario)
    idwd = ingest_idwd(scenario)

    validation = validate_quality(laus, oews, idwd)
    publication = publish_snapshot(validation)

    publication >> end_pipeline()


resilience_pipeline()
