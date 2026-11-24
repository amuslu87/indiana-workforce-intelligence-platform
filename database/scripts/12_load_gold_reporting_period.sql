USE IndianaWorkforceDW;
GO

-- Load unique reporting periods from Silver
INSERT INTO gold.Dim_ReportingPeriod
(
    ReportingYear,
    MonthCode,
    ReportingMonth,
    PeriodType
)
SELECT DISTINCT
    s.ReportingYear,
    s.MonthCode,
    s.ReportingMonth,
    s.PeriodType
FROM silver.Laus_Unemployment AS s
WHERE NOT EXISTS
(
    SELECT 1
    FROM gold.Dim_ReportingPeriod AS p
    WHERE p.ReportingYear = s.ReportingYear
      AND p.MonthCode = s.MonthCode
);
GO

-- Validate reporting-period counts by year
SELECT
    ReportingYear,
    PeriodType,
    COUNT(*) AS TotalPeriods
FROM gold.Dim_ReportingPeriod
GROUP BY
    ReportingYear,
    PeriodType
ORDER BY
    ReportingYear,
    PeriodType;