import pyodbc
from compensation_parser import extract_description_base

conn = pyodbc.connect(
    "DRIVER={ODBC Driver 18 for SQL Server};"
    "SERVER=Matt;"
    "DATABASE=IndianaWorkforceDW;"
    "Trusted_Connection=yes;"
    "Encrypt=yes;"
    "TrustServerCertificate=yes;"
)

cursor = conn.cursor()

rows = cursor.execute("""
    SELECT JobPostingID, JobTitle,
           JobDescription, MinimumSalaryRaw
    FROM silver.StateCareers_JobPosting
    WHERE IsActive = 1
    ORDER BY JobPostingID
""").fetchall()

count = 0

for job_id, title, description, listing in rows:

    if extract_description_base(description):
        continue

    count += 1

    print(f"\nID: {job_id} | {title}")
    print(f"Listing: {listing}")

    evidence = cursor.execute("""
        SELECT DISTINCT
            CAST(LEFT(c.SalaryEvidence,1000)
                AS nvarchar(1000))
        FROM silver.StateCareers_JobCompensation c
        JOIN silver.StateCareers_JobPosting p
            ON p.JobPostingID = c.JobPostingID
            AND p.LatestRawID = c.SourceRawID
        WHERE c.JobPostingID = ?
    """, job_id).fetchall()

    for item in evidence:
        print(item[0])

print(f"\nTOTAL UNMATCHED POSTINGS: {count}")

conn.close()
