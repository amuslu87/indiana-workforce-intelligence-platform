USE IndianaWorkforceDW;
GO

SELECT
    p.ReportingYear,
    p.MonthCode,
    p.ReportingMonth,
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
    p.ReportingYear,
    p.MonthCode;

--- Preparing county level filtering

SELECT
    GeographyType,
    COUNT(*) AS GeographyCount
FROM gold.Dim_Geography
GROUP BY GeographyType
ORDER BY GeographyType;

-- Retrieve county names from SQL Server
