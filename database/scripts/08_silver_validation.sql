
--Verify the Silver table before transformation
USE IndianaWorkforceDW;
GO

SELECT
    COUNT(*) AS SilverRecordCount
FROM silver.Laus_Unemployment;

--Validate data types before transformation

USE IndianaWorkforceDW;
GO

SELECT
    RawID,
    SourceFile,
    FIPSCode,
    ReportingYear,
    MonthCode,
    UnemploymentRate
FROM bronze.Laus_Unemployment_Raw
WHERE
    TRY_CONVERT(SMALLINT, ReportingYear) IS NULL
    OR TRY_CONVERT(TINYINT, MonthCode) IS NULL
    OR TRY_CONVERT(DECIMAL(5,2), UnemploymentRate) IS NULL
    OR LEN(FIPSCode) <> 5
    OR FIPSCode IS NULL;

-- Validate Silver business rules

USE IndianaWorkforceDW;
GO

SELECT
    SUM(CASE
        WHEN TRY_CONVERT(DECIMAL(5,2), UnemploymentRate)
             NOT BETWEEN 0 AND 100
        THEN 1 ELSE 0
    END) AS InvalidRates,

    SUM(CASE
        WHEN TRY_CONVERT(TINYINT, MonthCode)
             NOT BETWEEN 1 AND 13
        THEN 1 ELSE 0
    END) AS InvalidMonthCodes,

    SUM(CASE
        WHEN (MonthCode = '13' AND ReportingMonth <> 'Annual Average')
          OR (TRY_CONVERT(TINYINT, MonthCode) BETWEEN 1 AND 12
              AND ReportingMonth = 'Annual Average')
        THEN 1 ELSE 0
    END) AS InvalidPeriodLabels
FROM bronze.Laus_Unemployment_Raw;


-- Validate business-key uniqueness

USE IndianaWorkforceDW;
GO

SELECT
    FIPSCode,
    ReportingYear,
    MonthCode,
    COUNT(*) AS DuplicateCount
FROM bronze.Laus_Unemployment_Raw
GROUP BY
    FIPSCode,
    ReportingYear,
    MonthCode
HAVING COUNT(*) > 1
ORDER BY DuplicateCount DESC;