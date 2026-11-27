import requests
import re
import pandas as pd

from io import StringIO
from pathlib import Path
from datetime import datetime, timezone
from urllib.parse import urljoin
from lxml import html

BASE = "https://workforindiana.in.gov"

URL = (
    BASE + "/search/?searchby=location"
    "&createNewAlert=false"
    "&q=&locationsearch=&geolocation="
    "&optionsFacetsDD_customfield3="
    "&optionsFacetsDD_city="
    "&optionsFacetsDD_customfield1="
)

ROOT = Path(r"C:\Projects\IndianaWorkforceIntelligence")
OUT = ROOT / "data" / "raw" / "state_careers"

OUT.mkdir(parents=True, exist_ok=True)

session = requests.Session()

session.headers.update({
    "User-Agent": "IndianaWorkforceResearch/1.0",
    "Accept": "text/html,application/json"
})

print("\n=== STATE CAREERS SOURCE DISCOVERY ===")
print("Collection UTC:", datetime.now(timezone.utc))
print("Source:", URL)

print("\n=== ROBOTS POLICY ===")

robots = session.get(
    BASE + "/robots.txt",
    timeout=30
)

print("HTTP status:", robots.status_code)

if robots.status_code == 200:
    print(robots.text[:5000])

if robots.status_code != 200:
    print("Review robots policy before automated collection.")

# Only retrieve the search page if the robots policy
# explicitly permits this user agent to fetch it.

from urllib.robotparser import RobotFileParser

rp = RobotFileParser()

if robots.status_code == 200:
    rp.parse(robots.text.splitlines())

    if not rp.can_fetch(
        "IndianaWorkforceResearch", URL
    ):
        raise SystemExit(
            "Robots policy disallows automated retrieval."
        )

elif robots.status_code != 404:
    raise SystemExit(
        "Robots policy could not be verified."
    )

print("\n=== LIVE WEBSITE CONNECTION ===")

response = session.get(URL, timeout=60)

print("HTTP status:", response.status_code)
print("Content type:", response.headers.get("Content-Type"))
print("Response size:", len(response.content))
print("Final URL:", response.url)

response.raise_for_status()

tree = html.fromstring(response.content)

stamp = datetime.now(timezone.utc).strftime(
    "%Y%m%dT%H%M%SZ"
)

raw_file = OUT / f"discovery_{stamp}.html"

raw_file.write_bytes(response.content)

print("Raw response saved:", raw_file)

print("\n=== PAGE TITLE ===")

print(tree.xpath("string(//title)").strip())

print("\n=== SEARCH RESULT COUNTS ===")

page_text = " ".join(tree.text_content().split())

pattern = (
    r"Results\s+[\d,]+\s*[-–]\s*[\d,]+"
    r"\s+of\s+[\d,]+"
)

matches = list(set(re.findall(
    pattern,
    page_text,
    flags=re.I
)))

print(matches or "Result count not identified")

print("\n=== HTML TABLE DISCOVERY ===")

try:
    tables = pd.read_html(
        StringIO(response.text)
    )

    print("Tables found:", len(tables))

    for i, table in enumerate(tables):

        print(f"\nTable {i + 1}")
        print("Shape:", table.shape)
        print("Columns:", list(table.columns))
        print(table.head(5).to_string(index=False))

except ValueError:
    print("No standard HTML tables detected.")

print("\n=== INDIVIDUAL JOB LINKS ===")

jobs = {}

for link in tree.xpath("//a[@href]"):

    href = link.get("href", "")

    if "/job/" not in href.lower():
        continue

    full_url = urljoin(BASE, href)

    title = " ".join(
        link.text_content().split()
    )

    if title:
        jobs[full_url] = title

print("Unique job links:", len(jobs))

for job_url, title in list(jobs.items())[:5]:

    print("Title:", title)
    print("URL:", job_url)
    print()

print("\n=== PAGINATION DISCOVERY ===")

pagination = set()

for href in tree.xpath("//a/@href"):

    if "startrow=" in href.lower():
        pagination.add(urljoin(BASE, href))

for link in sorted(pagination)[:5]:
    print(link)

print("Pagination links found:", len(pagination))

print("\n=== STRUCTURED DATA DISCOVERY ===")

for script in tree.xpath("//script[@type]"):

    script_type = script.get("type", "")

    if "json" in script_type.lower():

        content = script.text or ""

        print(
            "Type:", script_type,
            "| Characters:", len(content)
        )

print("\n=== SOURCE DISCOVERY SUMMARY ===")
print("HTTP connection: PASS")
print("Unique job links:", len(jobs))
print("Pagination links:", len(pagination))
print("No database changes performed.")
print("SOURCE DISCOVERY COMPLETE")
