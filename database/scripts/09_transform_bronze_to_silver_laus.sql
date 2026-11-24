USE IndianaWorkforceDW;
GO

SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    INSERT INTO silver.Laus_Unemployment
    (
        Geography,
        FIPSCode,
        GeographyType,
        ReportingYear,
        MonthCode,
        ReportingMonth,
        PeriodType,
        UnemploymentRate,
        BronzeRawID,
        SourceFile
    )
    SELECT
        b.Geography,
        b.FIPSCode,

        CASE
            WHEN b.FIPSCode = '18000' THEN 'State'
            ELSE 'County'
        END,

        TRY_CONVERT(SMALLINT, b.ReportingYear),
        TRY_CONVERT(TINYINT, b.MonthCode),
        b.ReportingMonth,

        CASE
            WHEN TRY_CONVERT(TINYINT, b.MonthCode) = 13
                THEN 'Annual Average'
            ELSE 'Monthly'
        END,

        TRY_CONVERT(DECIMAL(5,2), b.UnemploymentRate),
        b.RawID,
        b.SourceFile

    FROM bronze.Laus_Unemployment_Raw AS b

    WHERE NOT EXISTS
    (
        SELECT 1
        FROM silver.Laus_Unemployment AS s
        WHERE s.FIPSCode = b.FIPSCode
          AND s.ReportingYear = TRY_CONVERT(SMALLINT, b.ReportingYear)
          AND s.MonthCode = TRY_CONVERT(TINYINT, b.MonthCode)
    );

    DECLARE @InsertedRecords INT = @@ROWCOUNT;

    COMMIT TRANSACTION;

    SELECT
        @InsertedRecords AS InsertedRecords,
        (SELECT COUNT(*) FROM silver.Laus_Unemployment)
            AS TotalSilverRecords;

END TRY
BEGIN CATCH

    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    THROW;

END CATCH;
GO


--- validate silver record counts

USE IndianaWorkforceDW;
GO

SELECT
    ReportingYear,
    GeographyType,
    PeriodType,
    COUNT(*) AS TotalRecords
FROM silver.Laus_Unemployment
GROUP BY
    ReportingYear,
    GeographyType,
    PeriodType
ORDER BY
    ReportingYear,
    GeographyType,
    PeriodType;

  --Validate Bronze-to-Silver data lineage

USE IndianaWorkforceDW;
GO

SELECT
    COUNT(*) AS TotalSilverRecords,

    SUM(CASE
        WHEN b.RawID IS NULL THEN 1 ELSE 0
    END) AS MissingBronzeReferences,

    SUM(CASE
        WHEN s.SourceFile <> b.SourceFile
        THEN 1 ELSE 0
    END) AS SourceFileMismatches,

    SUM(CASE
        WHEN s.FIPSCode <> b.FIPSCode
          OR s.ReportingYear <> TRY_CONVERT(SMALLINT, b.ReportingYear)
          OR s.MonthCode <> TRY_CONVERT(TINYINT, b.MonthCode)
        THEN 1 ELSE 0
    END) AS BusinessKeyMismatches

FROM silver.Laus_Unemployment AS s

LEFT JOIN bronze.Laus_Unemployment_Raw AS b
    ON s.BronzeRawID = b.RawID;