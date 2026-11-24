
/* chekcing what schema table we have had:

USE IndianaWorkforceDW;
GO

SELECT
    TABLE_SCHEMA,
    TABLE_NAME
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'bronze'
ORDER BY TABLE_NAME;

*/

USE IndianaWorkforceDW;
GO

CREATE TABLE bronze.Laus_Unemployment_Raw
(
    RawID BIGINT IDENTITY(1,1) PRIMARY KEY,

    Geography VARCHAR(100),
    FIPSCode VARCHAR(5),
    ReportingYear VARCHAR(4),
    ReportingMonth VARCHAR(20),
    MonthCode VARCHAR(2),
    UnemploymentRate VARCHAR(20),

    SourceSystem VARCHAR(100) NOT NULL,
    SourceFile VARCHAR(255) NOT NULL,
    IngestionTimestamp DATETIME2
        NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

-- verify that SQL Server created all columns with the correct data types and constraints--

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