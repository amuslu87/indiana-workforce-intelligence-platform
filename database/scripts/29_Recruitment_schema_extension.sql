USE IndianaWorkforceDW;
GO

SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    -- 1. Multiple compensation records per posting

    IF OBJECT_ID(
        'silver.StateCareers_JobCompensation', 'U'
    ) IS NULL
    BEGIN
        CREATE TABLE silver.StateCareers_JobCompensation
        (
            CompensationID BIGINT IDENTITY(1,1)
                PRIMARY KEY,

            JobPostingID BIGINT NOT NULL,

            SourceRawID BIGINT NOT NULL,

            RoleName NVARCHAR(300) NULL,

            SalaryAmount DECIMAL(18,2) NOT NULL,

            SalaryFrequency VARCHAR(20) NOT NULL,

            AnnualizedSalary DECIMAL(18,2) NULL,

            AnnualizationHours SMALLINT NULL,

            TipsEligible BIT NULL,

            IsExplicitlyHiring BIT NULL,

            SalaryEvidence NVARCHAR(MAX) NOT NULL,

            ContextEvidence NVARCHAR(MAX) NULL,

            ExtractionMethod VARCHAR(50) NOT NULL,

            ExtractionVersion VARCHAR(30) NOT NULL,

            ValidationStatus VARCHAR(20) NOT NULL
                DEFAULT 'REVIEW_REQUIRED',

            LoadUTC DATETIME2(3) NOT NULL
                DEFAULT SYSUTCDATETIME(),

            CONSTRAINT FK_SC_Compensation_Posting
                FOREIGN KEY (JobPostingID)
                REFERENCES silver.StateCareers_JobPosting
                    (JobPostingID),

            CONSTRAINT FK_SC_Compensation_Raw
                FOREIGN KEY (SourceRawID)
                REFERENCES bronze.StateCareers_Raw
                    (RawID),

            CONSTRAINT CK_SC_Compensation_Amount
                CHECK (SalaryAmount >= 0),

            CONSTRAINT CK_SC_Compensation_Annual
                CHECK (AnnualizedSalary >= 0),

            CONSTRAINT CK_SC_Compensation_Hours
                CHECK (AnnualizationHours > 0),

            CONSTRAINT CK_SC_Compensation_Frequency
                CHECK (
                    SalaryFrequency IN (
                        'HOURLY',
                        'ANNUAL',
                        'MONTHLY',
                        'BIWEEKLY',
                        'WEEKLY',
                        'UNKNOWN'
                    )
                ),

            CONSTRAINT CK_SC_Compensation_Status
                CHECK (
                    ValidationStatus IN (
                        'VALIDATED',
                        'REVIEW_REQUIRED',
                        'EXCLUDED'
                    )
                )
        );

        CREATE INDEX IX_SC_Compensation_Posting
        ON silver.StateCareers_JobCompensation
        (
            JobPostingID,
            ValidationStatus
        );

        PRINT 'PASS: Compensation table created.';
    END;


    -- 2. Preserve complete structured source evidence

    IF COL_LENGTH(
        'bronze.StateCareers_Raw',
        'RawPayloadJSON'
    ) IS NULL
    BEGIN
        ALTER TABLE bronze.StateCareers_Raw
        ADD RawPayloadJSON NVARCHAR(MAX) NULL;
    END;


    -- 3. Preserve original HTML location

    IF COL_LENGTH(
        'bronze.StateCareers_Raw',
        'HTMLPath'
    ) IS NULL
    BEGIN
        ALTER TABLE bronze.StateCareers_Raw
        ADD HTMLPath NVARCHAR(2048) NULL;
    END;


    -- 4. Distinguish listing and detail retrieval times

    IF COL_LENGTH(
        'bronze.StateCareers_Raw',
        'DetailRetrievedUTC'
    ) IS NULL
    BEGIN
        ALTER TABLE bronze.StateCareers_Raw
        ADD DetailRetrievedUTC DATETIME2(3) NULL;
    END;


    -- 5. Preserve extraction scope

    IF COL_LENGTH(
        'bronze.StateCareers_Raw',
        'DescriptionScope'
    ) IS NULL
    BEGIN
        ALTER TABLE bronze.StateCareers_Raw
        ADD DescriptionScope VARCHAR(30) NULL;
    END;


    -- 6. Distinguish listing completeness from
    --    detail collection completeness

    IF COL_LENGTH(
        'bronze.StateCareers_Collection',
        'IsListingComplete'
    ) IS NULL
    BEGIN
        ALTER TABLE bronze.StateCareers_Collection
        ADD IsListingComplete BIT NULL;
    END;

    IF COL_LENGTH(
        'bronze.StateCareers_Collection',
        'IsDetailComplete'
    ) IS NULL
    BEGIN
        ALTER TABLE bronze.StateCareers_Collection
        ADD IsDetailComplete BIT NULL;
    END;


    COMMIT TRANSACTION;

    PRINT 'PASS: Recruitment schema extension completed.';

END TRY
BEGIN CATCH

    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    THROW;

END CATCH;
GO


-- 7. Final verification

SELECT
    OBJECT_ID(
        'silver.StateCareers_JobCompensation'
    ) AS CompensationTableID,

    COL_LENGTH(
        'bronze.StateCareers_Raw',
        'RawPayloadJSON'
    ) AS RawPayloadJSON,

    COL_LENGTH(
        'bronze.StateCareers_Raw',
        'HTMLPath'
    ) AS HTMLPath,

    COL_LENGTH(
        'bronze.StateCareers_Raw',
        'DetailRetrievedUTC'
    ) AS DetailRetrievedUTC,

    COL_LENGTH(
        'bronze.StateCareers_Raw',
        'DescriptionScope'
    ) AS DescriptionScope,

    COL_LENGTH(
        'bronze.StateCareers_Collection',
        'IsListingComplete'
    ) AS IsListingComplete,

    COL_LENGTH(
        'bronze.StateCareers_Collection',
        'IsDetailComplete'
    ) AS IsDetailComplete;
GO