USE IndianaWorkforceDW;
GO

SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    IF COL_LENGTH(
        'bronze.StateCareers_Collection',
        'SourceCollectionKey'
    ) IS NULL
    BEGIN
        ALTER TABLE bronze.StateCareers_Collection
        ADD SourceCollectionKey VARCHAR(50) NULL;
    END;

    IF NOT EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE object_id = OBJECT_ID(
            'bronze.StateCareers_Collection'
        )
        AND name = 'UX_SC_Collection_SourceKey'
    )
    BEGIN
        EXEC(N'
            CREATE UNIQUE INDEX UX_SC_Collection_SourceKey
            ON bronze.StateCareers_Collection
                (SourceCollectionKey)
            WHERE SourceCollectionKey IS NOT NULL;
        ');
    END;

    COMMIT TRANSACTION;

    PRINT 'PASS: Collection idempotency protection created.';

END TRY
BEGIN CATCH

    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    THROW;

END CATCH;
GO

SELECT
    name AS IndexName,
    is_unique AS IsUnique,
    is_disabled AS IsDisabled,
    filter_definition AS FilterDefinition
FROM sys.indexes
WHERE object_id = OBJECT_ID(
    'bronze.StateCareers_Collection'
)
AND name = 'UX_SC_Collection_SourceKey';