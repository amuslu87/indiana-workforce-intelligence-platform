---Validate the KPI against SQL Server
USE IndianaWorkforceDW
GO
SELECT TOP (1)
    g.GeographyName,
    p.ReportingYear,
    p.MonthCode,
    f.UnemploymentRate
FROM gold.Fact_Unemployment AS f
INNER JOIN gold.Dim_Geography AS g
    ON f.GeographyKey = g.GeographyKey
INNER JOIN gold.Dim_ReportingPeriod AS p
    ON f.PeriodKey = p.PeriodKey
WHERE
    g.FIPSCode = '18000'
    AND p.PeriodType = 'Monthly'
ORDER BY
    p.ReportingYear DESC,
    p.MonthCode DESC;


-- Validate Marion County's KPI against SQL Server
SELECT TOP (1)
    g.GeographyName,
    p.ReportingYear,
    p.MonthCode,
    f.UnemploymentRate
FROM gold.Fact_Unemployment AS f
INNER JOIN gold.Dim_Geography AS g
    ON f.GeographyKey = g.GeographyKey
INNER JOIN gold.Dim_ReportingPeriod AS p
    ON f.PeriodKey = p.PeriodKey
WHERE
    g.FIPSCode = '18097'
    AND p.PeriodType = 'Monthly'
ORDER BY
    p.ReportingYear DESC,
    p.MonthCode DESC;

-- Prepare a month-over-month comparison

SELECT TOP (3)
    g.GeographyName,
    p.ReportingYear,
    p.MonthCode,
    f.UnemploymentRate
FROM gold.Fact_Unemployment AS f
INNER JOIN gold.Dim_Geography AS g
    ON f.GeographyKey = g.GeographyKey
INNER JOIN gold.Dim_ReportingPeriod AS p
    ON f.PeriodKey = p.PeriodKey
WHERE
    g.FIPSCode = '18097'
    AND p.PeriodType = 'Monthly'
ORDER BY
    p.ReportingYear DESC,
    p.MonthCode DESC;