import re
import sys
import pyodbc
from collections import Counter
from decimal import Decimal
from compensation_parser import extract_description_base, VERSION

CONNECTION = (
    "DRIVER={ODBC Driver 18 for SQL Server};"
    "SERVER=Matt;DATABASE=IndianaWorkforceDW;"
    "Trusted_Connection=yes;Encrypt=yes;"
    "TrustServerCertificate=yes;"
)

NUMBER = (
    r"(?:[0-9]{1,3}(?:,[0-9]{3})+|[0-9]+)"
    r"(?:\.[0-9]{1,2})?"
)

LISTING_PATTERN = re.compile(
    rf"\s*\$?\s*({NUMBER})"
    rf"(?:\s*(?:-|–|—|to)\s*\$?\s*({NUMBER}))?"
    r"\s*(/hr|/hour|per hour|hourly|"
    r"/year|per year|annually|annual|"
    r"/month|per month|monthly|"
    r"biweekly|bi-weekly)?\s*",
    re.I
)

UNIT_MAP = {
    "/hr": "HOURLY",
    "/hour": "HOURLY",
    "per hour": "HOURLY",
    "hourly": "HOURLY",
    "/year": "ANNUAL",
    "per year": "ANNUAL",
    "annually": "ANNUAL",
    "annual": "ANNUAL",
    "/month": "MONTHLY",
    "per month": "MONTHLY",
    "monthly": "MONTHLY",
    "biweekly": "BIWEEKLY",
    "bi-weekly": "BIWEEKLY",
}


def parse_listing(raw):
    match = LISTING_PATTERN.fullmatch(raw or "")

    if not match:
        return None

    amount = Decimal(match.group(1).replace(",", ""))

    if amount <= 0:
        return None

    if match.group(2):
        upper = Decimal(match.group(2).replace(",", ""))

        if upper < amount:
            return None

    unit = match.group(3)

    return (
        amount,
        UNIT_MAP[unit.lower()] if unit else "ANNUAL",
        "EXPLICIT" if unit else "SOURCE_ASSUMPTION"
    )


def assess(description, listing):

    results = extract_description_base(description)

    candidates = {
        (r["base_salary"], r["frequency"])
        for r in results
    }

    count = len(candidates)

    evidence = "\n".join(
        r["evidence"] for r in results
    )

    fallback = parse_listing(listing)

    if count > 1:
        return (
            None, "UNKNOWN", "UNRESOLVED",
            "AMBIGUOUS_DESCRIPTION",
            evidence, count
        )

    if count == 1:
        amount, frequency = next(iter(candidates))

        if frequency != "UNKNOWN":
            basis = "EXPLICIT"

        elif fallback and fallback[0] == amount:
            frequency = fallback[1]
            basis = fallback[2]

        else:
            frequency = "ANNUAL"
            basis = "SOURCE_ASSUMPTION"

        return (
            amount, frequency, basis,
            "DESCRIPTION_BASE", evidence, count
        )

    if fallback:
        amount, frequency, basis = fallback

        return (
            amount, frequency, basis,
            "LISTING_FALLBACK", listing, count
        )

    return (
        None, "UNKNOWN", "UNRESOLVED",
        "REVIEW_REQUIRED", listing, count
    )


def main():

    commit = "--commit" in sys.argv
    conn = pyodbc.connect(CONNECTION, autocommit=False)

    try:
        cursor = conn.cursor()

        cursor.execute("""
            SET XACT_ABORT ON;
            SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
        """)

        rows = cursor.execute("""
            SELECT
                JobPostingID,
                LatestRawID,
                LatestListingRawID,
                JobDescription,
                MinimumSalaryRaw
            FROM silver.StateCareers_JobPosting
            WHERE IsActive = 1
            ORDER BY JobPostingID
        """).fetchall()

        if not rows:
            raise RuntimeError("No active postings found")

        summary = Counter()

        for job_id, source_id, listing_id, description, listing in rows:

            if source_id is None or listing_id is None:
                raise RuntimeError(
                    f"Missing source lineage: {job_id}"
                )

            amount, frequency, basis, method, evidence, count = (
                assess(description, listing)
            )

            summary[method] += 1

            cursor.execute("""
                UPDATE control.RecruitmentSalaryAssessment
                SET BaseSalary = ?,
                    SalaryFrequency = ?,
                    FrequencyBasis = ?,
                    StandardizationMethod = ?,
                    Evidence = ?,
                    ParserVersion = ?,
                    CandidateCount = ?,
                    AssessedUTC = SYSUTCDATETIME()
                WHERE JobPostingID = ?
                  AND SourceRawID = ?
                  AND ListingRawID = ?
            """,
                amount, frequency, basis, method,
                evidence, VERSION, count,
                job_id, source_id, listing_id
            )

            if cursor.rowcount == 0:

                cursor.execute("""
                    INSERT INTO control.RecruitmentSalaryAssessment
                    (
                        JobPostingID,
                        SourceRawID,
                        ListingRawID,
                        BaseSalary,
                        SalaryFrequency,
                        FrequencyBasis,
                        StandardizationMethod,
                        Evidence,
                        ParserVersion,
                        CandidateCount
                    )
                    VALUES (?,?,?,?,?,?,?,?,?,?)
                """,
                    job_id, source_id, listing_id,
                    amount, frequency, basis, method,
                    evidence, VERSION, count
                )

        assessed = cursor.execute("""
            SELECT COUNT(*)
            FROM silver.StateCareers_JobPosting p
            JOIN control.RecruitmentSalaryAssessment a
                ON a.JobPostingID = p.JobPostingID
                AND a.SourceRawID = p.LatestRawID
                AND a.ListingRawID = p.LatestListingRawID
            WHERE p.IsActive = 1
        """).fetchone()[0]

        assert assessed == len(rows)
        assert sum(summary.values()) == len(rows)

        print("\n=== AUTOMATED SALARY ASSESSMENT ===")
        print("Parser version:", VERSION)
        print("Active postings:", len(rows))

        for method, count in sorted(summary.items()):
            print(f"{method}: {count}")

        print("Current assessments:", assessed)
        print("Source reconciliation: PASS")

        if commit:
            conn.commit()
            print("TRANSACTION: COMMITTED")
        else:
            conn.rollback()
            print("TRANSACTION: DRY RUN - ROLLED BACK")

        print("AUTOMATED SALARY ASSESSMENT: PASS")

    except Exception:
        conn.rollback()
        raise

    finally:
        conn.close()


if __name__ == "__main__":
    main()
