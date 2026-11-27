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
        v.FrequencyBasis,
        v.CorrectionType,
        e.SalaryEvidence
    FROM silver.StateCareers_JobPosting p
    JOIN
    (
        VALUES
        (802,45422.00,'ANNUAL','SOURCE_ASSUMPTION',
            'SOURCE_CORRECTION'),
        (753,42900.00,'ANNUAL','SOURCE_ASSUMPTION',
            'SOURCE_CORRECTION'),
        (858,12.65,'HOURLY','EXPLICIT',
            'DESCRIPTION_RECOVERY'),
        (605,12.65,'HOURLY','EXPLICIT',
            'DESCRIPTION_RECOVERY'),
        (704,13.29,'HOURLY','EXPLICIT',
            'DESCRIPTION_RECOVERY')
    ) v
    (
        JobPostingID,BaseSalary,Frequency,
        FrequencyBasis,CorrectionType
    )
        ON p.JobPostingID = v.JobPostingID

    CROSS APPLY
    (
        SELECT TOP 1
            LEFT(c.SalaryEvidence,2000) AS SalaryEvidence
        FROM silver.StateCareers_JobCompensation c
        WHERE c.JobPostingID = p.JobPostingID
        AND c.SourceRawID = p.LatestRawID
        AND c.SalaryAmount = v.BaseSalary
        AND TRY_CONVERT(
            decimal(18,2),
            REPLACE(
                control.fn_DescriptionBaseSalary(
                    c.SalaryEvidence
                ),',',''
            )
        ) = v.BaseSalary
        AND
        (
            v.FrequencyBasis = 'SOURCE_ASSUMPTION'
            OR c.SalaryFrequency = v.Frequency
        )
        ORDER BY c.CompensationID
    ) e

    WHERE p.IsActive = 1
    AND
    (
        (p.JobPostingID = 802
            AND p.MinimumSalaryRaw = '$45,222.00')
        OR
        (p.JobPostingID = 753
            AND p.MinimumSalaryRaw = '$47,900.00')
        OR
        (p.JobPostingID IN (858,605,704)
            AND NULLIF(
                LTRIM(RTRIM(p.MinimumSalaryRaw)),''
            ) IS NULL)
    )
    AND NOT EXISTS
    (
        SELECT 1
        FROM control.RecruitmentSalaryOverride o
        WHERE o.JobPostingID = p.JobPostingID
        AND o.SourceRawID = p.LatestRawID
        AND o.ListingRawID = p.LatestListingRawID
    );

    PRINT CONCAT('New corrections registered: ',@@ROWCOUNT);

    IF
    (
        SELECT COUNT(DISTINCT JobPostingID)
        FROM silver.vw_RecruitmentStandardizedSalary
        WHERE IsActive = 1
        AND OverrideID IS NOT NULL
        AND JobPostingID IN (802,753,858,605,704)
    ) <> 5
        THROW 50001,'Correction reconciliation failed.',1;

    COMMIT TRANSACTION;

    SELECT
        JobPostingID,
        JobTitle,
        MinimumSalaryRaw,
        BaseSalary,
        SalaryFrequency,
        StandardizationMethod
    FROM silver.vw_RecruitmentStandardizedSalary
    WHERE JobPostingID IN (802,753,858,605,704);

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

    PRINT 'ADDITIONAL SALARY CORRECTIONS: PASS';

END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
