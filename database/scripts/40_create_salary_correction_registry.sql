USE IndianaWorkforceDW;
GO

SET XACT_ABORT ON;
BEGIN TRANSACTION;

IF OBJECT_ID('control.RecruitmentSalaryOverride','U') IS NULL
BEGIN
    CREATE TABLE control.RecruitmentSalaryOverride
    (
        OverrideID bigint IDENTITY(1,1) PRIMARY KEY,

        JobPostingID bigint NOT NULL
            REFERENCES silver.StateCareers_JobPosting(JobPostingID),

        SourceRawID bigint NOT NULL
            REFERENCES bronze.StateCareers_Raw(RawID),

        ListingRawID bigint NOT NULL
            REFERENCES bronze.StateCareers_Raw(RawID),

        OriginalSalaryRaw nvarchar(100) NULL,

        ApprovedBaseSalary decimal(18,2) NOT NULL
            CHECK (ApprovedBaseSalary > 0),

        SalaryFrequency varchar(20) NOT NULL
            CHECK (SalaryFrequency IN
                ('ANNUAL','HOURLY','MONTHLY','BIWEEKLY')),

        FrequencyBasis varchar(30) NOT NULL
            CHECK (FrequencyBasis IN
                ('EXPLICIT','SOURCE_ASSUMPTION')),

        CorrectionType varchar(30) NOT NULL
            CHECK (CorrectionType IN
                ('SOURCE_CORRECTION','DESCRIPTION_RECOVERY')),

        Evidence nvarchar(2000) NOT NULL,

        IsActive bit NOT NULL DEFAULT 1,

        ReviewedBy sysname NOT NULL DEFAULT ORIGINAL_LOGIN(),

        ReviewedUTC datetime2(3) NOT NULL
            DEFAULT SYSUTCDATETIME(),

        CONSTRAINT UQ_RecruitmentSalaryOverride
            UNIQUE (JobPostingID,SourceRawID,ListingRawID)
    );
END;

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
    v.Evidence
FROM silver.StateCareers_JobPosting p
JOIN
(
    VALUES
    (
        622,83000.00,'ANNUAL','SOURCE_ASSUMPTION',
        'SOURCE_CORRECTION',
        N'Listing contains malformed $83,00.00.
        Description states starting salary of $83,000.00.'
    ),
    (
        636,90000.00,'ANNUAL','SOURCE_ASSUMPTION',
        'SOURCE_CORRECTION',
        N'Listing contains malformed $83,00.00.
        Description states starting salary of $90,000.00.'
    ),
    (
        597,12.65,'HOURLY','EXPLICIT',
        'DESCRIPTION_RECOVERY',
        N'Explicitly recruiting cooks and dishwashers.
        Dishwasher base $12.65/hour; cook base $15/hour.
        Minimum recruited base retained.'
    ),
    (
        816,50414.00,'ANNUAL','SOURCE_ASSUMPTION',
        'DESCRIPTION_RECOVERY',
        N'Description salary range $50,414 to $90,582.
        Minimum qualification-based salary retained.'
    ),
    (
        845,13.00,'HOURLY','EXPLICIT',
        'DESCRIPTION_RECOVERY',
        N'Description salary range $13-$17 per hour.
        Seasonal employment limited to 180 calendar days.'
    )
) v
(
    JobPostingID,BaseSalary,Frequency,
    FrequencyBasis,CorrectionType,Evidence
)
ON p.JobPostingID = v.JobPostingID

WHERE p.IsActive = 1
AND
(
    (
        p.JobPostingID IN (622,636)
        AND p.MinimumSalaryRaw = '$83,00.00'
    )
    OR
    (
        p.JobPostingID IN (597,816,845)
        AND NULLIF(LTRIM(RTRIM(p.MinimumSalaryRaw)),'') IS NULL
    )
)
AND NOT EXISTS
(
    SELECT 1
    FROM control.RecruitmentSalaryOverride o
    WHERE o.JobPostingID = p.JobPostingID
    AND o.SourceRawID = p.LatestRawID
    AND o.ListingRawID = p.LatestListingRawID
);

IF
(
    SELECT COUNT(*)
    FROM control.RecruitmentSalaryOverride o
    JOIN silver.StateCareers_JobPosting p
        ON p.JobPostingID = o.JobPostingID
        AND p.LatestRawID = o.SourceRawID
        AND p.LatestListingRawID = o.ListingRawID
    WHERE o.IsActive = 1
    AND p.JobPostingID IN (622,636,597,816,845)
) <> 5
BEGIN
    THROW 50001,'Salary correction reconciliation failed.',1;
END;

COMMIT TRANSACTION;

SELECT
    o.OverrideID,
    p.JobTitle,
    o.OriginalSalaryRaw,
    o.ApprovedBaseSalary,
    o.SalaryFrequency,
    o.FrequencyBasis,
    o.CorrectionType
FROM control.RecruitmentSalaryOverride o
JOIN silver.StateCareers_JobPosting p
    ON p.JobPostingID = o.JobPostingID
ORDER BY o.OverrideID;

PRINT 'SALARY CORRECTION REGISTRY: PASS';
GO
