import os
import sys
import subprocess
import uuid
from pathlib import Path

import pandas
import requests
import openpyxl
import pyodbc

ROOT = Path(r"C:\WorkforceRuntime")
results = []


def check(name, passed, detail=""):
    results.append(bool(passed))
    status = "PASS" if passed else "FAIL"
    print(f"[{status}] {name} | {detail}", flush=True)


print("\n=== WINDOWS IDENTITY ===")

identity = subprocess.check_output(
    ["whoami"], text=True
).strip()

check(
    "Restricted Windows identity",
    identity.lower() == r"matt\svc_workforce_etl",
    identity
)

if not results[-1]:
    sys.exit("Incorrect execution identity. Testing stopped.")


print("\n=== PYTHON RUNTIME ===")

check(
    "Dedicated Python executable",
    Path(sys.executable).resolve() ==
    (ROOT / "python" / "python.exe").resolve(),
    sys.executable
)

print("Python:", sys.version)
print("pandas:", pandas.__version__)
print("requests:", requests.__version__)
print("openpyxl:", openpyxl.__version__)
print("pyodbc:", pyodbc.version)


print("\n=== FILESYSTEM SECURITY ===")

def test_write(folder, expected):
    path = ROOT / folder / f"security_test_{uuid.uuid4().hex}.tmp"

    try:
        with path.open("x") as handle:
            handle.write("Temporary security validation")

        allowed = True
        detail = "Write permitted"

        try:
            path.unlink()
        except OSError as exc:
            check(f"{folder}: cleanup", False, str(exc))

    except PermissionError:
        allowed = False
        detail = "Access denied"

    except OSError as exc:
        check(f"{folder}: write test", False, str(exc))
        return

    check(f"{folder}: write permission", allowed == expected, detail)


for folder in ["state", "logs", "data"]:
    test_write(folder, True)

for folder in ["python", "app", "config"]:
    test_write(folder, False)


print("\n=== SQL SERVER AUTHENTICATION ===")

connection_string = (
    "DRIVER={ODBC Driver 18 for SQL Server};"
    "SERVER=Matt;"
    "DATABASE=IndianaWorkforceDW;"
    "Trusted_Connection=yes;"
    "Encrypt=yes;"
    "TrustServerCertificate=yes;"
)

try:
    con = pyodbc.connect(connection_string, timeout=10)
    check("SQL Server connection", True)

    cur = con.cursor()

    cur.execute("""
        SELECT
            ORIGINAL_LOGIN(),
            USER_NAME(),
            IS_SRVROLEMEMBER('sysadmin'),
            IS_MEMBER('db_owner'),
            IS_MEMBER('rl_workforce_etl')
    """)

    login, user, sysadmin, owner, etl_role = cur.fetchone()

    check(
        "SQL Windows login",
        login.lower() == r"matt\svc_workforce_etl",
        login
    )

    check(
        "Database user mapping",
        user == "svc_workforce_etl",
        user
    )

    check("Not sysadmin", sysadmin == 0, sysadmin)
    check("Not database owner", owner == 0, owner)
    check("ETL role membership", etl_role == 1, etl_role)


    print("\n=== AUTHORIZED DATA ACCESS ===")

    views = [
        "serving.vw_Unemployment",
        "serving.vw_LaborMarket",
        "serving.vw_OccupationalWages",
        "serving.vw_OccupationalProjection"
    ]

    for view in views:
        try:
            cur.execute(f"SELECT COUNT_BIG(*) FROM {view}")
            count = cur.fetchone()[0]
            check(f"SELECT {view}", True, f"{count} records")
        except pyodbc.Error as exc:
            check(f"SELECT {view}", False, str(exc))


    print("\n=== EFFECTIVE SQL PERMISSIONS ===")

    tests = [
        ("bronze.BLS_LAUS_API_Raw", "OBJECT", "SELECT", 1),
        ("bronze.BLS_LAUS_API_Raw", "OBJECT", "INSERT", 1),
        ("bronze.BLS_API_IngestionRun", "OBJECT", "UPDATE", 1),
        ("gold.Fact_BLS_LaborMarket", "OBJECT", "INSERT", 1),
        ("gold.Fact_Unemployment", "OBJECT", "DELETE", 0),
        ("gold.Fact_Unemployment", "OBJECT", "ALTER", 0),
        ("gold", "SCHEMA", "ALTER", 0),
        ("bronze", "SCHEMA", "ALTER", 0),
        ("IndianaWorkforceDW", "DATABASE", "CREATE TABLE", 0),
        ("IndianaWorkforceDW", "DATABASE", "ALTER ANY USER", 0),
        ("IndianaWorkforceDW", "DATABASE", "CONTROL", 0)
    ]

    for securable, category, permission, expected in tests:

        cur.execute(
            "SELECT HAS_PERMS_BY_NAME(?, ?, ?)",
            securable, category, permission
        )

        actual = cur.fetchone()[0]

        check(
            f"{permission} on {securable}",
            actual == expected,
            f"Expected={expected}, Actual={actual}"
        )

    con.close()

except pyodbc.Error as exc:
    check("SQL security assessment", False, str(exc))


print("\n=== SECURITY TEST SUMMARY ===")

passed = sum(results)
failed = len(results) - passed

print(f"Total tests: {len(results)}")
print(f"Passed: {passed}")
print(f"Failed: {failed}")

if failed:
    print("SECURITY VALIDATION FAILED")
    sys.exit(1)

print("ALL SECURITY TESTS PASSED")
sys.exit(0)
