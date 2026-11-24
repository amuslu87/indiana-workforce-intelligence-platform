
# Workforce Analytics KPI Definitions

## 1. Latest Available Unemployment Rate

**Definition:** The most recently reported monthly unemployment
rate for the selected geographic area.

**Source:** gold.Fact_Unemployment

**Dimensions:**
- gold.Dim_Geography
- gold.Dim_ReportingPeriod

**Calculation:**
Select the unemployment rate associated with the latest
available monthly reporting date for the selected geography.

**Unit:** Percent (%)

**Data Quality Rules:**
- Exclude annual-average records.
- Do not substitute missing monthly observations.
- Reporting dates may differ between geographic areas.

## 2. Month-over-Month Unemployment Rate Change

**Definition:** The difference between the latest available
monthly unemployment rate and the rate from the immediately
preceding calendar month.

**Formula:**
MoM Change (pp) = Current Rate (%) - Previous Month Rate (%)

**Unit:** Percentage points (pp)

**Data Quality Rules:**
- Compare only consecutive calendar months.
- Return N/A when the preceding month is unavailable.
- Do not interpolate missing observations.
- Positive values indicate an increase in unemployment rate.
- Negative values indicate a decrease in unemployment rate.

## 3. Validation Evidence

### Indiana Statewide
Latest available rate: 3.3%
Reporting period: October 2026
Validated against SQL Server Gold fact table.

### Marion County
Latest available rate: 3.7%
Reporting period: September 2026

August 2026 rate: 3.6%
September 2026 rate: 3.7%
Month-over-month change: +0.1 percentage points

Validated against SQL Server Gold fact table and R Shiny.

## 4. Metric Governance

- SQL Server Gold is the authoritative data source.
- R Shiny provides presentation and reactive calculations.
- Missing observations are not estimated.
- Unemployment rates are non-additive measures.
- Statewide unemployment rates must not be calculated
  by averaging county unemployment rates.
