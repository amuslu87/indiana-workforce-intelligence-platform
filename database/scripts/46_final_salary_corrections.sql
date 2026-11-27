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
        v.Frequency,
        'EXPLICIT',
        'SOURCE_CORRECTION',
        LEFT(c.SalaryEvidence,2000)
    FROM silver.StateCareers_JobPosting p
    JOIN
    (
        VALUES
        (685,59800.00,'ANNUAL',
            N'%annual salary of $59,800%'),
        (643,14.25,'HOURLY',
            N'%hourly wage%starting at $14.25/hour%')
    ) v(JobPostingID,BaseSalary,Frequency,EvidencePattern)
        ON p.JobPostingID = v.JobPostingID
    CROSS APPLY
    (
        SELECT TOP 1 c.SalaryEvidence
        FROM silver.StateCareers_JobCompensation c
        WHERE c.JobPostingID = p.JobPostingID
        AND c.SourceRawID = p.LatestRawID
        AND c.SalaryAmount = v.BaseSalary
        AND c.SalaryEvidence LIKE v.EvidencePattern
        ORDER BY c.CompensationID
    ) c
    WHERE p.IsActive = 1
    AND NOT EXISTS
    (
        SELECT 1
        FROM control.RecruitmentSalaryOverride o
        WHERE o.JobPostingID = p.JobPostingID
        AND o.SourceRawID = p.LatestRawID
        AND o.ListingRawID = p.LatestListingRawID
    );

    PRINT CONCAT('Final corrections registered: ',@@ROWCOUNT);

    IF
    (
        SELECT COUNT(*)
        FROM silver.vw_RecruitmentStandardizedSalary
        WHERE IsActive = 1
        AND OverrideID IS NOT NULL
        AND
        (
            (JobPostingID = 685
                AND BaseSalary = 59800
                AND SalaryFrequency = 'ANNUAL')
            OR
            (JobPostingID = 643
                AND BaseSalary = 14.25
                AND SalaryFrequency = 'HOURLY')
        )
    ) <> 2
        THROW 50001,'Final correction reconciliation failed.',1;

    COMMIT TRANSACTION;

    SELECT
        JobPostingID,
        JobTitle,
        MinimumSalaryRaw,
        BaseSalary,
        SalaryFrequency,
        AnnualizedSalary
    FROM silver.vw_RecruitmentStandardizedSalary
    WHERE JobPostingID IN (685,643);

    PRINT 'FINAL SALARY CORRECTIONS: PASS';

END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
