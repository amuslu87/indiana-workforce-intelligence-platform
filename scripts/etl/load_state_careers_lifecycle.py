"""Transactional daily recruitment ingestion; default rollback. One observation per local day."""
import argparse,csv,json,re,hashlib
from pathlib import Path
from datetime import datetime,timedelta
from zoneinfo import ZoneInfo
from decimal import Decimal
from collections import Counter
from load_state_careers import utc,dump,salary
ROOT=Path(__file__).resolve().parents[2]
FIELDS=('JobTitle','Location','MinimumSalaryRaw','DatePosted','JobURL')
S='silver.StateCareers_JobPosting'; B='bronze.StateCareers_Raw'; G='gold.Fact_StateJobPosting'; C='bronze.StateCareers_Collection'
def require(ok,msg):
    if not ok: raise ValueError(msg)
def classify(rows,old):
    return {k: 'NEW' if k not in old else 'REACTIVATED' if not old[k][1] else 'UPDATED' if any(r.get(f)!=old[k][2].get(f) for f in FIELDS) else 'UNCHANGED' for k,r in rows.items()}
def main():
    p=argparse.ArgumentParser();p.add_argument('--collection',required=True);p.add_argument('--commit',action='store_true');p.add_argument('--test-next-day',action='store_true');a=p.parse_args()
    require(not(a.commit and a.test_next_day),'Synthetic test cannot commit')
    require(re.fullmatch(r'\d{8}T\d{6}Z',a.collection),'Invalid key')
    folder=ROOT/'data/raw/state_careers'/('daily_'+a.collection)
    m=json.loads((folder/'manifest.json').read_text(encoding='utf-8-sig'))
    with (folder/'listings.csv').open(encoding='utf-8-sig',newline='') as f: listings=list(csv.DictReader(f))
    rows={r['SourcePostingID']:r for r in listings}; details={}
    for line in (folder/'details.jsonl').read_text(encoding='utf-8-sig').splitlines():
        if not line.strip():continue
        d=json.loads(line);k=d['SourcePostingID'];require(k in rows and k not in details,'Invalid detail ID');details[k]=d
        if d.get('HTMLPath'):require((ROOT/d['HTMLPath']).is_file(),'Missing HTML evidence')
    require(m['collection_key']==a.collection and m['listing_complete'] is True and not m['stop'],'Incomplete collection')
    require(len(rows)==len(listings)==m['reported']==m['retrieved'] and len(rows)>0,'Listing count mismatch')
    require(set(m['plan'])==set(rows) and {k:d['DetailStatus'] for k,d in details.items()}==m['detail_outcomes'],'Manifest mismatch')
    start=utc(m['started_utc']);end=utc(m['completed_utc']);day=datetime.fromisoformat(m['started_utc']).astimezone(ZoneInfo('America/Indiana/Indianapolis')).date();key=a.collection
    import pyodbc
    cn=pyodbc.connect('DRIVER={ODBC Driver 18 for SQL Server};SERVER=Matt;DATABASE=IndianaWorkforceDW;Trusted_Connection=yes;Encrypt=yes;TrustServerCertificate=yes;',autocommit=False);c=cn.cursor()
    def ins(t,d,id=None):
        c.execute('INSERT INTO '+t+' ('+','.join(d)+') '+('OUTPUT INSERTED.'+id+' ' if id else '')+'VALUES ('+','.join('?' for _ in d)+')',*d.values());return c.fetchone()[0] if id else None
    def upd(t,d,col,k):c.execute('UPDATE '+t+' SET '+','.join(x+'=?' for x in d)+' WHERE '+col+'=?',*d.values(),k)
    def dim(t,id,col,v):
        x=c.execute(f'SELECT {id} FROM {t} WHERE {col}=?',v).fetchone();return x[0] if x else ins(t,{col:v},id)
    try:
        c.execute('SET XACT_ABORT ON; SET QUOTED_IDENTIFIER ON; SET ANSI_NULLS ON; SET ANSI_PADDING ON; SET ANSI_WARNINGS ON; SET CONCAT_NULL_YIELDS_NULL ON; SET ARITHABORT ON; SET NUMERIC_ROUNDABORT OFF; SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;')
        c.execute("DECLARE @r int; EXEC @r=sp_getapplock @Resource='RecruitmentIngestion',@LockMode='Exclusive',@LockOwner='Transaction',@LockTimeout=10000; IF @r<0 THROW 51000,'Lock failed',1;")
        latest=c.execute(f'SELECT MAX(CollectionDate),MAX(StartedUTC) FROM {C} WHERE IsListingComplete=1').fetchone()
        old={r[0]:(r[1],bool(r[2]),json.loads(r[3])) for r in c.execute(f'SELECT s.SourcePostingID,s.JobPostingID,s.IsActive,b.RawPayloadJSON FROM {S} s JOIN {B} b ON b.RawID=s.LatestListingRawID').fetchall()}
        require(len(old)==c.execute(f'SELECT COUNT(*) FROM {S}').fetchone()[0],'Missing listing lineage')
        if a.test_next_day:
            require(len(rows)>4 and set(rows)==set(old),'Test requires matching baseline inventory')
            day=latest[0]+timedelta(days=1);start=latest[1]+timedelta(days=1);end=start;key='TEST_'+a.collection
            k1,k2,k3,k4=sorted(rows)[:4]; rows.pop(k1);details.pop(k1,None)
            rows[k2]=dict(rows[k2],JobTitle=rows[k2]['JobTitle']+' TEST');details.pop(k2,None)
            upd(S,dict(IsActive=0,FirstNotSeenUTC=start),'JobPostingID',old[k3][0]);old[k3]=(old[k3][0],False,old[k3][2])
            rows['TEST_NEW']=dict(rows[k4],SourcePostingID='TEST_NEW');details.pop(k3,None)
        if c.execute(f'SELECT CollectionID FROM {C} WHERE SourceCollectionKey=?',key).fetchone():print('Already ingested; no changes.');return
        require(latest[0] is None or (day>latest[0] and start>latest[1]),'Same-day or older collection rejected')
        plan=classify(rows,old);removed={k for k,v in old.items() if v[1] and k not in rows};counts=Counter(plan.values());print('Lifecycle:',dict(counts),'REMOVED:',len(removed))
        complete=all(details.get(k,{}).get('DetailStatus')=='COMPLETE' for k in rows if plan[k]!='UNCHANGED' or m['plan'].get(k)!='UNCHANGED')
        cid=ins(C,dict(CollectionDate=day,StartedUTC=start,CompletedUTC=end,SourceURL='https://workforindiana.in.gov/search/',ReportedPostings=len(rows),RetrievedPostings=len(rows),DetailsRetrieved=sum(bool(d.get('JobDescriptionRaw')) for d in details.values()),CollectionStatus='SUCCEEDED' if complete else 'PARTIAL',IsListingComplete=1,IsDetailComplete=int(complete),SourceCollectionKey=key),'CollectionID')
        for k,r in rows.items():
            d=details.get(k,{}); payload={**d,**r};payload.update({x:y for x,y in d.items() if x not in FIELDS and x!='SourcePostingID'});status=d.get('DetailStatus','NOT_RECHECKED');good=status=='COMPLETE' and bool(d.get('JobDescriptionRaw')) and bool(d.get('HTMLPath'));h=hashlib.sha256(dump(payload).encode()).digest()
            rid=ins(B,dict(CollectionID=cid,SourcePostingID=k,RequisitionIDRaw=d.get('RequisitionID'),JobTitleRaw=r['JobTitle'],LocationRaw=r['Location'],MinimumSalaryRaw=r['MinimumSalaryRaw'],DatePostedRaw=r['DatePosted'],AgencyRaw=d.get('AgencyRaw'),AgencyEvidence=d.get('AgencyEvidence'),JobDescriptionRaw=d.get('JobDescriptionRaw'),ResponsibilitiesRaw=d.get('ResponsibilitiesRaw'),QualificationsRaw=d.get('QualificationsRaw'),JobURL=r['JobURL'],DetailStatus=status,CollectionUTC=start,RecordHash=h,RawPayloadJSON=dump(payload),HTMLPath=d.get('HTMLPath'),DetailRetrievedUTC=utc(d['DetailRetrievedUTC']) if d.get('DetailRetrievedUTC') else None,DescriptionScope=d.get('DescriptionScope')),'RawID')
            date=None
            for fmt in ('%b %d, %Y','%B %d, %Y','%m/%d/%Y','%Y-%m-%d'):
                try:date=datetime.strptime(r['DatePosted'],fmt).date();break
                except ValueError:pass
            loc=re.fullmatch(r'(.+?),\s*([A-Z]{2}),\s*US,?\s*(\d{5}(?:-\d{4})?)?',r['Location']);new=k not in old;changed=not new and any(r.get(f)!=old[k][2].get(f) for f in FIELDS)
            v=dict(LastSeenUTC=start,IsActive=1,FirstNotSeenUTC=None,LatestListingRawID=rid)
            if new or changed:
                amount,freq,annual=salary(r['MinimumSalaryRaw']);v.update(JobTitle=r['JobTitle'],JobURL=r['JobURL'],DatePosted=date,City=loc[1] if loc else None,StateCode=loc[2] if loc else None,ZIPCode=loc[3] if loc else None,CountyFIPS=None,SOCCode=None,GeographyMappingStatus='PENDING',OccupationMappingStatus='PENDING',MinimumSalaryRaw=r['MinimumSalaryRaw'],SalaryAmount=amount,SalaryFrequency=freq,AnnualizedSalary=annual,AnnualizationHours=2080 if freq=='HOURLY' else None,SalaryValidationStatus='REVIEW_REQUIRED',LastModifiedUTC=start)
            if good or new:
                agency=d.get('AgencyRaw') or None;v.update(RequisitionID=d.get('RequisitionID') or None,AgencyRaw=agency,AgencyName=agency,AgencyMappingStatus='REVIEW_REQUIRED',JobDescription=d.get('JobDescriptionRaw'),Responsibilities=d.get('ResponsibilitiesRaw'),Qualifications=d.get('QualificationsRaw'),EducationRequirements=dump(d.get('EducationEvidence',[])),ExperienceRequirements=dump(d.get('ExperienceEvidence',[])),CertificationRequirements=dump(d.get('CertificationEvidence',[])),LatestRawID=rid,RecordHash=h,DetailStatus=status if d else 'PENDING')
            elif d or changed or plan[k]=='REACTIVATED':v['DetailStatus']=status if d else 'PENDING'
            if new:jid=ins(S,dict(SourcePostingID=k,FirstSeenUTC=start,**v),'JobPostingID');fid=ins(G,dict(JobPostingID=jid,FirstSeenUTC=start,LastSeenUTC=start,IsActive=1),'PostingFactKey')
            else:
                jid=old[k][0];upd(S,v,'JobPostingID',jid);fid=c.execute(f'SELECT PostingFactKey FROM {G} WHERE JobPostingID=?',jid).fetchone()[0]
            if good or new:
                ak=dim('gold.Dim_Agency','AgencyKey','AgencyName',agency) if agency else None;upd(G,dict(AgencyKey=ak),'JobPostingID',jid)
                c.execute('DELETE FROM gold.Bridge_JobPostingSkill WHERE PostingFactKey=?',fid);c.execute('DELETE FROM silver.StateCareers_JobSkill WHERE JobPostingID=?',jid)
                skills={}
                for sk in d.get('SkillCandidates',[]):skills.setdefault(sk['skill'],[]).append(sk['evidence'])
                for name,evidence in skills.items():
                    ins('silver.StateCareers_JobSkill',dict(JobPostingID=jid,SkillName=name,RequirementType='UNSPECIFIED',EvidenceText='\n'.join(dict.fromkeys(evidence)),ExtractionMethod='KEYWORD',ExtractionVersion='3.0'));sk=dim('gold.Dim_Skill','SkillKey','SkillName',name);ins('gold.Bridge_JobPostingSkill',dict(PostingFactKey=fid,SkillKey=sk,RequirementType='UNSPECIFIED'))
            for comp in d.get('CompensationCandidates',[]):
                val=Decimal(comp['amount']);freq=comp['frequency'];ins('silver.StateCareers_JobCompensation',dict(JobPostingID=jid,SourceRawID=rid,SalaryAmount=val,SalaryFrequency=freq,AnnualizedSalary=val*2080 if freq=='HOURLY' else val if freq=='ANNUAL' else None,AnnualizationHours=2080 if freq=='HOURLY' else None,SalaryEvidence=comp['evidence'],ContextEvidence=comp.get('context'),ExtractionMethod='CONTEXT_CANDIDATE',ExtractionVersion='3.0',ValidationStatus='REVIEW_REQUIRED'))
            if changed:upd(G,dict(GeographyKey=None,OccupationKey=None,PeriodKey=None),'JobPostingID',jid)
        for k in removed:upd(S,dict(IsActive=0,FirstNotSeenUTC=start),'JobPostingID',old[k][0])
        c.execute(f'UPDATE f SET IsActive=s.IsActive,LastSeenUTC=s.LastSeenUTC,FirstNotSeenUTC=s.FirstNotSeenUTC,DatePosted=s.DatePosted,SalaryAmount=s.SalaryAmount,AnnualizedSalary=s.AnnualizedSalary,SalaryFrequency=s.SalaryFrequency FROM {G} f JOIN {S} s ON s.JobPostingID=f.JobPostingID')
        total=len(old)+counts['NEW'];ins('gold.Fact_RecruitmentDaily',dict(ObservationDate=day,CollectionID=cid,AdvertisedPostings=len(rows),NewlyObservedPostings=counts['NEW'],NoLongerObservedPostings=len(removed),ReactivatedPostings=counts['REACTIVATED'],CumulativeUniquePostings=total))
        require(c.execute(f'SELECT COUNT(*) FROM {B} WHERE CollectionID=?',cid).fetchone()[0]==len(rows),'Raw reconciliation failed');require(c.execute(f'SELECT COUNT(*) FROM {S} WHERE IsActive=1').fetchone()[0]==len(rows),'Active reconciliation failed');require(c.execute(f'SELECT COUNT(*) FROM {S}').fetchone()[0]==total,'Total reconciliation failed');require(c.execute(f'SELECT COUNT(*) FROM {G}').fetchone()[0]==total,'Gold reconciliation failed')
        print('Reconciliation PASS; active:',len(rows),'historical:',total)
        if a.commit:cn.commit();print('COMMITTED')
        else:cn.rollback();print('DRY RUN PASSED; rolled back')
    finally:cn.rollback();cn.close()
if __name__=='__main__':main()
