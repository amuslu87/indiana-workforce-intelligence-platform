USE IndianaWorkforceDW;
GO

SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    INSERT INTO control.RecruitmentSalaryOverride
    (
        JobPostingID,
        SourceRawID,
        ListingRawID,
        OriginalSalaryRaw,
        ApprovedBaseSalary,
        SalaryFrequency,
        FrequencyBasis,
        CorrectionType,
        Evidence
    )
    SELECT
        p.JobPostingID,
        p.LatestRawID,
        p.LatestListingRawID,
        p.MinimumSalaryRaw,
        v.BaseSalary,
        'HOURLY',
        'EXPLICIT',
        'DESCRIPTION_RECOVERY',
        LEFT(c.ContextEvidence,2000)
    FROM silver.StateCareers_JobPosting p
    JOIN
    (
        VALUES
        (706,14.23,N'Guest Services Representative:'),
        (594,15.00,N'Housekeeping:')
    ) v(JobPostingID,BaseSalary,RolePrefix)
        ON p.JobPostingID = v.JobPostingID

    CROSS APPLY
    (
        SELECT TOP 1 c.ContextEvidence
        FROM silver.StateCareers_JobCompensation c
        WHERE c.JobPostingID = p.JobPostingID
        AND c.SourceRawID = p.LatestRawID
        AND c.SalaryAmount = v.BaseSalary
        AND c.SalaryFrequency = 'HOURLY'
        AND c.ContextEvidence LIKE v.RolePrefix + '%'
        ORDER BY c.CompensationID
    ) c

    WHERE p.IsActive = 1
    AND NULLIF(
        LTRIM(RTRIM(p.MinimumSalaryRaw)),''
    ) IS NULL
    AND NOT EXISTS
    (
        SELECT 1
        FROM control.RecruitmentSalaryOverride o
        WHERE o.JobPostingID = p.JobPostingID
        AND o.SourceRawID = p.LatestRawID
        AND o.ListingRawID = p.LatestListingRawID
    );

    PRINT CONCAT('New corrections: ',@@ROWCOUNT);

    IF
    (
        SELECT COUNT(*)
        FROM silver.vw_RecruitmentStandardizedSalary
        WHERE JobPostingID IN (706,594)
        AND OverrideID IS NOT NULL
        AND IsActive = 1
    ) <> 2
        THROW 50001,'Role salary reconciliation failed.',1;

    COMMIT TRANSACTION;

    SELECT
        JobPostingID,
        JobTitle,
        BaseSalary,
        SalaryFrequency,
        AnnualizedSalary
    FROM silver.vw_RecruitmentStandardizedSalary
    WHERE JobPostingID IN (706,594);

    SELECT
        COUNT(*) AS TotalPostings,
        COUNT(BaseSalary) AS AvailableSalaries,
        COUNT(*) - COUNT(BaseSalary) AS UnresolvedSalaries,
        CAST(
            100.0 * COUNT(BaseSalary) /
            NULLIF(COUNT(*),0)
            AS decimal(5,2)
        ) AS CoveragePercent
    FROM silver.vw_RecruitmentStandardizedSalary
    WHERE IsActive = 1;

    PRINT 'ROLE-SPECIFIC COMPENSATION: PASS';

END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
