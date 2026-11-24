
USE IndianaWorkforceDW;
GO

SELECT
    SourceFile,
    ReportingYear,
    COUNT(*) AS TotalRecords,
    COUNT(DISTINCT FIPSCode) AS GeographicAreas,
    MIN(IngestionTimestamp) AS FirstIngestion,
    MAX(IngestionTimestamp) AS LastIngestion
FROM bronze.Laus_Unemployment_Raw
GROUP BY
    SourceFile,
    ReportingYear;