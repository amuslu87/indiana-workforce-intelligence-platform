USE IndianaWorkforceDW;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;

BEGIN TRY

    BEGIN TRANSACTION;

    -- Capture standardized compensation
    SELECT *
    INTO #StandardizedSalary
    FROM silver.vw_RecruitmentStandardizedSalary
    WHERE IsActive = 1;

    -- Validate uniqueness
    IF EXISTS
    (
        SELECT JobPostingID
        FROM #StandardizedSalary
        GROUP BY JobPostingID
        HAVING COUNT(*) > 1
    )
        THROW 50001,'Duplicate standardized salaries.',1;

    -- Synchronize Silver
    UPDATE p
    SET
        p.SalaryAmount = s.BaseSalary,
        p.SalaryFrequency = s.SalaryFrequency,
        p.AnnualizedSalary = s.AnnualizedSalary,
        p.AnnualizationHours = s.AnnualizationHours,
        p.SalaryValidationStatus =
            CASE
                WHEN s.BaseSalary IS NULL
                    THEN 'REVIEW_REQUIRED'
                WHEN s.FrequencyBasis = 'SOURCE_ASSUMPTION'
                    THEN 'REVIEW_REQUIRED'
                ELSE 'VALIDATED'
            END
    FROM silver.StateCareers_JobPosting p
    JOIN #StandardizedSalary s
        ON p.JobPostingID = s.JobPostingID;

    PRINT CONCAT('Silver rows synchronized: ',@@ROWCOUNT);

    -- Synchronize Gold
    UPDATE g
    SET
        g.SalaryAmount = s.BaseSalary,
        g.SalaryFrequency = s.SalaryFrequency,
        g.AnnualizedSalary = s.AnnualizedSalary
    FROM gold.Fact_StateJobPosting g
    JOIN #StandardizedSalary s
        ON g.JobPostingID = s.JobPostingID;

    PRINT CONCAT('Gold rows synchronized: ',@@ROWCOUNT);

    -- Validate Silver and Gold reconciliation
    IF EXISTS
    (
        SELECT
            p.JobPostingID,
            p.SalaryAmount,
            p.SalaryFrequency,
            p.AnnualizedSalary
        FROM silver.StateCareers_JobPosting p
        WHERE p.IsActive = 1

        EXCEPT

        SELECT
            g.JobPostingID,
            g.SalaryAmount,
            g.SalaryFrequency,
            g.AnnualizedSalary
        FROM gold.Fact_StateJobPosting g
        WHERE g.IsActive = 1
    )
        THROW 50002,'Silver-Gold salary mismatch.',1;

    -- Validate annualization
    IF EXISTS
    (
        SELECT 1
        FROM silver.StateCareers_JobPosting
        WHERE IsActive = 1
        AND SalaryFrequency = 'HOURLY'
        AND
        (
            AnnualizationHours IS NULL
            OR AnnualizationHours <> 1950
            OR AnnualizedSalary IS NULL
            OR AnnualizedSalary <> SalaryAmount * 1950
        )
    )
        THROW 50003,'Hourly annualization mismatch.',1;

    COMMIT TRANSACTION;

    -- Final compensation summary
    SELECT
        SalaryFrequency,
        SalaryValidationStatus,
        COUNT(*) AS Postings,
        MIN(SalaryAmount) AS MinimumBase,
        MAX(SalaryAmount) AS MaximumBase,
        MIN(AnnualizedSalary) AS MinimumAnnualized,
        MAX(AnnualizedSalary) AS MaximumAnnualized
    FROM silver.StateCareers_JobPosting
    WHERE IsActive = 1
    GROUP BY SalaryFrequency,SalaryValidationStatus;

    DROP TABLE #StandardizedSalary;

    PRINT 'SILVER-GOLD COMPENSATION INTEGRATION: PASS';

END TRY
BEGIN CATCH

    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    THROW;

END CATCH;
GO
