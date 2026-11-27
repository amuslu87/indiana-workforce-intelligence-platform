USE IndianaWorkforceDW;
GO

SET NOCOUNT ON;

SELECT
    p.JobPostingID,
    p.JobTitle,
    p.MinimumSalaryRaw,

    CASE
        WHEN p.JobPostingID = 622
             AND p.MinimumSalaryRaw = '$83,00.00'
            THEN 83000.00

        WHEN p.JobPostingID = 636
             AND p.MinimumSalaryRaw = '$83,00.00'
            THEN 90000.00

        WHEN p.JobPostingID = 597
             AND s.ParsingStatus = 'MISSING'
            THEN 12.65

        WHEN p.JobPostingID = 816
             AND s.ParsingStatus = 'MISSING'
            THEN 50414.00

        WHEN p.JobPostingID = 845
             AND s.ParsingStatus = 'MISSING'
            THEN 13.00

        ELSE s.BaseSalary
    END AS BaseSalary,

    CASE
        WHEN p.JobPostingID IN (597,845)
             AND s.ParsingStatus = 'MISSING'
            THEN 'HOURLY'

        WHEN p.JobPostingID = 816
             AND s.ParsingStatus = 'MISSING'
            THEN 'ANNUAL'

        WHEN s.SalaryFrequency = 'UNKNOWN'
             AND s.BaseSalary IS NOT NULL
            THEN 'ANNUAL'

        ELSE s.SalaryFrequency
    END AS SalaryFrequency,

    CASE
        WHEN p.JobPostingID IN (622,636)
             AND p.MinimumSalaryRaw = '$83,00.00'
            THEN 'SOURCE_CORRECTION'

        WHEN p.JobPostingID IN (597,816,845)
             AND s.ParsingStatus = 'MISSING'
            THEN 'DESCRIPTION_RECOVERY'

        WHEN s.ParsingStatus = 'MISSING'
            THEN 'REVIEW_REQUIRED'

        WHEN s.SalaryFrequency = 'UNKNOWN'
             AND s.BaseSalary IS NOT NULL
            THEN 'ANNUAL_ASSUMPTION'

        ELSE s.ParsingStatus
    END AS StandardizationMethod

INTO #SalaryPreview

FROM silver.StateCareers_JobPosting p
CROSS APPLY
    control.fn_ParseBaseSalary(p.MinimumSalaryRaw) s
WHERE p.IsActive = 1;

-- Coverage summary
SELECT
    SalaryFrequency,
    StandardizationMethod,
    COUNT(*) AS Postings,
    MIN(BaseSalary) AS MinimumBase,
    MAX(BaseSalary) AS MaximumBase
FROM #SalaryPreview
GROUP BY SalaryFrequency,StandardizationMethod
ORDER BY StandardizationMethod;

-- Review recovered and unresolved salaries
SELECT *
FROM #SalaryPreview
WHERE StandardizationMethod IN (
    'SOURCE_CORRECTION',
    'DESCRIPTION_RECOVERY',
    'REVIEW_REQUIRED'
)
ORDER BY StandardizationMethod,JobTitle;

-- Overall coverage
SELECT
    COUNT(*) AS TotalPostings,
    COUNT(BaseSalary) AS AvailableBaseSalaries,
    COUNT(*) - COUNT(BaseSalary) AS UnresolvedSalaries,
    CAST(
        100.0 * COUNT(BaseSalary) / COUNT(*)
        AS decimal(5,2)
    ) AS SalaryCoveragePercent
FROM #SalaryPreview;

DROP TABLE #SalaryPreview;
GO
