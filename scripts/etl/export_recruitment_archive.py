import csv
import hashlib
from pathlib import Path
import pyodbc

out = Path(
    r"C:\Projects\IndianaWorkforceDataArchive\approved"
)

cn = pyodbc.connect(
    "DRIVER={ODBC Driver 18 for SQL Server};"
    "SERVER=Matt;DATABASE=IndianaWorkforceDW;"
    "Trusted_Connection=yes;Encrypt=yes;"
    "TrustServerCertificate=yes;"
)

try:
    c = cn.cursor()
    rows = c.execute("""
        SELECT ObservationDate,
               AdvertisedPostings,
               NewlyObservedPostings,
               NoLongerObservedPostings,
               ReactivatedPostings,
               CumulativeUniquePostings
        FROM gold.Fact_RecruitmentDaily
        ORDER BY ObservationDate
    """).fetchall()

    headers = [d[0] for d in c.description]

    for row in rows:
        assert all(
            isinstance(v, int) and v >= 0
            for v in row[1:]
        )

    p = out / "recruitment_daily.csv"

    with p.open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(headers)
        w.writerows(rows)

    digest = hashlib.sha256(p.read_bytes()).hexdigest()

    p.with_suffix(".sha256").write_text(
        digest + "  " + p.name + "\n",
        encoding="utf-8"
    )

    print("Exported records:", len(rows))
    print("SHA-256:", digest)
    print("AGGREGATED ARCHIVE CREATED")

finally:
    cn.close()
