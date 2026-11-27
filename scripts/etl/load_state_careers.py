import argparse,csv,json,re,hashlib
from pathlib import Path
from datetime import datetime,timezone,timedelta
from decimal import Decimal

def utc(s):
    return datetime.fromisoformat(s.replace('Z','+00:00')).astimezone(timezone.utc).replace(tzinfo=None)
def dump(x): return json.dumps(x,ensure_ascii=False,sort_keys=True)
def salary(s):
    m=re.fullmatch(r'\s*\$([\d,]+(?:\.\d{1,2})?)\s*(/hr|/hour|per hour|/year|annually)?\s*',s or '',re.I)
    if not m:return None,'UNKNOWN',None
    a=Decimal(m[1].replace(',','')); f='HOURLY' if m[2] and 'hour' in m[2].lower() or m[2]=='/hr' else 'ANNUAL' if m[2] else 'UNKNOWN'
    return a,f,a*2080 if f=='HOURLY' else a if f=='ANNUAL' else None

def main():
    p=argparse.ArgumentParser();p.add_argument('--root',default=r'C:\Projects\IndianaWorkforceIntelligence');p.add_argument('--commit',action='store_true');a=p.parse_args()
    root=Path(a.root); raw=root/'data/raw/state_careers'; stamp='20261127T035743Z'
    with (raw/f'state_careers_listings_{stamp}.csv').open(encoding='utf-8-sig',newline='') as f: rows=list(csv.DictReader(f))
    ids={r['SourcePostingID'] for r in rows}; assert len(rows)==len(ids)==468
    details={}
    for name in ('details','recovery'):
        for line in (raw/f'state_careers_{name}_{stamp}.jsonl').read_text(encoding='utf-8-sig').splitlines():
            if not line.strip():continue
            r=json.loads(line); k=r['SourcePostingID']; assert k in ids and k not in details; details[k]=r
    assert set(details)==ids
    for r in details.values():
        assert r.get('JobDescriptionRaw') and (root/r['HTMLPath']).is_file()
    import pyodbc
    cn=pyodbc.connect('DRIVER={ODBC Driver 18 for SQL Server};SERVER=Matt;DATABASE=IndianaWorkforceDW;Trusted_Connection=yes;Encrypt=yes;TrustServerCertificate=yes;',autocommit=False)
    c=cn.cursor()
    def ins(table,d,identity=None):
        sql='INSERT INTO '+table+' ('+','.join(d)+') '+('OUTPUT INSERTED.'+identity+' ' if identity else '')+'VALUES ('+','.join('?' for _ in d)+')'
        c.execute(sql,*d.values());return c.fetchone()[0] if identity else None
    def dim(table,key,col,value,extra={}):
        c.execute(f'SELECT {key} FROM {table} WHERE {col}=?',value); x=c.fetchone()
        return x[0] if x else ins(table,{col:value,**extra},key)
    try:
        c.execute('SET XACT_ABORT ON; SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;')
        c.execute('SELECT CollectionID FROM bronze.StateCareers_Collection WHERE SourceCollectionKey=?',stamp)
        if c.fetchone(): print('Already ingested; no changes.');return
        c.execute('SELECT COUNT(*) FROM silver.StateCareers_JobPosting');assert c.fetchone()[0]==0,'Baseline loader requires empty recruitment inventory'
        start=datetime.strptime(stamp,'%Y%m%dT%H%M%SZ'); day=(start-timedelta(hours=5)).date()
        cid=ins('bronze.StateCareers_Collection',dict(SourceCollectionKey=stamp,CollectionDate=day,StartedUTC=start,CompletedUTC=max(utc(r['DetailRetrievedUTC']) for r in details.values()),SourceURL='https://workforindiana.in.gov/search/',ReportedPostings=468,RetrievedPostings=468,DetailsRetrieved=468,CollectionStatus='SUCCEEDED',IsListingComplete=1,IsDetailComplete=1),'CollectionID')
        for listing in rows:
            r={**listing,**details[listing['SourcePostingID']]}; seen=utc(listing['CollectionUTC']); h=hashlib.sha256(dump({k:v for k,v in r.items() if k not in ('CollectionUTC','DetailRetrievedUTC','HTMLPath')}).encode()).digest()
            rawid=ins('bronze.StateCareers_Raw',dict(CollectionID=cid,SourcePostingID=r['SourcePostingID'],RequisitionIDRaw=r.get('RequisitionID'),JobTitleRaw=r['JobTitle'],LocationRaw=r['Location'],AgencyRaw=r.get('AgencyRaw'),MinimumSalaryRaw=r.get('MinimumSalaryRaw'),DatePostedRaw=r['DatePosted'],AgencyEvidence=r.get('AgencyEvidence'),JobDescriptionRaw=r['JobDescriptionRaw'],ResponsibilitiesRaw=r.get('ResponsibilitiesRaw'),QualificationsRaw=r.get('QualificationsRaw'),JobURL=r['JobURL'],DetailStatus=r['DetailStatus'],CollectionUTC=seen,RecordHash=h,RawPayloadJSON=dump(r),HTMLPath=r['HTMLPath'],DetailRetrievedUTC=utc(r['DetailRetrievedUTC']),DescriptionScope=r.get('DescriptionScope')),'RawID')
            date=None
            for fmt in ('%b %d, %Y','%B %d, %Y','%m/%d/%Y','%Y-%m-%d'):
                try:date=datetime.strptime(r['DatePosted'],fmt).date();break
                except ValueError:pass
            loc=re.fullmatch(r'(.+?),\s*([A-Z]{2}),\s*US,?\s*(\d{5}(?:-\d{4})?)?',r['Location']); agency=r.get('AgencyRaw') or None
            amount,freq,annual=salary(r.get('MinimumSalaryRaw')); special=r.get('RequisitionID')=='469668'
            if special: amount,freq,annual=Decimal('12.65'),'HOURLY',Decimal('26312')
            jid=ins('silver.StateCareers_JobPosting',dict(SourcePostingID=r['SourcePostingID'],RequisitionID=r.get('RequisitionID') or None,JobTitle=r['JobTitle'],AgencyRaw=agency,AgencyName=agency,City=loc[1] if loc else None,StateCode=loc[2] if loc else None,ZIPCode=loc[3] if loc else None,MinimumSalaryRaw=r.get('MinimumSalaryRaw'),SalaryAmount=amount,SalaryFrequency=freq,AnnualizedSalary=annual,AnnualizationHours=2080 if freq=='HOURLY' else None,JobDescription=r['JobDescriptionRaw'],Responsibilities=r.get('ResponsibilitiesRaw'),Qualifications=r.get('QualificationsRaw'),EducationRequirements=dump(r.get('EducationEvidence',[])),ExperienceRequirements=dump(r.get('ExperienceEvidence',[])),CertificationRequirements=dump(r.get('CertificationEvidence',[])),DatePosted=date,FirstSeenUTC=seen,LastSeenUTC=seen,IsActive=1,AgencyMappingStatus='REVIEW_REQUIRED',GeographyMappingStatus='PENDING',OccupationMappingStatus='PENDING',SalaryValidationStatus='VALIDATED' if annual is not None else 'REVIEW_REQUIRED',DetailStatus=r['DetailStatus'],JobURL=r['JobURL'],RecordHash=h,LatestRawID=rawid),'JobPostingID')
            ak=dim('gold.Dim_Agency','AgencyKey','AgencyName',agency) if agency else None
            fact=ins('gold.Fact_StateJobPosting',dict(JobPostingID=jid,AgencyKey=ak,DatePosted=date,SalaryAmount=amount,AnnualizedSalary=annual,SalaryFrequency=freq,FirstSeenUTC=seen,LastSeenUTC=seen,IsActive=1),'PostingFactKey')
            for comp in r.get('CompensationCandidates',[]):
                val=Decimal(comp['amount']); frequency=comp['frequency']; context=comp.get('context',''); role=None; hiring=None
                if special:
                    for label,price in [('Cook/Baker/Kitchen Prep',Decimal('15')),('Dishwasher/Kitchen Helper',Decimal('12.65'))]:
                        if val==price and label+':' in context and context.index(label+':')<context.find(comp['evidence']):role=label;hiring=1;break
                ins('silver.StateCareers_JobCompensation',dict(JobPostingID=jid,SourceRawID=rawid,RoleName=role,SalaryAmount=val,SalaryFrequency=frequency,AnnualizedSalary=val*2080 if frequency=='HOURLY' else val if frequency=='ANNUAL' else None,AnnualizationHours=2080 if frequency=='HOURLY' else None,TipsEligible=1 if 'eligible to receive tips' in comp['evidence'].lower() else None,IsExplicitlyHiring=hiring,SalaryEvidence=comp['evidence'],ContextEvidence=context,ExtractionMethod='CONTEXT_CANDIDATE',ExtractionVersion='3.0',ValidationStatus='REVIEW_REQUIRED'))
            skills={}
            for sk in r.get('SkillCandidates',[]):skills.setdefault(sk['skill'],[]).append(sk['evidence'])
            for name,evidence in skills.items():
                ins('silver.StateCareers_JobSkill',dict(JobPostingID=jid,SkillName=name,RequirementType='UNSPECIFIED',EvidenceText='\n'.join(dict.fromkeys(evidence)),ExtractionMethod='KEYWORD',ExtractionVersion='3.0'))
                skey=dim('gold.Dim_Skill','SkillKey','SkillName',name)
                ins('gold.Bridge_JobPostingSkill',dict(PostingFactKey=fact,SkillKey=skey,RequirementType='UNSPECIFIED'))
        ins('gold.Fact_RecruitmentDaily',dict(ObservationDate=day,CollectionID=cid,AdvertisedPostings=468,NewlyObservedPostings=468,NoLongerObservedPostings=0,ReactivatedPostings=0,CumulativeUniquePostings=468))
        for table in ('bronze.StateCareers_Raw','silver.StateCareers_JobPosting','gold.Fact_StateJobPosting','silver.StateCareers_JobCompensation','silver.StateCareers_JobSkill','gold.Bridge_JobPostingSkill','gold.Fact_RecruitmentDaily'):
            c.execute('SELECT COUNT(*) FROM '+table); n=c.fetchone()[0];print(table,n)
            if table in ('bronze.StateCareers_Raw','silver.StateCareers_JobPosting','gold.Fact_StateJobPosting'):assert n==468
        if a.commit:cn.commit();print('COMMITTED baseline historical observation',day)
        else:cn.rollback();print('DRY RUN PASSED: transaction rolled back')
    finally:cn.close()
if __name__=='__main__':main()
