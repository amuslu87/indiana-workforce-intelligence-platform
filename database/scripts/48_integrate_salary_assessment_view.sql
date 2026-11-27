USE IndianaWorkforceDW;
GO

CREATE OR ALTER VIEW silver.vw_RecruitmentStandardizedSalary
AS

WITH Classified AS
(
    SELECT
        p.JobPostingID,
        p.JobTitle,
        p.MinimumSalaryRaw,
        p.LatestRawID,
        p.LatestListingRawID,
        o.OverrideID,
        p.IsActive,

        CASE
            WHEN o.OverrideID IS NOT NULL
                THEN o.ApprovedBaseSalary
            ELSE a.BaseSalary
        END AS BaseSalary,

        CASE
            WHEN o.OverrideID IS NOT NULL
                THEN o.SalaryFrequency
            ELSE COALESCE(a.SalaryFrequency,'UNKNOWN')
        END AS SalaryFrequency,

        CASE
            WHEN o.OverrideID IS NOT NULL
                THEN o.FrequencyBasis
            ELSE COALESCE(a.FrequencyBasis,'UNRESOLVED')
        END AS FrequencyBasis,

        CASE
            WHEN o.OverrideID IS NOT NULL
                THEN o.CorrectionType
            ELSE COALESCE(
                a.StandardizationMethod,
                'REVIEW_REQUIRED'
            )
        END AS StandardizationMethod,

        CASE
            WHEN o.OverrideID IS NOT NULL
                THEN o.Evidence
            ELSE a.Evidence
        END AS SalaryEvidence,

        a.ParserVersion,
        a.AssessmentID

    FROM silver.StateCareers_JobPosting p

    LEFT JOIN control.RecruitmentSalaryAssessment a
        ON a.JobPostingID = p.JobPostingID
        AND a.SourceRawID = p.LatestRawID
        AND a.ListingRawID = p.LatestListingRawID

    OUTER APPLY
    (
        SELECT TOP 1 r.*
        FROM control.RecruitmentSalaryOverride r
        WHERE r.JobPostingID = p.JobPostingID
        AND r.SourceRawID = p.LatestRawID
        AND r.IsActive = 1
        AND
        (
            r.OriginalSalaryRaw = p.MinimumSalaryRaw
            OR
            (
                r.OriginalSalaryRaw IS NULL
                AND p.MinimumSalaryRaw IS NULL
            )
        )
        ORDER BY r.ReviewedUTC DESC,r.OverrideID DESC
    ) o
)

SELECT
    JobPostingID,
    JobTitle,
    MinimumSalaryRaw,
    LatestRawID,
    LatestListingRawID,
    OverrideID,
    IsActive,
    BaseSalary,
    SalaryFrequency,
    FrequencyBasis,
    StandardizationMethod,

    CAST(
        CASE SalaryFrequency
            WHEN 'HOURLY' THEN BaseSalary * 1950
            WHEN 'ANNUAL' THEN BaseSalary
            WHEN 'MONTHLY' THEN BaseSalary * 12
            WHEN 'BIWEEKLY' THEN BaseSalary * 26
            ELSE NULL
        END AS decimal(18,2)
    ) AS AnnualizedSalary,

    CASE
        WHEN SalaryFrequency = 'HOURLY'
             AND BaseSalary IS NOT NULL
        THEN 1950
        ELSE NULL
    END AS AnnualizationHours,

    SalaryEvidence,
    ParserVersion,
    AssessmentID

FROM Classified;
GO

SET NOCOUNT ON;

SELECT
    StandardizationMethod,
    FrequencyBasis,
    COUNT(*) AS Postings
FROM silver.vw_RecruitmentStandardizedSalary
WHERE IsActive = 1
GROUP BY StandardizationMethod, FrequencyBasis
ORDER BY StandardizationMethod, FrequencyBasis;

SELECT
    COUNT(*) AS TotalPostings,
    COUNT(DISTINCT JobPostingID) AS UniquePostings,
    COUNT(AssessmentID) AS AssessedPostings,
    COUNT(OverrideID) AS ReviewedOverrides,
    COUNT(BaseSalary) AS AvailableSalaries,
    COUNT(*) - COUNT(BaseSalary) AS UnresolvedSalaries,
    CAST(
        100.0 * COUNT(BaseSalary) /
        NULLIF(COUNT(*),0)
        AS decimal(5,2)
    ) AS CoveragePercent
FROM silver.vw_RecruitmentStandardizedSalary
WHERE IsActive = 1;

-- Blocking validation
IF EXISTS
(
    SELECT JobPostingID
    FROM silver.vw_RecruitmentStandardizedSalary
    GROUP BY JobPostingID
    HAVING COUNT(*) > 1
)
    THROW 50001,'Duplicate salary records detected.',1;

IF EXISTS
(
    SELECT 1
    FROM silver.vw_RecruitmentStandardizedSalary
    WHERE IsActive = 1
    AND AssessmentID IS NULL
)
    THROW 50002,'Missing current salary assessments.',1;

PRINT 'DESCRIPTION-FIRST SALARY VIEW: PASS';
GO
