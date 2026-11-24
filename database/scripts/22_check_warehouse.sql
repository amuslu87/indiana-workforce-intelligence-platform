USE IndianaWorkforceDW;
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @GoldBefore bigint;
DECLARE @PublishedBefore bigint;

SELECT @GoldBefore = COUNT_BIG(*)
FROM gold.Fact_Unemployment;

SELECT @PublishedBefore = COUNT_BIG(*)
FROM serving.vw_Unemployment;

BEGIN TRY
    BEGIN TRANSACTION;

    -- Simulate incomplete working Gold data
    DELETE TOP (1)
    FROM gold.Fact_Unemployment;

    SELECT
        'During simulated failure' AS TestStage,
        @GoldBefore AS OriginalGoldRows,
        (SELECT COUNT_BIG(*)
         FROM gold.Fact_Unemployment) AS CurrentGoldRows,
        @PublishedBefore AS OriginalPublishedRows,
        (SELECT COUNT_BIG(*)
         FROM serving.vw_Unemployment) AS CurrentPublishedRows;

    -- Restore the original working data
    ROLLBACK TRANSACTION;

    SELECT
        'After rollback' AS TestStage,
        (SELECT COUNT_BIG(*)
         FROM gold.Fact_Unemployment) AS GoldRows,
        (SELECT COUNT_BIG(*)
         FROM serving.vw_Unemployment) AS PublishedRows,
        @@TRANCOUNT AS OpenTransactions;

END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;