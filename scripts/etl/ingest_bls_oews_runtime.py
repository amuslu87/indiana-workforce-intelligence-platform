"""BLS OEWS May 2025 Indiana state employment/wage ingestion.
Dependencies: pip install requests pandas openpyxl pyodbc
Run: python -u ingest_bls_oews.py
Optional: --file C:\\path\\to\\oesm25st.zip (or extracted .xlsx)
Environment: SQL_SERVER=Matt SQL_DATABASE=IndianaWorkforceDW
"""
import argparse
import hashlib
import io
import json
import logging
import os
from datetime import datetime, timezone
from pathlib import Path
from zipfile import ZipFile

import pandas as pd
import pyodbc
import requests

URL = 'https://www.bls.gov/oes/special-requests/oesm25st.zip'
YEAR = 2025
LOG = logging.getLogger('oews')


def get_workbook(path):
    if path:
        p = Path(path)
        if not p.is_file():
            raise FileNotFoundError(p)
        payload = p.read_bytes()
        name = str(p)
    else:
        LOG.info('Downloading official BLS OEWS state dataset: %s', URL)
        response = requests.get(URL, headers={'User-Agent': 'Mozilla/5.0 (compatible; WorkforceResearch/1.0)'}, timeout=90)
        response.raise_for_status()
        payload = response.content
        name = URL
    sha = hashlib.sha256(payload).hexdigest()
    if payload[:2] == b'PK':
        with ZipFile(io.BytesIO(payload)) as z:
            candidates = [n for n in z.namelist() if n.lower().endswith('.xlsx') and not Path(n).name.startswith('~$')]
            if not candidates:
                raise ValueError('Archive has no XLSX file; contents: ' + str(z.namelist()))
            candidate = next((n for n in candidates if 'state' in n.lower() or 'st_' in n.lower()), candidates[0])
            LOG.info('Workbook inside archive: %s', candidate)
            return io.BytesIO(z.read(candidate)), sha, name + ' :: ' + candidate
    if payload[:4] == b'PK\x03\x04':
        return io.BytesIO(payload), sha, name
    raise ValueError('Expected a ZIP/XLSX download; received an unexpected file. Download the official State XLSX/ZIP from https://www.bls.gov/oes/tables.htm and rerun with --file.')


def normalize_frame(workbook):
    df = pd.read_excel(workbook, dtype=str, engine='openpyxl')
    df.columns = [str(c).strip().upper().replace(' ', '_') for c in df.columns]
    required = {'AREA', 'AREA_TITLE', 'OCC_CODE', 'OCC_TITLE', 'TOT_EMP', 'A_MEDIAN'}
    if not required.issubset(df.columns):
        raise ValueError(f'Unexpected OEWS columns. Missing {sorted(required - set(df.columns))}; available {list(df.columns)}')
    # State file: AREA 18 is Indiana; guard against metropolitan and national rows.
    indiana = df[df['AREA'].astype(str).str.strip().str.replace(r'\.0$', '', regex=True).eq('18')].copy()
    if 'AREA_TYPE' in indiana.columns:
        indiana = indiana[indiana['AREA_TYPE'].astype(str).str.strip().isin(['2', '2.0'])]
    if indiana.empty:
        raise ValueError('No Indiana state rows found; inspect AREA and AREA_TYPE values.')
    if not indiana['AREA_TITLE'].astype(str).str.contains('Indiana', case=False, na=False).all():
        raise ValueError('AREA=18 contains unexpected geography labels.')
    fields = ['TOT_EMP', 'H_MEAN', 'A_MEAN', 'H_MEDIAN', 'A_MEDIAN', 'A_PCT10', 'A_PCT25', 'A_PCT75', 'A_PCT90']
    for field in fields:
        if field not in indiana:
            indiana[field] = None
    def number(v):
        if v is None or pd.isna(v): return None
        v = str(v).strip().replace(',', '').replace('$', '')
        if v in ('', '*', '**', '#', '-', 'N/A', 'nan'): return None
        try: return float(v)
        except ValueError: raise ValueError(f'Unexpected numeric marker: {v!r}')
    result = []
    for row in indiana.to_dict('records'):
        code = str(row['OCC_CODE']).strip()
        if not code or code.lower() == 'nan': continue
        values = {f: number(row.get(f)) for f in fields}
        result.append((code, str(row['OCC_TITLE']).strip(), str(row.get('OCC_GROUP') or '').strip(), values, json.dumps({k: None if pd.isna(v) else str(v) for k,v in row.items()}, ensure_ascii=False)))
    keys = [x[0] for x in result]
    if len(keys) != len(set(keys)):
        raise ValueError('Duplicate occupation codes in Indiana state dataset; refusing ambiguous load.')
    if len(result) < 100:
        raise ValueError(f'Unexpectedly few Indiana occupations ({len(result)}).')
    LOG.info('Indiana occupation rows: %s', len(result))
    return result




def ingest(cur, rows, sha, source):
    stats = {'bronze':0, 'silver':0, 'gold':0}
    for code, title, group, values, raw in rows:
        cur.execute('SELECT RawID, RawJSON, SourceSHA256 FROM bronze.BLS_OEWS_Raw WHERE ReferenceYear=? AND AreaCode=? AND OccupationCode=?', YEAR, '18', code)
        existing = cur.fetchone()
        if existing is None:
            cur.execute('INSERT INTO bronze.BLS_OEWS_Raw (ReferenceYear,AreaCode,OccupationCode,OccupationTitle,RawJSON,SourceURL,SourceSHA256) VALUES (?,?,?,?,?,?,?)', YEAR,'18',code,title,raw,source,sha)
            stats['bronze'] += 1
        elif existing[1] != raw or existing[2] != sha:
            cur.execute('UPDATE bronze.BLS_OEWS_Raw SET OccupationTitle=?,RawJSON=?,SourceURL=?,SourceSHA256=?,IngestedAt=SYSUTCDATETIME() WHERE RawID=?',title,raw,source,sha,existing[0])
        cur.execute('SELECT RawID FROM bronze.BLS_OEWS_Raw WHERE ReferenceYear=? AND AreaCode=? AND OccupationCode=?',YEAR,'18',code)
        raw_id = cur.fetchone()[0]
        vals = [values[k] for k in ('TOT_EMP','H_MEAN','A_MEAN','H_MEDIAN','A_MEDIAN','A_PCT10','A_PCT25','A_PCT75','A_PCT90')]
        cur.execute('SELECT SilverID FROM silver.BLS_OEWS_Indiana WHERE ReferenceYear=? AND OccupationCode=?',YEAR,code)
        s = cur.fetchone()
        if s is None:
            cur.execute('''INSERT INTO silver.BLS_OEWS_Indiana (RawID,ReferenceYear,OccupationCode,OccupationTitle,OccupationGroup,EmploymentEstimate,MeanHourlyWage,MeanAnnualWage,MedianHourlyWage,MedianAnnualWage,AnnualP10,AnnualP25,AnnualP75,AnnualP90)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)''',raw_id,YEAR,code,title,group,*vals)
            stats['silver'] += 1
        else:
            cur.execute('''UPDATE silver.BLS_OEWS_Indiana SET OccupationTitle=?,OccupationGroup=?,EmploymentEstimate=?,MeanHourlyWage=?,MeanAnnualWage=?,MedianHourlyWage=?,MedianAnnualWage=?,AnnualP10=?,AnnualP25=?,AnnualP75=?,AnnualP90=? WHERE SilverID=?''',title,group,*vals,s[0])
        cur.execute('SELECT SilverID FROM silver.BLS_OEWS_Indiana WHERE ReferenceYear=? AND OccupationCode=?',YEAR,code)
        silver_id = cur.fetchone()[0]
        cur.execute('SELECT OccupationKey FROM gold.Dim_Occupation WHERE OccupationCode=?',code)
        o = cur.fetchone()
        if o is None:
            cur.execute('INSERT INTO gold.Dim_Occupation (OccupationCode,OccupationTitle,OccupationGroup) VALUES (?,?,?)',code,title,group)
        else:
            cur.execute('UPDATE gold.Dim_Occupation SET OccupationTitle=?,OccupationGroup=? WHERE OccupationKey=?',title,group,o[0])
        cur.execute('SELECT OccupationKey FROM gold.Dim_Occupation WHERE OccupationCode=?',code)
        occ_key = cur.fetchone()[0]
        goldvals = [values[k] for k in ('TOT_EMP','A_MEAN','A_MEDIAN','A_PCT10','A_PCT25','A_PCT75','A_PCT90')]
        cur.execute('SELECT FactKey FROM gold.Fact_OccupationalWages WHERE SilverID=?',silver_id)
        f = cur.fetchone()
        if f is None:
            cur.execute('''INSERT INTO gold.Fact_OccupationalWages (SilverID,OccupationKey,ReferenceYear,GeographyCode,EmploymentEstimate,MeanAnnualWage,MedianAnnualWage,AnnualP10,AnnualP25,AnnualP75,AnnualP90) VALUES (?,?,?,?,?,?,?,?,?,?,?)''',silver_id,occ_key,YEAR,'18',*goldvals)
            stats['gold'] += 1
        else:
            cur.execute('''UPDATE gold.Fact_OccupationalWages SET EmploymentEstimate=?,MeanAnnualWage=?,MedianAnnualWage=?,AnnualP10=?,AnnualP25=?,AnnualP75=?,AnnualP90=? WHERE FactKey=?''',*goldvals,f[0])
    for table in ['bronze.BLS_OEWS_Raw','silver.BLS_OEWS_Indiana','gold.Fact_OccupationalWages']:
        cur.execute(f'SELECT COUNT(*) FROM {table} WHERE ReferenceYear=?',YEAR)
        count = cur.fetchone()[0]
        if count != len(rows):
            raise ValueError(f'Validation failed: {table} contains {count}, expected {len(rows)}')
    cur.execute('''SELECT COUNT(*) FROM gold.Fact_OccupationalWages g LEFT JOIN silver.BLS_OEWS_Indiana s ON s.SilverID=g.SilverID WHERE g.ReferenceYear=? AND (s.SilverID IS NULL OR (g.MedianAnnualWage<>s.MedianAnnualWage) OR (g.MedianAnnualWage IS NULL AND s.MedianAnnualWage IS NOT NULL) OR (g.MedianAnnualWage IS NOT NULL AND s.MedianAnnualWage IS NULL))''',YEAR)
    mismatches = cur.fetchone()[0]
    if mismatches: raise ValueError(f'Gold/Silver wage mismatch: {mismatches}')
    return stats


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--file',help='Optional local BLS ZIP or XLSX when direct download is blocked')
    args=parser.parse_args()
    logging.basicConfig(level=logging.INFO, format='%(levelname)s %(message)s')
    workbook,sha,source=get_workbook(args.file)
    rows=normalize_frame(workbook)
    server=os.getenv('SQL_SERVER','Matt'); database=os.getenv('SQL_DATABASE','IndianaWorkforceDW')
    connstr=(f'DRIVER={{ODBC Driver 18 for SQL Server}};SERVER={server};DATABASE={database};'
             'Trusted_Connection=yes;Encrypt=yes;TrustServerCertificate=yes;')
    LOG.info('Connecting to %s / %s',server,database)
    with pyodbc.connect(connstr,autocommit=False,timeout=20) as conn:
        cur=conn.cursor()
        try:
            for table in ['bronze.BLS_OEWS_Raw', 'silver.BLS_OEWS_Indiana', 'gold.Dim_Occupation', 'gold.Fact_OccupationalWages']:
                if cur.execute("SELECT OBJECT_ID(?, 'U')", table).fetchone()[0] is None:
                    raise RuntimeError(f"Missing or inaccessible prerequisite: {table}")
            stats=ingest(cur,rows,sha,source)
            conn.commit()
        except Exception:
            conn.rollback()
            raise
    print('\n=== BLS OEWS INGESTION SUCCESS ===')
    print(f'Source: {source}\nReference year: {YEAR}\nIndiana occupations: {len(rows)}')
    for key,value in stats.items():print(f'{key.title()} new rows: {value}')
    print('Validation: Bronze/Silver/Gold counts matched; wage lineage reconciled')
    print('Rerun to test duplicate prevention (new rows should be zero).')


if __name__=='__main__':
    try: main()
    except Exception:
        LOG.exception('BLS OEWS ingestion failed')
        raise SystemExit(1)
