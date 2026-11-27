USE IndianaWorkforceDW;
GO

CREATE OR ALTER VIEW serving.vw_RecruitmentCompensation
AS

SELECT
    p.JobPostingID,
    p.JobTitle,
    CAST(NULL AS bigint) AS CompensationID,
    CAST(NULL AS nvarchar(300)) AS RoleName,
    s.BaseSalary AS SalaryAmount,
    s.SalaryFrequency,
    s.AnnualizedSalary,
    s.AnnualizationHours,
    CAST(NULL AS bit) AS TipsEligible,
    s.SalaryEvidence,
    s.FrequencyBasis,
    s.StandardizationMethod,
    p.SalaryValidationStatus,
    p.MinimumSalaryRaw,
    s.ParserVersion

FROM serving.vw_StateRecruitment p

JOIN silver.vw_RecruitmentStandardizedSalary s
    ON p.JobPostingID = s.JobPostingID

WHERE p.ObservedActive = 1;
GO

GRANT SELECT
ON serving.vw_RecruitmentCompensation
TO rl_dashboard_reader;
GO

SET NOCOUNT ON;

SELECT
    SalaryFrequency,
    FrequencyBasis,
    SalaryValidationStatus,
    COUNT(*) AS Postings
FROM serving.vw_RecruitmentCompensation
GROUP BY
    SalaryFrequency,
    FrequencyBasis,
    SalaryValidationStatus;

SELECT
    COUNT(*) AS TotalPostings,
    COUNT(DISTINCT JobPostingID) AS UniquePostings,
    COUNT(SalaryAmount) AS AvailableSalaries,
    COUNT(*) - COUNT(SalaryAmount) AS UnresolvedSalaries,
    CAST(
        100.0 * COUNT(SalaryAmount) /
        NULLIF(COUNT(*),0)
        AS decimal(5,2)
    ) AS CoveragePercent
FROM serving.vw_RecruitmentCompensation;

EXECUTE AS USER = 'usr_dashboard_test';

SELECT COUNT(*) AS DashboardAccessibleRecords
FROM serving.vw_RecruitmentCompensation;

REVERT;

PRINT 'COMPENSATION SERVING VIEW: READY';
GO
