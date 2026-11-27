import csv
import json
import hashlib
import argparse
from pathlib import Path
from datetime import datetime, timezone
from zoneinfo import ZoneInfo
import pyodbc

ROOT = Path(__file__).resolve().parents[2]

CONN = (
    "DRIVER={ODBC Driver 18 for SQL Server};"
    "SERVER=Matt;DATABASE=IndianaWorkforceDW;"
    "Trusted_Connection=yes;Encrypt=yes;"
    "TrustServerCertificate=yes;"
)

def utc(value):
    return datetime.fromisoformat(value).astimezone(
        timezone.utc
    ).replace(tzinfo=None)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--collection", required=True)
    parser.add_argument("--commit", action="store_true")
    args = parser.parse_args()

    folder = ROOT / "data/raw/state_careers" / (
        "daily_" + args.collection
    )

    m = json.loads(
        (folder / "manifest.json").read_text(encoding="utf-8")
    )

    with (folder / "listings.csv").open(
        encoding="utf-8-sig"
    ) as f:
        rows = list(csv.DictReader(f))

    details = {
        d["SourcePostingID"]: d
        for d in (
            json.loads(line)
            for line in (folder / "details.jsonl").read_text(
                encoding="utf-8"
            ).splitlines() if line.strip()
        )
    }

    ids = {r["SourcePostingID"] for r in rows}
    assert m["collection_key"] == args.collection
    assert m["listing_complete"] is True
    assert m["stop"] is None
    assert len(ids) == len(rows) == m["reported"] == m["retrieved"]
    assert set(m["plan"]) == ids
    assert set(details).issubset(ids)

    start = utc(m["started_utc"])
    end = utc(m["completed_utc"])
    day = datetime.fromisoformat(
        m["started_utc"]
    ).astimezone(
        ZoneInfo("America/Indiana/Indianapolis")
    ).date()

    cn = pyodbc.connect(CONN, autocommit=False)
    c = cn.cursor()

    try:
        c.execute("""
        SET XACT_ABORT ON;
        SET QUOTED_IDENTIFIER ON;
        SET ANSI_NULLS ON;
        SET ANSI_PADDING ON;
        SET ANSI_WARNINGS ON;
        SET CONCAT_NULL_YIELDS_NULL ON;
        SET ARITHABORT ON;
        SET NUMERIC_ROUNDABORT OFF;
        SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
        """)

        duplicate = c.execute("""
        SELECT CollectionID
        FROM bronze.StateCareers_Collection
        WHERE SourceCollectionKey = ?
        """, args.collection).fetchone()

        if duplicate:
            print("Already ingested; no changes.")
            return

        existing = c.execute("""
        SELECT SourcePostingID, IsActive, LatestRawID
        FROM silver.StateCareers_JobPosting
        """).fetchall()

        old = {r[0]: r for r in existing}
        active = {r[0] for r in existing if r[1]}

        assert ids == active, "Inventory changed; aborting"

        current = {
            r[0]: json.loads(r[1])
            for r in c.execute("""
                SELECT s.SourcePostingID, b.RawPayloadJSON
                FROM silver.StateCareers_JobPosting s
                JOIN bronze.StateCareers_Raw b
                  ON s.LatestRawID = b.RawID
            """).fetchall()
        }

        fields = (
            "JobTitle", "Location", "MinimumSalaryRaw",
            "DatePosted", "JobURL"
        )

        changed = [
            r["SourcePostingID"]
            for r in rows
            if any(
                r.get(f) != current[r["SourcePostingID"]].get(f)
                for f in fields
            )
        ]

        assert not changed, (
            "Unexpected listing changes: " + str(changed)
        )

        print("Independent listing comparison: PASS")


        assert all(
            p in ("UNCHANGED", "RETRY_DETAIL")
            for p in m["plan"].values()
        ), "Unsupported lifecycle change"

        latest = c.execute("""
        SELECT MAX(CollectionDate)
        FROM bronze.StateCareers_Collection
        WHERE IsListingComplete = 1
        """).fetchone()[0]

        assert latest is None or day > latest

        collection_id = c.execute("""
        INSERT INTO bronze.StateCareers_Collection
        (
            CollectionDate, StartedUTC, CompletedUTC,
            SourceURL, ReportedPostings, RetrievedPostings,
            DetailsRetrieved, CollectionStatus,
            IsListingComplete, IsDetailComplete,
            SourceCollectionKey
        )
        OUTPUT INSERTED.CollectionID
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, day, start, end,
            "https://workforindiana.in.gov/search/",
            len(rows), len(rows), len(details),
            "SUCCEEDED", 1, 0, args.collection
        ).fetchone()[0]

        for r in rows:
            k = r["SourcePostingID"]
            d = details.get(k, {})
            payload = {**r, **d}

            if d:
                assert (ROOT / d["HTMLPath"]).is_file()

            raw_json = json.dumps(
                payload, ensure_ascii=False, sort_keys=True
            )

            record_hash = hashlib.sha256(
                raw_json.encode("utf-8")
            ).digest()

            c.execute("""
            INSERT INTO bronze.StateCareers_Raw
            (
                CollectionID, SourcePostingID,
                RequisitionIDRaw, JobTitleRaw,
                LocationRaw, MinimumSalaryRaw,
                DatePostedRaw, AgencyRaw,
                JobDescriptionRaw, JobURL,
                DetailStatus, CollectionUTC,
                RecordHash, RawPayloadJSON,
                HTMLPath, DetailRetrievedUTC
            )
            VALUES (
                ?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?
            )
            """,
                collection_id, k,
                d.get("RequisitionID") or None,
                r["JobTitle"], r["Location"],
                r["MinimumSalaryRaw"], r["DatePosted"],
                d.get("AgencyRaw") or None,
                d.get("JobDescriptionRaw"),
                r["JobURL"],
                d.get("DetailStatus", "NOT_RECHECKED"),
                start, record_hash, raw_json,
                d.get("HTMLPath"),
                utc(d["DetailRetrievedUTC"])
                if d.get("DetailRetrievedUTC") else None
            )

            c.execute("""
            UPDATE silver.StateCareers_JobPosting
            SET LastSeenUTC = ?
            WHERE SourcePostingID = ?
            """, start, k)

        c.execute("""
        UPDATE f
        SET f.LastSeenUTC = s.LastSeenUTC
        FROM gold.Fact_StateJobPosting f
        JOIN silver.StateCareers_JobPosting s
          ON f.JobPostingID = s.JobPostingID
        WHERE s.IsActive = 1
        """)

        c.execute("""
        INSERT INTO gold.Fact_RecruitmentDaily
        (
            ObservationDate, CollectionID,
            AdvertisedPostings, NewlyObservedPostings,
            NoLongerObservedPostings, ReactivatedPostings,
            CumulativeUniquePostings
        )
        VALUES (?, ?, ?, 0, 0, 0, ?)
        """, day, collection_id, len(ids), len(old))

        checks = {
            "Collections": "bronze.StateCareers_Collection",
            "Bronze observations": "bronze.StateCareers_Raw",
            "Silver postings": "silver.StateCareers_JobPosting",
            "Gold daily records": "gold.Fact_RecruitmentDaily"
        }

        for label, table in checks.items():
            count = c.execute(
                f"SELECT COUNT(*) FROM {table}"
            ).fetchone()[0]
            print(label, ":", count)

        assert c.execute("""
        SELECT COUNT(*) FROM bronze.StateCareers_Raw
        WHERE CollectionID = ?
        """, collection_id).fetchone()[0] == len(ids)

        print("Incremental reconciliation: PASS")

        if args.commit:
            cn.commit()
            print("Transaction committed successfully.")
        else:
            cn.rollback()
            print("Dry run completed. No records committed.")

    except Exception:
        cn.rollback()
        print("Ingestion failed. Transaction rolled back.")
        raise

    finally:
        cn.rollback()
        cn.close()

if __name__ == "__main__":
    main()
