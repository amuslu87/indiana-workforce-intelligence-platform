SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;

BEGIN TRY
    BEGIN TRANSACTION;

    IF COL_LENGTH(
        'silver.StateCareers_JobPosting',
        'LatestListingRawID'
    ) IS NULL
    BEGIN
        ALTER TABLE silver.StateCareers_JobPosting
        ADD LatestListingRawID bigint NULL;

        ALTER TABLE silver.StateCareers_JobPosting
        ADD CONSTRAINT FK_SC_LatestListingRaw
        FOREIGN KEY (LatestListingRawID)
        REFERENCES bronze.StateCareers_Raw(RawID);
    END;

    EXEC sp_executesql N'
        UPDATE s
        SET LatestListingRawID = r.RawID
        FROM silver.StateCareers_JobPosting s
        CROSS APPLY (
            SELECT TOP 1 b.RawID
            FROM bronze.StateCareers_Raw b
            WHERE b.SourcePostingID = s.SourcePostingID
            ORDER BY b.CollectionUTC DESC, b.RawID DESC
        ) r;

        SELECT
            COUNT(*) AS TotalPostings,
            COUNT(LatestListingRawID) AS ListingReferences,
            COUNT(LatestRawID) AS ExistingReferences
        FROM silver.StateCareers_JobPosting;
    ';

    COMMIT TRANSACTION;
    PRINT 'LINEAGE MIGRATION PASSED';

END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
