"""Read-only SQL inventory comparison; fresh source collection to local evidence files."""
import json, re, os
from datetime import datetime, timezone, timedelta
from pathlib import Path
import pyodbc
import ingest_state_careers_v3 as v3

FIELDS=('JobTitle','Location','MinimumSalaryRaw','DatePosted','JobURL')
CONN='DRIVER={ODBC Driver 18 for SQL Server};SERVER=Matt;DATABASE=IndianaWorkforceDW;Trusted_Connection=yes;Encrypt=yes;TrustServerCertificate=yes;'

def inventory():
    cn=pyodbc.connect(CONN)
    try:
        rows=cn.cursor().execute('''SELECT s.SourcePostingID,s.IsActive,l.RawPayloadJSON,b.DetailRetrievedUTC,s.DetailStatus
        FROM silver.StateCareers_JobPosting s
        JOIN bronze.StateCareers_Raw b ON b.RawID=s.LatestRawID
        JOIN bronze.StateCareers_Raw l ON l.RawID=s.LatestListingRawID''').fetchall()
        return {r[0]:(bool(r[1]),json.loads(r[2]),r[3],r[4]) for r in rows}
    finally: cn.close()

def page_count(text):
    m = re.search(
        r'Results\s+([\d,]+)\s*[^\d\s]{1,12}\s*([\d,]+)\s+of\s+([\d,]+)',
        text, re.I
    )
    if not m:
        raise ValueError('Unrecognized search count; no complete scan')
    return tuple(int(x.replace(',', '')) for x in m.groups())

def reason(row, old, now):
    if old is None:return 'NEW'
    active,previous,retrieved,status=old
    if not active:return 'REACTIVATED'
    if any(row.get(k)!=previous.get(k) for k in FIELDS):return 'UPDATED'
    if not retrieved or status!='COMPLETE':return 'RETRY_DETAIL'
    if now-retrieved>=timedelta(days=7):return 'PERIODIC_RECHECK'
    return 'UNCHANGED'

def main():
    start=datetime.now(timezone.utc); stamp=start.strftime('%Y%m%dT%H%M%SZ'); v3.STAMP=stamp
    old=inventory(); out=v3.OUT; out.mkdir(parents=True,exist_ok=True)
    folder=out/('daily_'+stamp); folder.mkdir()
    v3.init_network()
    params=dict(q='',sortColumn='referencedate',sortDirection='desc',searchby='location',locationsearch='',startrow=0)
    records={}; offset=0; expected=None; size=None
    while True:
        params['startrow']=offset
        content=v3.fetch(v3.SEARCH,params); (folder/f'listing_{offset}.html').write_bytes(content)
        rows,text=v3.get_listings(content); first,last,total=page_count(text)
        if expected is None: expected=total; size=len(rows)
        if not size or total!=expected or first!=offset+1 or last!=offset+len(rows) or len(rows)!=min(size,expected-offset):raise ValueError('Pagination inconsistent; collection rejected')
        for r in rows:
            k=r['SourcePostingID']
            if k in records:raise ValueError('Duplicate listing ID; collection rejected')
            records[k]=r
        print(f'Listings {len(records)}/{expected}',flush=True)
        offset+=len(rows)
        if offset==expected:break
    v3.atomic_csv(folder/'listings.csv',list(records.values()))
    from collections import Counter
    plan={k:reason(r,old.get(k),start.replace(tzinfo=None)) for k,r in records.items()}
    print('Plan:',dict(Counter(plan.values())),flush=True)
    print('No longer observed:',sum(k not in records and x[0] for k,x in old.items()),flush=True)
    stop=None; outcomes={}
    order={'NEW':0,'REACTIVATED':1,'UPDATED':2,'RETRY_DETAIL':3,'PERIODIC_RECHECK':4,'UNCHANGED':5}
    with (folder/'details.jsonl').open('x',encoding='utf-8') as f:
        for k in sorted(records,key=lambda k:order[plan[k]]):
            if plan[k]=='UNCHANGED':continue
            try:r=v3.enrich(dict(records[k]))
            except v3.Unavailable as e:r=dict(SourcePostingID=k,DetailStatus='DETAIL_UNAVAILABLE',Error=str(e))
            except ValueError as e:r=dict(SourcePostingID=k,DetailStatus='DETAIL_REVIEW',Error=str(e))
            except (v3.StopCollection,KeyboardInterrupt) as e:stop=str(e) or 'Interrupted';break
            r['AttemptUTC']=v3.now(); outcomes[k]=r['DetailStatus']; f.write(json.dumps(r,ensure_ascii=False)+'\n');f.flush();os.fsync(f.fileno())
            print(k,r['DetailStatus'],flush=True)
    manifest=dict(collection_key=stamp,started_utc=start.isoformat(),completed_utc=v3.now(),reported=expected,retrieved=len(records),listing_complete=True,plan=plan,detail_outcomes=outcomes,stop=stop)
    tmp=folder/'manifest.tmp';tmp.write_text(json.dumps(manifest,indent=2),encoding='utf-8');tmp.replace(folder/'manifest.json')
    print('Collection folder:',folder);print('Detail outcomes:',dict(Counter(outcomes.values())));print('No SQL changes.');return int(bool(stop))

if __name__=='__main__':raise SystemExit(main())
