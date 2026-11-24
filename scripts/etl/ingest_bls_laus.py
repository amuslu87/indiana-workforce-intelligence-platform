"""Indiana Workforce Intelligence: BLS LAUS API -> Bronze / Silver / Gold.

Run: python ingest_bls_laus.py
Dependencies: pip install requests pyodbc
Target: SQL Server Matt / IndianaWorkforceDW (Windows integrated auth).
BLS Public API v1 returns a rolling window of recent observations.
"""
import json
import logging
import os
import sys
import traceback
import time
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation

import pyodbc
import requests

SERVER = os.getenv('IWI_SQL_SERVER', 'Matt')
DATABASE = os.getenv('IWI_SQL_DATABASE', 'IndianaWorkforceDW')
API_URL = 'https://api.bls.gov/publicAPI/v1/timeseries/data/'
SERIES = {
    'LAUST180000000000003': ('UNEMPLOYMENT_RATE', 'Percent'),
    'LAUST180000000000004': ('UNEMPLOYED_PERSONS', 'Persons'),
    'LAUST180000000000005': ('EMPLOYED_PERSONS', 'Persons'),
    'LAUST180000000000006': ('CIVILIAN_LABOR_FORCE', 'Persons'),
}
LOG = logging.getLogger('bls_laus')

DDL = [
    """IF OBJECT_ID('bronze.BLS_LAUS_API_Raw','U') IS NULL
    CREATE TABLE bronze.BLS_LAUS_API_Raw (
      BronzeBLSID BIGINT IDENTITY(1,1) PRIMARY KEY,
      SeriesID VARCHAR(30) NOT NULL,
      ReportingYear SMALLINT NOT NULL,
      PeriodCode VARCHAR(3) NOT NULL,
      RawValue VARCHAR(60) NOT NULL,
      RawObservationJson NVARCHAR(MAX) NOT NULL,
      SourceURL VARCHAR(500) NOT NULL,
      IngestedAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
      CONSTRAINT UQ_BLS_Bronze_SeriesPeriod UNIQUE (SeriesID,ReportingYear,PeriodCode)
    )""",
    """IF OBJECT_ID('silver.BLS_LAUS_Indiana','U') IS NULL
    CREATE TABLE silver.BLS_LAUS_Indiana (
      SilverBLSID BIGINT IDENTITY(1,1) PRIMARY KEY,
      BronzeBLSID BIGINT NOT NULL UNIQUE,
      SeriesID VARCHAR(30) NOT NULL,
      FIPSCode CHAR(5) NOT NULL DEFAULT '18000',
      ReportingYear SMALLINT NOT NULL,
      MonthCode TINYINT NOT NULL,
      ReportingDate DATE NOT NULL,
      MeasureCode VARCHAR(40) NOT NULL,
      MeasureUnit VARCHAR(15) NOT NULL,
      MeasureValue DECIMAL(18,3) NOT NULL,
      TransformedAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
      CONSTRAINT FK_BLS_Silver_Bronze FOREIGN KEY (BronzeBLSID)
        REFERENCES bronze.BLS_LAUS_API_Raw(BronzeBLSID),
      CONSTRAINT UQ_BLS_Silver_SeriesDate UNIQUE(SeriesID,ReportingDate),
      CONSTRAINT CK_BLS_Silver_Month CHECK(MonthCode BETWEEN 1 AND 12),
      CONSTRAINT CK_BLS_Silver_Value CHECK(MeasureValue >= 0)
    )""",
    """IF OBJECT_ID('gold.Dim_BLS_Measure','U') IS NULL
    CREATE TABLE gold.Dim_BLS_Measure (
      MeasureKey INT IDENTITY(1,1) PRIMARY KEY,
      SeriesID VARCHAR(30) NOT NULL UNIQUE,
      MeasureCode VARCHAR(40) NOT NULL UNIQUE,
      MeasureUnit VARCHAR(15) NOT NULL
    )""",
    """IF OBJECT_ID('gold.Dim_BLS_ReportingPeriod','U') IS NULL
    CREATE TABLE gold.Dim_BLS_ReportingPeriod (
      BLSPeriodKey INT IDENTITY(1,1) PRIMARY KEY,
      ReportingYear SMALLINT NOT NULL,
      MonthCode TINYINT NOT NULL,
      ReportingDate DATE NOT NULL UNIQUE,
      CONSTRAINT UQ_BLS_Period_YearMonth UNIQUE(ReportingYear,MonthCode),
      CONSTRAINT CK_BLS_Period_Month CHECK(MonthCode BETWEEN 1 AND 12)
    )""",
    """IF OBJECT_ID('gold.Fact_BLS_LaborMarket','U') IS NULL
    CREATE TABLE gold.Fact_BLS_LaborMarket (
      BLSFactKey BIGINT IDENTITY(1,1) PRIMARY KEY,
      SilverBLSID BIGINT NOT NULL UNIQUE,
      GeographyKey INT NOT NULL,
      BLSPeriodKey INT NOT NULL,
      MeasureKey INT NOT NULL,
      MeasureValue DECIMAL(18,3) NOT NULL,
      LoadedAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
      CONSTRAINT FK_BLS_Fact_Silver FOREIGN KEY(SilverBLSID)
        REFERENCES silver.BLS_LAUS_Indiana(SilverBLSID),
      CONSTRAINT FK_BLS_Fact_Geography FOREIGN KEY(GeographyKey)
        REFERENCES gold.Dim_Geography(GeographyKey),
      CONSTRAINT FK_BLS_Fact_Period FOREIGN KEY(BLSPeriodKey)
        REFERENCES gold.Dim_BLS_ReportingPeriod(BLSPeriodKey),
      CONSTRAINT FK_BLS_Fact_Measure FOREIGN KEY(MeasureKey)
        REFERENCES gold.Dim_BLS_Measure(MeasureKey),
      CONSTRAINT UQ_BLS_Fact_Grain UNIQUE(GeographyKey,BLSPeriodKey,MeasureKey)
    )""",
    """IF OBJECT_ID('bronze.BLS_API_IngestionRun','U') IS NULL
    CREATE TABLE bronze.BLS_API_IngestionRun (
      RunID BIGINT IDENTITY(1,1) PRIMARY KEY,
      StartedAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
      CompletedAt DATETIME2(3) NULL,
      RunStatus VARCHAR(20) NOT NULL,
      SeriesRequested INT NOT NULL,
      ObservationsReceived INT NULL,
      BronzeInserted INT NULL,
      SilverInserted INT NULL,
      GoldInserted INT NULL,
      ErrorMessage NVARCHAR(2000) NULL
    )""",
]


def connect():
    return pyodbc.connect(
        f'DRIVER={{ODBC Driver 18 for SQL Server}};SERVER={SERVER};'
        f'DATABASE={DATABASE};Trusted_Connection=yes;Encrypt=yes;'
        'TrustServerCertificate=yes;', autocommit=False, timeout=20)


def fetch_series(session, series_id):
    for attempt in range(1, 4):
        try:
            response = session.get(API_URL + series_id, timeout=35)
            response.raise_for_status()
            payload = response.json()
            if payload.get('status') != 'REQUEST_SUCCEEDED':
                raise RuntimeError(f'BLS API status for {series_id}: '
                                   f"{payload.get('status')} {payload.get('message')}")
            returned = payload.get('Results', {}).get('series', [])
            if len(returned) != 1 or returned[0].get('seriesID') != series_id:
                raise RuntimeError(f'Unexpected BLS series response: {series_id}')
            return returned[0].get('data', [])
        except (requests.RequestException, ValueError) as exc:
            if attempt == 3:
                raise RuntimeError(f'BLS request failed for {series_id}: {exc}') from exc
            LOG.warning('Retry %d for %s: %s', attempt, series_id, exc)
            time.sleep(attempt * 2)


def normalize(series_id, observation):
    year = int(observation['year'])
    period = str(observation['period'])
    if not (2000 <= year <= 2100 and len(period) == 3 and
            period.startswith('M') and period[1:].isdigit()):
        return None  # Ignore annual-average periods (M13) and unsupported periods.
    month = int(period[1:])
    if month not in range(1, 13):
        return None
    try:
        value = Decimal(str(observation['value']).replace(',', ''))
    except (InvalidOperation, TypeError) as exc:
        raw = str(observation.get('value', '')).strip()
        if raw in ('', '-', '--', 'N/A', 'NA', '(NA)'):
            LOG.warning('Skipping unpublished/missing BLS value: %s %s-%s (raw=%r)', series_id, year, period, raw)
            return None
        raise ValueError(f'Invalid numeric value {series_id} {year}-{period}: {raw!r}') from exc
    if not value.is_finite() or value < 0:
        raise ValueError(f'Invalid value {series_id} {year}-{period}: {value}')
    if SERIES[series_id][0] == 'UNEMPLOYMENT_RATE' and value > 100:
        raise ValueError(f'Invalid unemployment rate {year}-{period}: {value}')
    return (series_id, year, period, str(value),
            json.dumps(observation, ensure_ascii=False, separators=(',', ':')),
            API_URL + series_id)


def execute_scalar(cur, sql, *params):
    row = cur.execute(sql, *params).fetchone()
    return row[0] if row else None


def main():
    logging.basicConfig(level=logging.INFO, format='%(levelname)s %(message)s')
    LOG.info('BLS LAUS ingestion started: %s / %s', SERVER, DATABASE)
    observations = []
    with requests.Session() as session:
        session.headers.update({'User-Agent': 'IndianaWorkforceIntelligence/1.0 (educational project)'})
        for series_id, (measure, unit) in SERIES.items():
            records = fetch_series(session, series_id)
            normalized = [row for x in records if (row := normalize(series_id, x)) is not None]
            LOG.info('%s (%s): %d valid monthly observations from %d returned records', series_id, measure, len(normalized), len(records))
            if not normalized:
                raise RuntimeError(f'No monthly observations returned for {series_id}')
            observations.extend(normalized)
    keys = [(x[0], x[1], x[2]) for x in observations]
    if len(keys) != len(set(keys)):
        raise RuntimeError('Duplicate series/year/period keys in BLS API payload')

    con = connect()
    cur = con.cursor()
    run_id = None
    try:
        for ddl in DDL:
            cur.execute(ddl)
        for series_id, (code, unit) in SERIES.items():
            cur.execute('''IF NOT EXISTS (SELECT 1 FROM gold.Dim_BLS_Measure WHERE SeriesID=?)
                INSERT INTO gold.Dim_BLS_Measure(SeriesID,MeasureCode,MeasureUnit)
                VALUES(?,?,?)''', series_id, series_id, code, unit)
        cur.execute('''INSERT INTO bronze.BLS_API_IngestionRun(RunStatus,SeriesRequested)
            OUTPUT INSERTED.RunID VALUES('RUNNING',?)''', len(SERIES))
        run_id = cur.fetchone()[0]
        con.commit()

        bronze_count = 0
        for row in observations:
            cur.execute('''IF NOT EXISTS (
                  SELECT 1 FROM bronze.BLS_LAUS_API_Raw WITH (UPDLOCK,HOLDLOCK)
                  WHERE SeriesID=? AND ReportingYear=? AND PeriodCode=?)
                INSERT INTO bronze.BLS_LAUS_API_Raw
                  (SeriesID,ReportingYear,PeriodCode,RawValue,RawObservationJson,SourceURL)
                VALUES(?,?,?,?,?,?)''', row[0], row[1], row[2], *row)
            bronze_count += max(cur.rowcount, 0)

        # Silver: typed, validated observations; retain Bronze record lineage.
        cur.execute('''INSERT INTO silver.BLS_LAUS_Indiana
            (BronzeBLSID,SeriesID,FIPSCode,ReportingYear,MonthCode,ReportingDate,
             MeasureCode,MeasureUnit,MeasureValue)
            SELECT b.BronzeBLSID,b.SeriesID,'18000',b.ReportingYear,
                   CAST(SUBSTRING(b.PeriodCode,2,2) AS TINYINT),
                   DATEFROMPARTS(b.ReportingYear,CAST(SUBSTRING(b.PeriodCode,2,2) AS INT),1),
                   m.MeasureCode,m.MeasureUnit,
                   TRY_CONVERT(DECIMAL(18,3),REPLACE(b.RawValue,',',''))
            FROM bronze.BLS_LAUS_API_Raw b
            JOIN gold.Dim_BLS_Measure m ON m.SeriesID=b.SeriesID
            WHERE NOT EXISTS (
                SELECT 1 FROM silver.BLS_LAUS_Indiana s WHERE s.BronzeBLSID=b.BronzeBLSID)
              AND b.PeriodCode LIKE 'M[0-1][0-9]'
              AND TRY_CONVERT(DECIMAL(18,3),REPLACE(b.RawValue,',','')) IS NOT NULL
              AND CAST(SUBSTRING(b.PeriodCode,2,2) AS INT) BETWEEN 1 AND 12''')
        silver_count = cur.rowcount

        # Independent BLS date dimension: source coverage can include months
        # absent from the original STATS Indiana reporting-period dimension.
        cur.execute('''INSERT INTO gold.Dim_BLS_ReportingPeriod
            (ReportingYear,MonthCode,ReportingDate)
            SELECT DISTINCT s.ReportingYear,s.MonthCode,s.ReportingDate
            FROM silver.BLS_LAUS_Indiana s
            WHERE NOT EXISTS (SELECT 1 FROM gold.Dim_BLS_ReportingPeriod p
                              WHERE p.ReportingDate=s.ReportingDate)''')

        geography_key = execute_scalar(cur,
            "SELECT GeographyKey FROM gold.Dim_Geography WHERE FIPSCode='18000'")
        if geography_key is None:
            raise RuntimeError('Indiana FIPS 18000 is absent from gold.Dim_Geography')

        cur.execute('''INSERT INTO gold.Fact_BLS_LaborMarket
            (SilverBLSID,GeographyKey,BLSPeriodKey,MeasureKey,MeasureValue)
            SELECT s.SilverBLSID,g.GeographyKey,p.BLSPeriodKey,m.MeasureKey,s.MeasureValue
            FROM silver.BLS_LAUS_Indiana s
            JOIN gold.Dim_Geography g ON g.FIPSCode=s.FIPSCode
            JOIN gold.Dim_BLS_ReportingPeriod p ON p.ReportingDate=s.ReportingDate
            JOIN gold.Dim_BLS_Measure m ON m.SeriesID=s.SeriesID
            WHERE NOT EXISTS (
                SELECT 1 FROM gold.Fact_BLS_LaborMarket f
                WHERE f.SilverBLSID=s.SilverBLSID)''')
        gold_count = cur.rowcount

        # Verify all API observations are represented and lineage is consistent.
        absent = execute_scalar(cur, '''SELECT COUNT(*)
            FROM bronze.BLS_LAUS_API_Raw b
            LEFT JOIN silver.BLS_LAUS_Indiana s ON s.BronzeBLSID=b.BronzeBLSID
            LEFT JOIN gold.Fact_BLS_LaborMarket f ON f.SilverBLSID=s.SilverBLSID
            WHERE s.SilverBLSID IS NULL OR f.BLSFactKey IS NULL''')
        if absent:
            raise RuntimeError(f'{absent} Bronze observations lack Silver/Gold lineage')
        mismatches = execute_scalar(cur, '''SELECT COUNT(*)
            FROM gold.Fact_BLS_LaborMarket f
            JOIN silver.BLS_LAUS_Indiana s ON s.SilverBLSID=f.SilverBLSID
            WHERE f.MeasureValue<>s.MeasureValue''')
        if mismatches:
            raise RuntimeError(f'{mismatches} Gold/Silver measure mismatches')
        cur.execute('''UPDATE bronze.BLS_API_IngestionRun SET
            CompletedAt=SYSUTCDATETIME(),RunStatus='SUCCESS',
            ObservationsReceived=?,BronzeInserted=?,SilverInserted=?,GoldInserted=?
            WHERE RunID=?''', len(observations), bronze_count,
            silver_count, gold_count, run_id)
        con.commit()
        print('\n=== BLS API INGESTION SUCCESS ===')
        print(f'Run ID: {run_id}')
        print(f'API monthly observations: {len(observations)}')
        print(f'Bronze new rows: {bronze_count}')
        print(f'Silver new rows: {silver_count}')
        print(f'Gold new rows: {gold_count}')
        print('Missing lineage: 0 | Value mismatches: 0')
        print('\nGold rows by measure:')
        for row in cur.execute('''SELECT m.MeasureCode,COUNT(*)
            FROM gold.Fact_BLS_LaborMarket f
            JOIN gold.Dim_BLS_Measure m ON m.MeasureKey=f.MeasureKey
            GROUP BY m.MeasureCode ORDER BY m.MeasureCode'''):
            print(f'  {row[0]}: {row[1]}')
        print('\nRe-run this script to verify idempotence (new rows should be zero).')
    except Exception as exc:
        con.rollback()
        LOG.exception('BLS ingestion failed')
        if run_id is not None:
            try:
                cur.execute('''UPDATE bronze.BLS_API_IngestionRun
                    SET CompletedAt=SYSUTCDATETIME(),RunStatus='FAILED',
                    ErrorMessage=? WHERE RunID=?''', str(exc)[:2000], run_id)
                con.commit()
            except Exception:
                con.rollback()
        raise
    finally:
        con.close()


if __name__ == '__main__':
    try:
        main()
    except Exception:
        traceback.print_exc()
        sys.exit(1)
