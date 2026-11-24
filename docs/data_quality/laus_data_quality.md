# STATS Indiana LAUS — Data Quality Assessment

**Project:** Indiana Workforce Intelligence Platform  
**Data Source:** STATS Indiana — Local Area Unemployment Statistics (LAUS)  
**Indicator:** Unemployment Rate  
**Adjustment:** Not Seasonally Adjusted (NSA)  
**Reporting Period:** 2023–2026  
**Assessment Date:** November 22, 2026  
**Assessment Status:** Initial validation completed; reporting gaps identified

## 1. Purpose

This document records the initial data-quality assessment of Indiana unemployment data before ingestion into the enterprise data warehouse.

The assessment supports data reliability, traceability, governance, and reproducibility.

## 2. Source Data

Four annual datasets were downloaded from STATS Indiana:

- `stats_data_2023.xls`
- `stats_data_2024.xls`
- `stats_data_2025.xls`
- `stats_data_2026.xls`

The files contain HTML-formatted tables with `.xls` extensions.

Original files are retained in `data/raw/stats_indiana/laus/`.

## 3. Data Structure

Each dataset contains six columns:

| Column | Description |
|---|---|
| Geography | State or county name |
| FIPS Code | Geographic identifier |
| Year | Reporting year |
| Month | Reporting month or annual average |
| Month Code | Numeric reporting-period identifier |
| Unemployment Rate | Reported unemployment percentage |

The datasets contain 92 Indiana counties and one statewide aggregate.

## 4. Initial Validation Results

| Year | Records | Geographies | Null Values | Duplicate Keys | Invalid Rates |
|---|---:|---:|---:|---:|---:|
| 2023 | 1,209 | 93 | 0 | 0 | 0 |
| 2024 | 1,209 | 93 | 0 | 0 | 0 |
| 2025 | 1,116 | 93 | 0 | 0 | 0 |
| 2026 | 838 | 93 | 0 | 0 | 0 |
| **Total** | **4,372** | | **0** | **0** | **0** |

**Business key:** FIPS Code + Year + Month Code

The initial validation found no duplicate business keys, null values, or unemployment rates outside the permitted range of 0–100%.

These checks do not independently establish the accuracy of source values.

## 5. Reporting-Period Completeness

| Year | Reporting Coverage | Finding |
|---|---|---|
| 2023 | January–December + annual average | Complete |
| 2024 | January–December + annual average | Complete |
| 2025 | January–September, November–December + annual average | October missing |
| 2026 | January–September for all geographies; October statewide only | Partial-year coverage |

### Identified Data-Quality Issues

**DQ-001: Missing October 2025 observations**

October 2025 is absent for all 93 geographic areas in the downloaded dataset.

Status: Open — source coverage requires further investigation.

**DQ-002: Partial October 2026 coverage**

October 2026 contains one statewide observation but no county-level observations.

Status: Open — monitor future source releases.

## 6. Initial Data-Quality Rules

- **DQ-R01 — Completeness:** Identify missing values and reporting periods.
- **DQ-R02 — Uniqueness:** Detect duplicate combinations of FIPS Code, Year, and Month Code.
- **DQ-R03 — Validity:** Require unemployment rates to fall between 0% and 100%.
- **DQ-R04 — Geographic Classification:** Distinguish statewide observations from county-level observations.
- **DQ-R05 — Reporting Period:** Treat Month Code 13 as an annual-average record, not a calendar month.
- **DQ-R06 — Source Preservation:** Retain original downloaded files without modification.

## 7. Architecture and Governance Decisions

Python and pandas are used for source extraction, initial profiling, and ingestion.

SQL Server will support the Medallion architecture:

- **Bronze:** Source records and ingestion metadata.
- **Silver:** Standardized data, validation rules, and geographic classification.
- **Gold:** Analytics-ready models, workforce indicators, and reporting datasets.

Power BI will consume curated analytical data from the Gold layer.

Missing observations will not be silently replaced or fabricated. Data-quality exceptions will be documented and investigated.

## 8. Outstanding Validation Activities

- Verify all county FIPS identifiers against an authoritative reference.
- Investigate the missing October 2025 reporting period.
- Monitor availability of remaining 2026 county observations.
- Validate data types and reporting-period classifications during SQL transformation.
- Establish automated data-quality logging and exception handling.
- Document source retrieval dates, source URLs, and refresh procedures.

## 9. Assessment Summary

The four datasets contain 4,372 observations. Initial checks for null values, duplicate business keys, geographic counts, and unemployment-rate validity passed.

Reporting-period completeness differs by year. These differences will be preserved, documented, and addressed through data-quality controls as the pipeline develops.



# Dashboard Missing-Data Handling

## Decision
Missing monthly unemployment observations are represented as
NA values in the R Shiny visualization layer.

## Implementation
The application generates a complete monthly date sequence
for the selected geography and merges it with the reported
unemployment observations.

## Rationale
Connecting observations across missing reporting months could
misrepresent the continuity of the underlying data.

## Known Source Gap
October 2025 is absent from the current STATS Indiana LAUS
source dataset.

## Data Governance
- No missing unemployment rates are imputed.
- No interpolation is performed.
- Original SQL Server Gold records remain unchanged.
- Missing periods are displayed as breaks in the trend line.

## Validation
Verified visually using the Marion County unemployment trend
in the R Shiny dashboard.

## Future Enhancement
Add explicit missing-data indicators and data-coverage
information to the dashboard.


