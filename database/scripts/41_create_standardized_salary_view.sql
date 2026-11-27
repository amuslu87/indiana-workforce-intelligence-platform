USE IndianaWorkforceDW;
GO

CREATE OR ALTER VIEW silver.vw_RecruitmentStandardizedSalary
AS

WITH SalarySource AS
(
    SELECT
        p.JobPostingID,
        p.JobTitle,
        p.MinimumSalaryRaw,
        p.LatestRawID,
        p.LatestListingRawID,
        p.IsActive,

        o.OverrideID,
        o.ApprovedBaseSalary,
        o.SalaryFrequency AS OverrideFrequency,
        o.FrequencyBasis AS OverrideFrequencyBasis,
        o.CorrectionType,

        s.BaseSalary AS ParsedBaseSalary,
        s.SalaryFrequency AS ParsedFrequency,
        s.ParsingStatus

    FROM silver.StateCareers_JobPosting p

    CROSS APPLY
        control.fn_ParseBaseSalary(p.MinimumSalaryRaw) s

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
),

Classified AS
(
    SELECT *,

        CASE
            WHEN OverrideID IS NOT NULL
                THEN ApprovedBaseSalary

            WHEN MinimumSalaryRaw LIKE '%83,00.00%'
                THEN NULL

            ELSE ParsedBaseSalary
        END AS BaseSalary,

        CASE
            WHEN OverrideID IS NOT NULL
                THEN OverrideFrequency

            WHEN MinimumSalaryRaw LIKE '%83,00.00%'
                THEN 'UNKNOWN'

            WHEN ParsedFrequency = 'UNKNOWN'
                 AND ParsedBaseSalary IS NOT NULL
                THEN 'ANNUAL'

            ELSE ParsedFrequency
        END AS SalaryFrequency,

        CASE
            WHEN OverrideID IS NOT NULL
                THEN OverrideFrequencyBasis

            WHEN MinimumSalaryRaw LIKE '%83,00.00%'
                THEN 'UNRESOLVED'

            WHEN ParsedFrequency = 'UNKNOWN'
                 AND ParsedBaseSalary IS NOT NULL
                THEN 'SOURCE_ASSUMPTION'

            WHEN ParsedBaseSalary IS NOT NULL
                THEN 'EXPLICIT'

            ELSE 'UNRESOLVED'
        END AS FrequencyBasis,

        CASE
            WHEN OverrideID IS NOT NULL
                THEN CorrectionType

            WHEN MinimumSalaryRaw LIKE '%83,00.00%'
                THEN 'REVIEW_REQUIRED'

            WHEN ParsedBaseSalary IS NULL
                THEN 'REVIEW_REQUIRED'

            WHEN ParsedFrequency = 'UNKNOWN'
                THEN 'ANNUAL_ASSUMPTION'

            ELSE ParsingStatus
        END AS StandardizationMethod

    FROM SalarySource
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
        CASE
            WHEN SalaryFrequency = 'HOURLY'
                THEN BaseSalary * 1950

            WHEN SalaryFrequency = 'ANNUAL'
                THEN BaseSalary

            WHEN SalaryFrequency = 'MONTHLY'
                THEN BaseSalary * 12

            WHEN SalaryFrequency = 'BIWEEKLY'
                THEN BaseSalary * 26

            ELSE NULL
        END AS decimal(18,2)
    ) AS AnnualizedSalary,

    CASE
        WHEN SalaryFrequency = 'HOURLY'
             AND BaseSalary IS NOT NULL
            THEN 1950
        ELSE NULL
    END AS AnnualizationHours

FROM Classified;
GO

-- Validate coverage
SELECT
    SalaryFrequency,
    FrequencyBasis,
    StandardizationMethod,
    COUNT(*) AS Postings,
    MIN(BaseSalary) AS MinimumBase,
    MAX(BaseSalary) AS MaximumBase
FROM silver.vw_RecruitmentStandardizedSalary
WHERE IsActive = 1
GROUP BY
    SalaryFrequency,
    FrequencyBasis,
    StandardizationMethod;
GO

-- Validate total coverage and uniqueness
SELECT
    COUNT(*) AS TotalPostings,
    COUNT(DISTINCT JobPostingID) AS UniquePostings,
    COUNT(BaseSalary) AS AvailableSalaries,
    COUNT(*) - COUNT(BaseSalary) AS UnresolvedSalaries,
    CAST(
        100.0 * COUNT(BaseSalary) /
        NULLIF(COUNT(*),0)
        AS decimal(5,2)
    ) AS CoveragePercent
FROM silver.vw_RecruitmentStandardizedSalary
WHERE IsActive = 1;
GO

PRINT 'STANDARDIZED COMPENSATION VIEW CREATED';
GO
