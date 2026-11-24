import argparse, csv, hashlib, json, re
from pathlib import Path
import pyodbc


def main():
    p=argparse.ArgumentParser()
    p.add_argument('--file', required=True, type=Path)
    p.add_argument('--base-year', type=int, default=None, help='Supply only after verifying source metadata')
    args=p.parse_args()
    sha=hashlib.sha256(args.file.read_bytes()).hexdigest()
    with args.file.open(encoding='utf-8-sig', newline='') as f:
        reader=csv.reader(f)
        assert next(reader)==['Long Term Occupational Projections']
        header=next(reader)
        if header != ['Geography','statefips','countyfips','year','Occ. Title/Code','Occ. Title/Code','Base Year Emp.','Projected Year Emp.']:
            raise ValueError('Unexpected source header')
        rows=[]; seen=set()
        for line,r in enumerate(reader,3):
            if not r or not any(r): continue
            if len(r)==1 and r[0].startswith('This table was produced by'): continue
            if len(r)!=8: raise ValueError(f'Unexpected row {line}')
            geo,state,county,year,title,code,base,future=[x.strip() for x in r]
            if (state,county)!=('18','000') or not re.fullmatch(r'\d{6}',code): raise ValueError(f'Invalid geography/code at {line}')
            code=code[:2]+'-'+code[2:]; year=int(year); base=int(base); future=int(future)
            if min(base,future)<0 or (year,code) in seen or (args.base_year is not None and args.base_year>=year): raise ValueError(f'Invalid observation at {line}')
            seen.add((year,code)); rows.append((year,code,title,base,future,json.dumps(r,ensure_ascii=False)))
    if not rows: raise ValueError('No records')
    print(f'Validated source rows: {len(rows)}')
    con=pyodbc.connect('DRIVER={ODBC Driver 18 for SQL Server};SERVER=Matt;DATABASE=IndianaWorkforceDW;Trusted_Connection=yes;Encrypt=yes;TrustServerCertificate=yes;',autocommit=False)
    try:
        c=con.cursor()
        for table in ['bronze.IDWD_Projection_Raw', 'silver.IDWD_OccupationalProjection', 'gold.Fact_OccupationalProjection', 'gold.Dim_Occupation', 'gold.Fact_OccupationalWages']:
            if c.execute("SELECT OBJECT_ID(?, 'U')", table).fetchone()[0] is None:
                raise RuntimeError(f"Missing or inaccessible prerequisite: {table}")
        counts=[0,0,0]; matched=0
        for year,code,title,base,future,raw in rows:
            c.execute('SELECT RawID FROM bronze.IDWD_Projection_Raw WHERE ProjectionYear=? AND OccupationCode=?',year,code)
            r=c.fetchone()
            if not r:
                c.execute('INSERT INTO bronze.IDWD_Projection_Raw(ProjectionYear,OccupationCode,RawJSON,SourceFile,SourceSHA256) OUTPUT INSERTED.RawID VALUES(?,?,?,?,?)',year,code,raw,args.file.name,sha); rid=c.fetchone()[0]; counts[0]+=1
            else:
                rid=r[0]; c.execute('UPDATE bronze.IDWD_Projection_Raw SET RawJSON=?,SourceFile=?,SourceSHA256=? WHERE RawID=?',raw,args.file.name,sha,rid)
            c.execute('SELECT SilverID FROM silver.IDWD_OccupationalProjection WHERE RawID=?',rid); r=c.fetchone()
            if not r:
                c.execute('INSERT INTO silver.IDWD_OccupationalProjection(RawID,ProjectionYear,BaseYear,OccupationCode,OccupationTitle,BaseEmployment,ProjectedEmployment) OUTPUT INSERTED.SilverID VALUES(?,?,?,?,?,?,?)',rid,year,args.base_year,code,title,base,future); sid=c.fetchone()[0]; counts[1]+=1
            else:
                sid=r[0]; c.execute('UPDATE silver.IDWD_OccupationalProjection SET BaseYear=COALESCE(?,BaseYear),OccupationTitle=?,BaseEmployment=?,ProjectedEmployment=? WHERE SilverID=?',args.base_year,title,base,future,sid)
            c.execute('SELECT OccupationKey FROM gold.Dim_Occupation WHERE OccupationCode=?',code); r=c.fetchone()
            if not r:
                c.execute('INSERT INTO gold.Dim_Occupation(OccupationCode,OccupationTitle) OUTPUT INSERTED.OccupationKey VALUES(?,?)',code,title); key=c.fetchone()[0]
            else: key=r[0]
            c.execute("SELECT 1 FROM gold.Fact_OccupationalWages WHERE OccupationKey=? AND GeographyCode='18' AND ReferenceYear=2025",key)
            matched+=int(c.fetchone() is not None)
            c.execute('SELECT FactKey FROM gold.Fact_OccupationalProjection WHERE SilverID=?',sid); r=c.fetchone()
            if not r:
                c.execute("INSERT INTO gold.Fact_OccupationalProjection(SilverID,OccupationKey,GeographyCode,BaseYear,ProjectionYear,BaseEmployment,ProjectedEmployment) VALUES(?,?,'18',?,?,?,?)",sid,key,args.base_year,year,base,future); counts[2]+=1
            else:
                c.execute('UPDATE gold.Fact_OccupationalProjection SET BaseYear=COALESCE(?,BaseYear),BaseEmployment=?,ProjectedEmployment=? WHERE FactKey=?',args.base_year,base,future,r[0])
        for year in {r[0] for r in rows}:
            expected=sum(r[0]==year for r in rows)
            for table in ('bronze.IDWD_Projection_Raw','silver.IDWD_OccupationalProjection','gold.Fact_OccupationalProjection'):
                c.execute(f'SELECT COUNT(*) FROM {table} WHERE ProjectionYear=?',year)
                if c.fetchone()[0]!=expected: raise ValueError(f'Count mismatch: {table}')
        c.execute('''SELECT COUNT(*) FROM gold.Fact_OccupationalProjection g JOIN silver.IDWD_OccupationalProjection s ON s.SilverID=g.SilverID JOIN gold.Dim_Occupation d ON d.OccupationKey=g.OccupationKey WHERE g.BaseEmployment<>s.BaseEmployment OR g.ProjectedEmployment<>s.ProjectedEmployment OR d.OccupationCode<>s.OccupationCode''')
        if c.fetchone()[0]: raise ValueError('Gold reconciliation failed')
        con.commit()
        print('=== IDWD PROJECTION INGESTION SUCCESS ===')
        for layer,n in zip(('Bronze','Silver','Gold'),counts): print(f'{layer} new rows: {n}')
        print(f'Exact SOC matches to 2025 OEWS: {matched}/{len(rows)} (code matches, not verified taxonomy equivalence)')
        print('Validation passed; gold.vw_OccupationalOpportunity available')
    except Exception:
        con.rollback(); raise
    finally: con.close()

if __name__=='__main__': main()
