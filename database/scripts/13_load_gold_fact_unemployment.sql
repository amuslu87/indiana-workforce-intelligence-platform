USE IndianaWorkforceDW;
GO

SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    INSERT INTO gold.Fact_Unemployment
    (
        GeographyKey,
        PeriodKey,
        UnemploymentRate,
        SilverLausID
    )
    SELECT
        g.GeographyKey,
        p.PeriodKey,
        s.UnemploymentRate,
        s.LausID

    FROM silver.Laus_Unemployment AS s

    INNER JOIN gold.Dim_Geography AS g
        ON s.FIPSCode = g.FIPSCode

    INNER JOIN gold.Dim_ReportingPeriod AS p
        ON s.ReportingYear = p.ReportingYear
        AND s.MonthCode = p.MonthCode

    WHERE NOT EXISTS
    (
        SELECT 1
        FROM gold.Fact_Unemployment AS f
        WHERE f.GeographyKey = g.GeographyKey
          AND f.PeriodKey = p.PeriodKey
    );

    DECLARE @InsertedRecords INT = @@ROWCOUNT;

    COMMIT TRANSACTION;

    SELECT
        @InsertedRecords AS InsertedRecords,
        (SELECT COUNT(*) FROM gold.Fact_Unemployment)
            AS TotalGoldRecords;

END TRY
BEGIN CATCH

    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    THROW;

END CATCH;
GO


-- Validate the Gold star schema

USE IndianaWorkforceDW;
GO

SELECT
    (SELECT COUNT(*)
     FROM silver.Laus_Unemployment) AS SilverRecords,

    (SELECT COUNT(*)
     FROM gold.Fact_Unemployment) AS GoldRecords,

    (SELECT COUNT(*)
     FROM silver.Laus_Unemployment AS s
     LEFT JOIN gold.Fact_Unemployment AS f
         ON s.LausID = f.SilverLausID
     WHERE f.UnemploymentFactKey IS NULL) AS MissingGoldRecords,

    (SELECT COUNT(*)
     FROM gold.Fact_Unemployment AS f
     INNER JOIN silver.Laus_Unemployment AS s
         ON f.SilverLausID = s.LausID
     INNER JOIN gold.Dim_Geography AS g
         ON f.GeographyKey = g.GeographyKey
     INNER JOIN gold.Dim_ReportingPeriod AS p
         ON f.PeriodKey = p.PeriodKey
     WHERE f.UnemploymentRate <> s.UnemploymentRate
        OR g.FIPSCode <> s.FIPSCode
        OR p.ReportingYear <> s.ReportingYear
        OR p.MonthCode <> s.MonthCode
    ) AS DataMismatches;



    --- check server

    EXEC sys.xp_readerrorlog
    0,
    1,
    N'certificate';