import csv, json, re, time, os, argparse
from pathlib import Path
from datetime import datetime, timezone
from urllib.parse import urljoin, urlparse
from urllib.robotparser import RobotFileParser
import requests
from lxml import html
ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'data/raw/state_careers'
BASE = 'https://workforindiana.in.gov'
SEARCH = BASE + '/search/'
AGENT = 'IndianaWorkforceResearch'
def now(): return datetime.now(timezone.utc).isoformat()
class StopCollection(Exception): pass
class Unavailable(Exception): pass
session = requests.Session()
session.headers.update({'User-Agent': AGENT+'/1.0','Accept':'text/html'})
def init_network():
    global rp, delay
    r = session.get(BASE+'/robots.txt', timeout=30, allow_redirects=False)
    if r.status_code != 200: raise StopCollection(f'Robots HTTP {r.status_code}; stop')
    rp = RobotFileParser(); rp.parse(r.text.splitlines())
    delay = max(4, rp.crawl_delay(AGENT) or 0, rp.crawl_delay('*') or 0)
def fetch(url, params=None):
    prepared = requests.Request('GET',url,params=params).prepare().url
    p = urlparse(prepared)
    if p.scheme != 'https' or p.netloc != 'workforindiana.in.gov' or not rp.can_fetch(AGENT,prepared):
        raise StopCollection('URL or robots policy rejected')
    for attempt in range(3):
        time.sleep(delay)
        try:
            r = session.get(prepared, timeout=45, allow_redirects=False)
            if r.status_code in (401,403,429): raise StopCollection(f'HTTP {r.status_code}; stop; Retry-After={r.headers.get("Retry-After")}')
            if r.status_code in (404,410): raise Unavailable(f'HTTP {r.status_code}')
            if r.status_code in (500,502,503,504):
                if r.headers.get('Retry-After'): raise StopCollection('Server requests delay: '+r.headers['Retry-After'])
                r.raise_for_status()
            if r.status_code != 200: raise StopCollection(f'Unexpected HTTP {r.status_code}; stop')
            return r.content
        except (requests.ConnectionError,requests.Timeout,requests.HTTPError) as e:
            if attempt == 2: raise StopCollection(f'Retry budget exhausted: {e}') from e
            time.sleep(30 * 2**attempt)
def clean(value):
    return " ".join(value.split())

def get_listings(content):

    tree = html.fromstring(content)
    records = []

    for row in tree.xpath("//table//tr"):

        cells = row.xpath("./td")

        if len(cells) != 4:
            continue

        links = cells[0].xpath(".//a[@href]")

        for link in links:

            url = urljoin(BASE, link.get("href"))
            parsed = urlparse(url)

            match = re.search(r"/(\d+)/?$", parsed.path)

            if (
                parsed.hostname != "workforindiana.in.gov"
                or "/job/" not in parsed.path
                or not match
            ):
                continue

            records.append({
                "SourcePostingID": match.group(1),
                "RequisitionID": "",
                "JobTitle": clean(link.text_content()),
                "Location": clean(cells[1].text_content()),
                "MinimumSalaryRaw": clean(cells[2].text_content()),
                "DatePosted": clean(cells[3].text_content()),
                "AgencyRaw": "",
                "AgencyEvidence": "",
                "JobURL": url,
                "CollectionUTC": datetime.now(
                    timezone.utc
                ).isoformat(),
                "DetailStatus": "PENDING"
            })

            break

    return records, clean(tree.text_content())

def enrich(record):
    content = fetch(record["JobURL"])
    folder = OUT / ("html_recovery_" + STAMP)
    folder.mkdir(exist_ok=True)
    path = folder / (record["SourcePostingID"] + ".html")
    path.write_bytes(content)
    tree = html.fromstring(content)
    nodes = tree.xpath('//*[@itemprop="description"] | //*[@id="job-description"] | //*[contains(concat(" ",normalize-space(@class)," ")," jobdescription ")]')
    body = max(nodes, key=lambda n: len(n.text_content())) if nodes else tree.xpath('//body')[0]
    lines = [clean(x) for x in body.xpath('.//text()[not(ancestor::script) and not(ancestor::style)]') if x.strip()]
    text = '\n'.join(lines)
    alltext = clean(tree.text_content())
    req = re.search(r'Requisition\s*ID\s*:\s*(\d+)', alltext, re.I)
    if req:
        record['RequisitionID'] = req.group(1)
    for line in lines:
        if re.match(r'^About\s+(?:the\s+)?', line, re.I):
            candidate = re.sub(r'^About\s+(?:the\s+)?','',line,flags=re.I).strip(' :')
            if 3 < len(candidate) <= 150 and candidate.lower() not in ('us','indiana','this position','this role'):
                record['AgencyRaw'] = candidate
                record['AgencyEvidence'] = line
                break
    record['JobDescriptionRaw'] = text
    record['HTMLPath'] = str(path.relative_to(ROOT))
    record['DescriptionScope'] = 'DESCRIPTION_ELEMENT' if nodes else 'BODY_FALLBACK'
    headings = {'role overview':'RoleOverview','a day in the life':'ResponsibilitiesRaw','what you\'ll need for success':'QualificationsRaw','what you’ll need for success':'QualificationsRaw','responsibilities':'ResponsibilitiesRaw','qualifications':'QualificationsRaw','required qualifications':'RequiredQualifications','preferred qualifications':'PreferredQualifications','recommended experience':'ExperienceRequirements','salary':'SalarySection','benefits':'Benefits'}
    sections = {}
    current = None
    for line in lines:
        heading = line.lower().strip(' :')
        if heading in headings:
            current = headings[heading]
            sections.setdefault(current, [])
        elif current:
            sections[current].append(line)
    for key in set(headings.values()):
        record[key] = '\n'.join(sections.get(key, []))
    record['HiringEvidence'] = [x for x in lines if re.search(r'\b(currently hiring|now hiring|actively recruiting)\b',x,re.I)]
    record['CompensationCandidates'] = []
    for i,line in enumerate(lines):
        for m in re.finditer(r'\$\s*([\d,]+(?:\.\d{1,2})?)',line):
            context = ' '.join(lines[max(0,i-2):i+2])
            if not re.search(r'\b(salary|pay|wage|starts? at|per hour|hourly|annually|per year)\b|/hr',context,re.I):
                continue
            frequency = 'HOURLY' if re.search(r'per hour|hourly|/hr',line,re.I) else 'ANNUAL' if re.search(r'annually|per year|annual salary',line,re.I) else 'UNKNOWN'
            record['CompensationCandidates'].append({'amount':m.group(1).replace(',',''),'frequency':frequency,'evidence':line,'context':context,'status':'REVIEW_REQUIRED'})
    for field,pattern in {'EducationEvidence':r'\b(degree|diploma|GED|bachelor|master|doctorate)\b','ExperienceEvidence':r'\b(years? of experience|years? experience|experience required)\b','CertificationEvidence':r'\b(certification|certified|licensure|license)\b'}.items():
        record[field] = [line for line in lines if re.search(pattern,line,re.I)]
    skills = ['SQL','Python','data architecture','data governance','data modeling','machine learning','Power BI','Excel','customer service','communication','teamwork','leadership','project management','food preparation','food safety','equipment maintenance','budget management']
    record['SkillCandidates'] = [{'skill':skill,'evidence':line,'requirement':'UNSPECIFIED'} for skill in skills for line in lines if re.search(r'(?<!\w)'+re.escape(skill)+r'(?!\w)',line,re.I)]
    if not req:
        raise ValueError('Job page lacks requisition ID; review saved HTML')
    record['DetailStatus'] = 'COMPLETE' if record['RequisitionID'] and record['AgencyRaw'] and nodes else 'REVIEW_REQUIRED'
    record['DetailRetrievedUTC'] = datetime.now(timezone.utc).isoformat()
    return record


def atomic_csv(path, rows):
    fields = list(dict.fromkeys(k for r in rows for k in r))
    tmp = path.with_suffix('.tmp')
    with tmp.open('w', encoding='utf-8-sig', newline='') as f:
        w = csv.DictWriter(f, fieldnames=fields); w.writeheader()
        for r in rows: w.writerow({k:json.dumps(v,ensure_ascii=False) if isinstance(v,(list,dict)) else v for k,v in r.items()})
    os.replace(tmp,path)
def main():
    global STAMP
    parser=argparse.ArgumentParser(); parser.add_argument('--resume',required=True); args=parser.parse_args()
    STAMP=args.resume
    if not re.fullmatch(r'\d{8}T\d{6}Z',STAMP): raise ValueError('Invalid collection stamp')
    listing=OUT/f'state_careers_listings_{STAMP}.csv'
    checkpoint=OUT/f'state_careers_details_{STAMP}.jsonl'
    output=OUT/f'state_careers_snapshot_v3_{STAMP}.csv'
    journal=OUT/f'state_careers_recovery_{STAMP}.jsonl'
    with listing.open(encoding='utf-8-sig',newline='') as f: rows=list(csv.DictReader(f))
    records={r['SourcePostingID']:r for r in rows}
    if len(records)!=len(rows) or not rows or any(not k.isdigit() for k in records): raise ValueError('Invalid listing IDs')
    done={}; failures={}
    for file in (checkpoint,journal):
        if not file.exists(): continue
        with file.open(encoding='utf-8-sig') as f:
            for line in f:
                if not line.strip(): continue
                r=json.loads(line); k=r['SourcePostingID']
                if k not in records: raise ValueError('Unexpected checkpoint ID')
                if r.get('RecoveryStatus') in ('DETAIL_UNAVAILABLE','DETAIL_REVIEW'):
                    failures[k]=r; continue
                if not r.get('JobDescriptionRaw') or not r.get('HTMLPath') or not (ROOT/r['HTMLPath']).is_file(): raise ValueError(f'Missing evidence {k}')
                if k in done: raise ValueError(f'Duplicate checkpoint ID {k}')
                done[k]=r
    print(f'Listings: {len(records)} | preserved details: {len(done)} | remaining: {len(records)-len(done)}',flush=True)
    stop=None
    try:
        init_network()
        with journal.open('a',encoding='utf-8') as f:
            for k,original in records.items():
                if k in done or failures.get(k,{}).get('RecoveryStatus')=='DETAIL_UNAVAILABLE': continue
                try:
                    r=enrich(dict(original)); done[k]=r
                except Unavailable as e:
                    r={'SourcePostingID':k,'RecoveryStatus':'DETAIL_UNAVAILABLE','Error':str(e),'AttemptUTC':now()}; failures[k]=r
                except ValueError as e:
                    r={'SourcePostingID':k,'RecoveryStatus':'DETAIL_REVIEW','Error':str(e),'AttemptUTC':now()}; failures[k]=r
                f.write(json.dumps(r,ensure_ascii=False)+'\n'); f.flush(); os.fsync(f.fileno())
                print(f'{k}: {r.get("RecoveryStatus",r.get("DetailStatus"))} | details {len(done)}/{len(records)}',flush=True)
    except (StopCollection,requests.RequestException,KeyboardInterrupt) as e:
        stop=str(e) or 'Interrupted'; print('Stopped:',stop)
    result=[]
    for k,r in records.items():
        if k in done: result.append(done[k])
        else: result.append({**r,'DetailStatus':failures.get(k,{}).get('RecoveryStatus','PENDING'),'DetailError':failures.get(k,{}).get('Error','')})
    atomic_csv(output,result)
    print('=== RECOVERY SUMMARY ==='); print('Listings:',len(records)); print('Details:',len(done)); print('Unavailable:',sum(r['DetailStatus']=='DETAIL_UNAVAILABLE' for r in result)); print('Pending/review without details:',sum(r['DetailStatus'] in ('PENDING','DETAIL_REVIEW') for r in result)); print('Snapshot:',output); print('Original checkpoint preserved:',checkpoint); print('Recovery journal:',journal); print('No SQL changes. Historical inventory only; not a fresh active-posting scan.')
    return int(bool(stop) or any(r['DetailStatus'] in ('PENDING','DETAIL_REVIEW') for r in result))
if __name__=='__main__': raise SystemExit(main())
