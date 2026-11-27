import pyodbc
from collections import Counter
from compensation_parser import extract_description_base

connection_string = (
    "DRIVER={ODBC Driver 18 for SQL Server};"
    "SERVER=Matt;"
    "DATABASE=IndianaWorkforceDW;"
    "Trusted_Connection=yes;"
    "Encrypt=yes;"
    "TrustServerCertificate=yes;"
)

with pyodbc.connect(connection_string) as conn:
    rows = conn.cursor().execute("""
        SELECT
            p.JobPostingID,
            p.JobTitle,
            p.JobDescription,
            s.BaseSalary,
            s.SalaryFrequency
        FROM silver.StateCareers_JobPosting p
        JOIN silver.vw_RecruitmentStandardizedSalary s
            ON p.JobPostingID = s.JobPostingID
        WHERE p.IsActive = 1
        ORDER BY p.JobPostingID
    """).fetchall()

summary = Counter()
discrepancies = []
ambiguous = []
unmatched = []

for row in rows:

    job_id, title, description, current, frequency = row

    results = extract_description_base(description)

    candidates = {
        (r["base_salary"], r["frequency"])
        for r in results
    }

    if not candidates:
        summary["NO_DESCRIPTION_MATCH"] += 1
        unmatched.append((job_id, title, current))
        continue

    if len(candidates) > 1:
        summary["MULTIPLE_CANDIDATES"] += 1
        ambiguous.append((job_id, title, sorted(candidates)))
        continue

    amount, parsed_frequency = next(iter(candidates))

    if current is None:
        summary["POTENTIAL_RECOVERY"] += 1
        discrepancies.append(
            (job_id, title, current, amount, parsed_frequency)
        )

    elif amount != current:
        summary["AMOUNT_DISCREPANCY"] += 1
        discrepancies.append(
            (job_id, title, current, amount, parsed_frequency)
        )

    elif parsed_frequency == "UNKNOWN":
        summary["AMOUNT_MATCH_FREQUENCY_UNKNOWN"] += 1

    elif parsed_frequency != frequency:
        summary["FREQUENCY_DISCREPANCY"] += 1
        discrepancies.append(
            (job_id, title, current, amount, parsed_frequency)
        )

    else:
        summary["FULL_MATCH"] += 1

print("\n=== DESCRIPTION PARSER VALIDATION ===")
print("Total postings:", len(rows))

for status, count in sorted(summary.items()):
    print(f"{status}: {count}")

print("\n=== DISCREPANCIES AND RECOVERIES ===")
for item in discrepancies:
    print(item)

print("\n=== MULTIPLE SALARY CANDIDATES ===")
for item in ambiguous:
    print(item)

print("\n=== UNMATCHED DESCRIPTION SAMPLE ===")
for item in unmatched[:20]:
    print(item)

assert sum(summary.values()) == len(rows)

print("\nRECORD RECONCILIATION: PASS")
print("PRODUCTION DATA PREVIEW COMPLETE")
