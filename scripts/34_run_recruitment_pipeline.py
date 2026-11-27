import sys
import subprocess
import logging
import pyodbc
from zoneinfo import ZoneInfo
from pathlib import Path
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]
ETL = ROOT / "scripts/etl"
RAW = ROOT / "data/raw/state_careers"
LOGS = ROOT / "logs"
LOCK = LOGS / "recruitment_pipeline.lock"

LOGS.mkdir(exist_ok=True)
stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    handlers=[
        logging.FileHandler(
            LOGS / f"recruitment_{stamp}.log",
            encoding="utf-8"
        ),
        logging.StreamHandler()
    ]
)

def run(script, *args):
    logging.info("Starting %s", script)

    result = subprocess.run(
        [sys.executable, "-u", str(ETL / script), *args],
        cwd=ROOT,
        capture_output=True,
        text=True,
        errors="replace",
        timeout=7200
    )

    logging.info(result.stdout)

    if result.stderr:
        logging.warning(result.stderr)

    result.check_returncode()

def standardize_compensation():
    run("standardize_recruitment_salary.py", "--commit")

    sql_script = (
        ROOT / "database/scripts/"
        "42_integrate_standardized_compensation.sql"
    )

    logging.info("Synchronizing Silver and Gold compensation")

    result = subprocess.run(
        [
            "sqlcmd",
            "-S", "Matt",
            "-d", "IndianaWorkforceDW",
            "-E", "-C", "-b", "-I", "-W",
            "-i", str(sql_script)
        ],
        cwd=ROOT,
        capture_output=True,
        text=True,
        errors="replace",
        timeout=600
    )

    logging.info(result.stdout)

    if result.stderr:
        logging.warning(result.stderr)

    result.check_returncode()

    if "SILVER-GOLD COMPENSATION INTEGRATION: PASS" not in result.stdout:
        raise RuntimeError("Compensation reconciliation not confirmed")

    logging.info("COMPENSATION STANDARDIZATION PASSED")


def main():
    try:
        LOCK.mkdir()
    except FileExistsError:
        logging.error("Pipeline locked; execution blocked.")
        return 1

    try:
        if "--check" in sys.argv:
            for name in (
                "compensation_parser.py",
                "standardize_recruitment_salary.py",
                "collect_state_careers_daily.py",
                "load_state_careers_lifecycle.py",
                "export_recruitment_archive.py",
                "sync_recruitment_archive.py"
            ):
                p = ETL / name
                compile(p.read_text(encoding="utf-8-sig"),
                        str(p), "exec")
                logging.info("Script validation PASS: %s", name)

            logging.info("PREFLIGHT PASSED")
            return 0

        today = datetime.now(
            ZoneInfo("America/Indiana/Indianapolis")
        ).date()

        cn = pyodbc.connect(
            "DRIVER={ODBC Driver 18 for SQL Server};"
            "SERVER=Matt;DATABASE=IndianaWorkforceDW;"
            "Trusted_Connection=yes;Encrypt=yes;"
            "TrustServerCertificate=yes;"
        )

        try:
            existing = cn.cursor().execute("""
                SELECT COUNT(*)
                FROM gold.Fact_RecruitmentDaily d
                JOIN bronze.StateCareers_Collection c
                  ON d.CollectionID = c.CollectionID
                WHERE d.ObservationDate = ?
                  AND c.IsListingComplete = 1
                  AND c.CollectionStatus = 'SUCCEEDED'
            """, today).fetchone()[0]
        finally:
            cn.close()

        if existing:
            logging.info(
                "Daily observation already exists: %s", today
            )
            standardize_compensation()
            run("export_recruitment_archive.py")
            run("sync_recruitment_archive.py")
            logging.info("SAME-DAY PROTECTION PASSED")
            return 0

        before = set(RAW.glob("daily_*"))

        run("collect_state_careers_daily.py")

        created = set(RAW.glob("daily_*")) - before

        if len(created) != 1:
            raise RuntimeError("Unexpected collection count")

        folder = created.pop()

        if not (folder / "manifest.json").is_file():
            raise RuntimeError("Collection manifest missing")

        key = folder.name.removeprefix("daily_")

        run("load_state_careers_lifecycle.py",
            "--collection", key, "--commit")

        standardize_compensation()

        run("export_recruitment_archive.py")
        run("sync_recruitment_archive.py")

        logging.info("RECRUITMENT PIPELINE SUCCESS")
        return 0

    except Exception:
        logging.exception("RECRUITMENT PIPELINE FAILED")
        return 1

    finally:
        LOCK.rmdir()

if __name__ == "__main__":
    raise SystemExit(main())
