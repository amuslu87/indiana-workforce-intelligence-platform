USE IndianaWorkforceDW;
GO

SELECT
    ReportingYear,
    SourceFile,
    COUNT(*) AS TotalRecords,
    COUNT(DISTINCT FIPSCode) AS GeographicAreas
FROM bronze.Laus_Unemployment_Raw
GROUP BY
    ReportingYear,
    SourceFile
ORDER BY
    ReportingYear;

-- Inspect the Bronze data types --

USE IndianaWorkforceDW;
GO

SELECT
    COLUMN_NAME,
    DATA_TYPE,
    CHARACTER_MAXIMUM_LENGTH,
    IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'bronze'
  AND TABLE_NAME = 'Laus_Unemployment_Raw'
ORDER BY ORDINAL_POSITION;