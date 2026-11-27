import pyodbc
from datetime import datetime, timezone

CONN = (
    "DRIVER={ODBC Driver 18 for SQL Server};"
    "SERVER=Matt;DATABASE=IndianaWorkforceDW;"
    "Trusted_Connection=yes;Encrypt=yes;"
    "TrustServerCertificate=yes;"
)

def deactivate(c, posting_id, observed):
    c.execute("""
        UPDATE silver.StateCareers_JobPosting
        SET IsActive = 0,
            FirstNotSeenUTC = ?
        WHERE SourcePostingID = ?
          AND IsActive = 1
          AND LastSeenUTC <= ?
    """, observed, posting_id, observed)

    return c.rowcount

def reactivate(c, posting_id, observed):
    c.execute("""
        UPDATE silver.StateCareers_JobPosting
        SET IsActive = 1,
            FirstNotSeenUTC = NULL,
            LastSeenUTC = ?
        WHERE SourcePostingID = ?
          AND IsActive = 0
          AND LastSeenUTC <= ?
          AND FirstNotSeenUTC <= ?
    """, observed, posting_id, observed, observed)

    return c.rowcount

def sync_gold(c):
    c.execute("""
        UPDATE f
        SET f.IsActive = s.IsActive,
            f.LastSeenUTC = s.LastSeenUTC,
            f.FirstNotSeenUTC = s.FirstNotSeenUTC
        FROM gold.Fact_StateJobPosting f
        JOIN silver.StateCareers_JobPosting s
          ON f.JobPostingID = s.JobPostingID
    """)

def state(c, posting_id):
    return c.execute("""
        SELECT s.IsActive, s.FirstNotSeenUTC,
               f.IsActive, f.FirstNotSeenUTC
        FROM silver.StateCareers_JobPosting s
        JOIN gold.Fact_StateJobPosting f
          ON s.JobPostingID = f.JobPostingID
        WHERE s.SourcePostingID = ?
    """, posting_id).fetchone()

def test():
    cn = pyodbc.connect(CONN, autocommit=False)
    c = cn.cursor()

    try:
        c.execute("""
            SET XACT_ABORT ON;
            SET QUOTED_IDENTIFIER ON;
            SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
        """)

        k = c.execute("""
            SELECT TOP 1 SourcePostingID
            FROM silver.StateCareers_JobPosting
            WHERE IsActive = 1
            ORDER BY SourcePostingID
        """).fetchone()[0]

        now = c.execute(
            "SELECT CAST(SYSUTCDATETIME() AS datetime2(3))"
        ).fetchone()[0]

        print("SQL-aligned timestamp:", now)

        print("Testing posting:", k)

        assert deactivate(c, k, now) == 1
        sync_gold(c)
        r = state(c, k)

        assert not r[0] and r[1] is not None
        assert not r[2] and r[3] is not None
        print("Removal and Gold synchronization: PASS")

        assert deactivate(c, k, now) == 0
        print("Repeated removal protection: PASS")

        assert reactivate(c, k, now) == 1
        sync_gold(c)
        r = state(c, k)

        assert r[0] and r[1] is None
        assert r[2] and r[3] is None
        print("Reactivation and Gold synchronization: PASS")

        assert reactivate(c, k, now) == 0
        print("Repeated reactivation protection: PASS")

    finally:
        cn.rollback()
        cn.close()
        print("All test changes rolled back.")

if __name__ == "__main__":
    test()
