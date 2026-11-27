import re
import json
import time
import requests

from pathlib import Path
from lxml import html
from urllib.parse import urljoin, urlparse
from urllib.robotparser import RobotFileParser
from datetime import datetime, timezone

ROOT = Path(r"C:\Projects\IndianaWorkforceIntelligence")
OUT = ROOT / "data" / "raw" / "state_careers"
BASE = "https://workforindiana.in.gov"
AGENT = "IndianaWorkforceResearch"

files = sorted(OUT.glob("discovery_*.html"))

if not files:
    raise SystemExit("No saved discovery HTML found.")

source = files[-1]

print("\n=== SAVED SEARCH RESPONSE ===")
print(source)

tree = html.fromstring(source.read_bytes())

jobs = {}

for link in tree.xpath("//a[@href]"):

    href = link.get("href", "")
    url = urljoin(BASE, href)

    parsed = urlparse(url)

    if parsed.hostname != "workforindiana.in.gov":
        continue

    match = re.search(r"/(\d+)/?$", parsed.path)

    if "/job/" not in parsed.path or not match:
        continue

    title = " ".join(link.text_content().split())

    if title:
        jobs[match.group(1)] = {
            "title": title,
            "url": url
        }

print("Unique source posting IDs:", len(jobs))

session = requests.Session()

session.headers.update({
    "User-Agent": AGENT + "/1.0",
    "Accept": "text/html"
})

robots = session.get(
    BASE + "/robots.txt",
    timeout=30
)

robots.raise_for_status()

rp = RobotFileParser()
rp.parse(robots.text.splitlines())

results = []

for posting_id, job in list(jobs.items())[:5]:

    url = job["url"]

    print("\n" + "=" * 65)
    print("JOB TITLE:", job["title"])
    print("SOURCE POSTING ID:", posting_id)
    print("URL:", url)

    if not rp.can_fetch(AGENT, url):
        print("Skipped: robots policy.")
        continue

    time.sleep(2)

    response = session.get(url, timeout=30)

    print("HTTP status:", response.status_code)

    if response.status_code in (403, 429):
        print("Access restricted. Collection stopped.")
        break

    if response.status_code != 200:
        continue

    if urlparse(response.url).hostname != \
            "workforindiana.in.gov":
        print("Unexpected redirect. Collection stopped.")
        break

    page = html.fromstring(response.content)

    raw_path = OUT / f"job_detail_{posting_id}.html"
    raw_path.write_bytes(response.content)

    record = {
        "SourcePostingID": posting_id,
        "JobTitle": job["title"],
        "JobURL": url,
        "CollectionUTC": datetime.now(
            timezone.utc
        ).isoformat(),
        "Metadata": {},
        "StructuredData": [],
        "RelevantText": []
    }

    print("\n--- STRUCTURED METADATA ---")

    for element in page.xpath(
        "//meta[@itemprop] | "
        "//meta[@property] | "
        "//meta[@name]"
    ):

        key = (
            element.get("itemprop")
            or element.get("property")
            or element.get("name")
            or ""
        )

        value = element.get("content", "")

        if re.search(
            r"job|salary|location|date|title|"
            r"agency|department|organization|"
            r"identifier|description",
            key,
            re.I
        ) and value:

            record["Metadata"][key] = value
            print(f"{key}: {value[:300]}")

    print("\n--- JSON-LD STRUCTURED DATA ---")

    for script in page.xpath(
        "//script[@type='application/ld+json']"
    ):

        try:
            data = json.loads(script.text or "")

            record["StructuredData"].append(data)

            print(
                json.dumps(
                    data,
                    indent=2,
                    ensure_ascii=False
                )[:4000]
            )

        except json.JSONDecodeError:
            print("JSON-LD could not be parsed.")

    if not record["StructuredData"]:
        print("No JSON-LD detected.")

    print("\n--- RELEVANT JOB DETAIL TEXT ---")

    lines = [
        " ".join(line.split())
        for line in page.xpath(
            "//body//text()["
            "not(ancestor::script) and "
            "not(ancestor::style)]"
        )
        if line.strip()
    ]

    keywords = re.compile(
        r"agency|department|requisition|"
        r"salary|compensation|"
        r"starting pay|hourly|annually|"
        r"work for indiana|about the",
        re.I
    )

    selected = set()

    for i, line in enumerate(lines):

        if keywords.search(line):

            for j in range(
                max(0, i - 1),
                min(len(lines), i + 2)
            ):
                selected.add(j)

    for i in sorted(selected)[:40]:

        text = lines[i][:500]

        record["RelevantText"].append(text)
        print(text)

    results.append(record)

output = OUT / "job_detail_discovery.json"

output.write_text(
    json.dumps(
        results,
        indent=2,
        ensure_ascii=False
    ),
    encoding="utf-8"
)

print("\n=== JOB DETAIL DISCOVERY SUMMARY ===")
print("Jobs inspected:", len(results))
print("Discovery output:", output)
print("No database changes performed.")
print("JOB DETAIL DISCOVERY COMPLETE")
