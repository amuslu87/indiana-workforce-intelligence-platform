USE IndianaWorkforceDW;
GO

IF OBJECT_ID(
    'control.RecruitmentSalaryAssessment', 'U'
) IS NULL
BEGIN

    CREATE TABLE control.RecruitmentSalaryAssessment
    (
        AssessmentID bigint IDENTITY(1,1) PRIMARY KEY,

        JobPostingID bigint NOT NULL,

        SourceRawID bigint NOT NULL,

        ListingRawID bigint NOT NULL,

        BaseSalary decimal(18,2) NULL,

        SalaryFrequency varchar(20) NOT NULL,

        FrequencyBasis varchar(30) NOT NULL,

        StandardizationMethod varchar(40) NOT NULL,

        Evidence nvarchar(max) NULL,

        ParserVersion varchar(30) NOT NULL,

        CandidateCount int NOT NULL,

        AssessedUTC datetime2(3) NOT NULL
            DEFAULT SYSUTCDATETIME(),

        CONSTRAINT FK_SalaryAssessment_Posting
            FOREIGN KEY (JobPostingID)
            REFERENCES silver.StateCareers_JobPosting(JobPostingID),

        CONSTRAINT FK_SalaryAssessment_Detail
            FOREIGN KEY (SourceRawID)
            REFERENCES bronze.StateCareers_Raw(RawID),

        CONSTRAINT FK_SalaryAssessment_Listing
            FOREIGN KEY (ListingRawID)
            REFERENCES bronze.StateCareers_Raw(RawID),

        CONSTRAINT UQ_SalaryAssessment_Source
            UNIQUE (JobPostingID, SourceRawID, ListingRawID),

        CONSTRAINT CK_SalaryAssessment_Amount
            CHECK (BaseSalary > 0 OR BaseSalary IS NULL),

        CONSTRAINT CK_SalaryAssessment_Frequency
            CHECK (SalaryFrequency IN
            (
                'ANNUAL','HOURLY','MONTHLY',
                'BIWEEKLY','UNKNOWN'
            )),

        CONSTRAINT CK_SalaryAssessment_Basis
            CHECK (FrequencyBasis IN
            (
                'EXPLICIT',
                'SOURCE_ASSUMPTION',
                'UNRESOLVED'
            )),

        CONSTRAINT CK_SalaryAssessment_Method
            CHECK (StandardizationMethod IN
            (
                'DESCRIPTION_BASE',
                'LISTING_FALLBACK',
                'AMBIGUOUS_DESCRIPTION',
                'REVIEW_REQUIRED'
            )),

        CONSTRAINT CK_SalaryAssessment_Candidates
            CHECK (CandidateCount >= 0),

        CONSTRAINT CK_SalaryAssessment_Consistency
            CHECK
            (
                (
                    BaseSalary IS NULL
                    AND SalaryFrequency = 'UNKNOWN'
                    AND FrequencyBasis = 'UNRESOLVED'
                )
                OR
                (
                    BaseSalary IS NOT NULL
                    AND SalaryFrequency <> 'UNKNOWN'
                    AND FrequencyBasis <> 'UNRESOLVED'
                )
            )
    );

END;
GO

SELECT
    OBJECT_ID(
        'control.RecruitmentSalaryAssessment'
    ) AS TableObjectID,
    COUNT(*) AS CurrentAssessments
FROM control.RecruitmentSalaryAssessment;
GO

PRINT 'SALARY ASSESSMENT TABLE: READY';
GO
