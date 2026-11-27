USE IndianaWorkforceDW;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    /* =========================================
       BRONZE: COLLECTION METADATA
       ========================================= */

    IF OBJECT_ID(
        'bronze.StateCareers_Collection', 'U'
    ) IS NULL
    BEGIN
        CREATE TABLE bronze.StateCareers_Collection
        (
            CollectionID BIGINT IDENTITY(1,1)
                PRIMARY KEY,

            CollectionDate DATE NOT NULL,
            StartedUTC DATETIME2(3) NOT NULL
                DEFAULT SYSUTCDATETIME(),

            CompletedUTC DATETIME2(3) NULL,

            SourceURL NVARCHAR(2048) NOT NULL,

            ReportedPostings INT NULL,
            RetrievedPostings INT NULL,
            DetailsRetrieved INT NULL,

            CollectionStatus VARCHAR(20) NOT NULL
                DEFAULT 'RUNNING',

            ErrorMessage NVARCHAR(MAX) NULL,

            CHECK (CollectionStatus IN
            (
                'RUNNING',
                'SUCCEEDED',
                'PARTIAL',
                'FAILED'
            )),

            CHECK (ReportedPostings >= 0),
            CHECK (RetrievedPostings >= 0),
            CHECK (DetailsRetrieved >= 0)
        );
    END;


    /* =========================================
       BRONZE: RAW POSTING OBSERVATIONS
       ========================================= */

    IF OBJECT_ID(
        'bronze.StateCareers_Raw', 'U'
    ) IS NULL
    BEGIN
        CREATE TABLE bronze.StateCareers_Raw
        (
            RawID BIGINT IDENTITY(1,1)
                PRIMARY KEY,

            CollectionID BIGINT NOT NULL,

            SourcePostingID VARCHAR(30) NOT NULL,
            RequisitionIDRaw NVARCHAR(50) NULL,

            JobTitleRaw NVARCHAR(500) NULL,
            LocationRaw NVARCHAR(500) NULL,
            MinimumSalaryRaw NVARCHAR(100) NULL,
            DatePostedRaw NVARCHAR(100) NULL,

            AgencyRaw NVARCHAR(500) NULL,
            AgencyEvidence NVARCHAR(MAX) NULL,

            JobDescriptionRaw NVARCHAR(MAX) NULL,
            ResponsibilitiesRaw NVARCHAR(MAX) NULL,
            QualificationsRaw NVARCHAR(MAX) NULL,

            JobURL NVARCHAR(2048) NOT NULL,

            DetailStatus VARCHAR(30) NULL,

            CollectionUTC DATETIME2(3) NOT NULL,

            RecordHash VARBINARY(32) NULL,

            LoadUTC DATETIME2(3) NOT NULL
                DEFAULT SYSUTCDATETIME(),

            CONSTRAINT FK_SC_Raw_Collection
                FOREIGN KEY (CollectionID)
                REFERENCES
                    bronze.StateCareers_Collection
                    (CollectionID),

            CONSTRAINT UQ_SC_Raw_Observation
                UNIQUE
                (CollectionID, SourcePostingID)
        );
    END;


    /* =========================================
       SILVER: STANDARDIZED JOB POSTINGS
       ========================================= */

    IF OBJECT_ID(
        'silver.StateCareers_JobPosting', 'U'
    ) IS NULL
    BEGIN
        CREATE TABLE silver.StateCareers_JobPosting
        (
            JobPostingID BIGINT IDENTITY(1,1)
                PRIMARY KEY,

            SourcePostingID VARCHAR(30) NOT NULL
                UNIQUE,

            RequisitionID VARCHAR(30) NULL,

            JobTitle NVARCHAR(500) NOT NULL,

            AgencyRaw NVARCHAR(500) NULL,
            AgencyName NVARCHAR(300) NULL,

            City NVARCHAR(150) NULL,
            StateCode CHAR(2) NULL,
            ZIPCode VARCHAR(10) NULL,

            CountyFIPS VARCHAR(5) NULL,
            SOCCode VARCHAR(20) NULL,

            MinimumSalaryRaw NVARCHAR(100) NULL,
            SalaryAmount DECIMAL(18,2) NULL,
            SalaryFrequency VARCHAR(20) NULL,
            AnnualizedSalary DECIMAL(18,2) NULL,

            AnnualizationHours SMALLINT NULL,

            JobDescription NVARCHAR(MAX) NULL,
            Responsibilities NVARCHAR(MAX) NULL,
            Qualifications NVARCHAR(MAX) NULL,

            EducationRequirements NVARCHAR(MAX) NULL,
            ExperienceRequirements NVARCHAR(MAX) NULL,
            CertificationRequirements NVARCHAR(MAX) NULL,
            LicenseRequirements NVARCHAR(MAX) NULL,

            EmploymentType VARCHAR(30) NULL,

            DatePosted DATE NULL,

            FirstSeenUTC DATETIME2(3) NOT NULL,
            LastSeenUTC DATETIME2(3) NOT NULL,
            LastModifiedUTC DATETIME2(3) NULL,
            FirstNotSeenUTC DATETIME2(3) NULL,

            IsActive BIT NOT NULL DEFAULT 1,

            AgencyMappingStatus VARCHAR(20)
                NOT NULL DEFAULT 'PENDING',

            GeographyMappingStatus VARCHAR(20)
                NOT NULL DEFAULT 'PENDING',

            OccupationMappingStatus VARCHAR(20)
                NOT NULL DEFAULT 'PENDING',

            SalaryValidationStatus VARCHAR(20)
                NOT NULL DEFAULT 'PENDING',

            DetailStatus VARCHAR(30) NULL,

            JobURL NVARCHAR(2048) NOT NULL,

            RecordHash VARBINARY(32) NULL,

            LatestRawID BIGINT NOT NULL,

            LoadUTC DATETIME2(3) NOT NULL
                DEFAULT SYSUTCDATETIME(),

            CONSTRAINT FK_SC_Silver_Raw
                FOREIGN KEY (LatestRawID)
                REFERENCES bronze.StateCareers_Raw
                    (RawID),

            CHECK (SalaryAmount >= 0),
            CHECK (AnnualizedSalary >= 0),

            CHECK (SalaryFrequency IN
            (
                'HOURLY',
                'ANNUAL',
                'MONTHLY',
                'BIWEEKLY',
                'WEEKLY',
                'UNKNOWN'
            )),

            CHECK (LastSeenUTC >= FirstSeenUTC)
        );
    END;


    /* =========================================
       SILVER: EXTRACTED JOB SKILLS
       ========================================= */

    IF OBJECT_ID(
        'silver.StateCareers_JobSkill', 'U'
    ) IS NULL
    BEGIN
        CREATE TABLE silver.StateCareers_JobSkill
        (
            JobSkillID BIGINT IDENTITY(1,1)
                PRIMARY KEY,

            JobPostingID BIGINT NOT NULL,

            SkillName NVARCHAR(200) NOT NULL,
            SkillCategory NVARCHAR(100) NULL,

            RequirementType VARCHAR(20)
                NOT NULL DEFAULT 'UNSPECIFIED',

            EvidenceText NVARCHAR(MAX) NULL,

            ExtractionMethod VARCHAR(50) NULL,
            ExtractionVersion VARCHAR(30) NULL,

            LoadUTC DATETIME2(3) NOT NULL
                DEFAULT SYSUTCDATETIME(),

            CONSTRAINT FK_SC_JobSkill_Posting
                FOREIGN KEY (JobPostingID)
                REFERENCES
                    silver.StateCareers_JobPosting
                    (JobPostingID),

            CONSTRAINT UQ_SC_JobSkill
                UNIQUE
                (JobPostingID, SkillName,
                 RequirementType),

            CHECK (RequirementType IN
            (
                'REQUIRED',
                'PREFERRED',
                'UNSPECIFIED'
            ))
        );
    END;


    /* =========================================
       GOLD: AGENCY DIMENSION
       ========================================= */

    IF OBJECT_ID('gold.Dim_Agency', 'U') IS NULL
    BEGIN
        CREATE TABLE gold.Dim_Agency
        (
            AgencyKey INT IDENTITY(1,1)
                PRIMARY KEY,

            AgencyName NVARCHAR(300) NOT NULL
                UNIQUE,

            AgencyAbbreviation VARCHAR(50) NULL,

            IsActive BIT NOT NULL DEFAULT 1,

            CreatedUTC DATETIME2(3) NOT NULL
                DEFAULT SYSUTCDATETIME()
        );
    END;


    /* =========================================
       GOLD: SKILL DIMENSION
       ========================================= */

    IF OBJECT_ID('gold.Dim_Skill', 'U') IS NULL
    BEGIN
        CREATE TABLE gold.Dim_Skill
        (
            SkillKey INT IDENTITY(1,1)
                PRIMARY KEY,

            SkillName NVARCHAR(200) NOT NULL
                UNIQUE,

            SkillCategory NVARCHAR(100) NULL,
            ReferenceCode VARCHAR(50) NULL,
            ReferenceSource VARCHAR(50) NULL,

            CreatedUTC DATETIME2(3) NOT NULL
                DEFAULT SYSUTCDATETIME()
        );
    END;


    /* =========================================
       GOLD: JOB POSTING FACT
       Grain: one source job advertisement
       ========================================= */

    IF OBJECT_ID(
        'gold.Fact_StateJobPosting', 'U'
    ) IS NULL
    BEGIN
        CREATE TABLE gold.Fact_StateJobPosting
        (
            PostingFactKey BIGINT IDENTITY(1,1)
                PRIMARY KEY,

            JobPostingID BIGINT NOT NULL UNIQUE,

            AgencyKey INT NULL,
            GeographyKey INT NULL,
            OccupationKey INT NULL,
            PeriodKey INT NULL,

            DatePosted DATE NULL,

            SalaryAmount DECIMAL(18,2) NULL,
            SalaryFrequency VARCHAR(20) NULL,
            AnnualizedSalary DECIMAL(18,2) NULL,

            FirstSeenUTC DATETIME2(3) NOT NULL,
            LastSeenUTC DATETIME2(3) NOT NULL,
            FirstNotSeenUTC DATETIME2(3) NULL,

            IsActive BIT NOT NULL,

            LoadUTC DATETIME2(3) NOT NULL
                DEFAULT SYSUTCDATETIME(),

            FOREIGN KEY (JobPostingID)
                REFERENCES
                    silver.StateCareers_JobPosting
                    (JobPostingID),

            FOREIGN KEY (AgencyKey)
                REFERENCES gold.Dim_Agency
                    (AgencyKey),

            FOREIGN KEY (GeographyKey)
                REFERENCES gold.Dim_Geography
                    (GeographyKey),

            FOREIGN KEY (OccupationKey)
                REFERENCES gold.Dim_Occupation
                    (OccupationKey),

            FOREIGN KEY (PeriodKey)
                REFERENCES gold.Dim_ReportingPeriod
                    (PeriodKey),

            CHECK (SalaryAmount >= 0),
            CHECK (AnnualizedSalary >= 0)
        );
    END;


    /* =========================================
       GOLD: DAILY RECRUITMENT FACT
       Grain: one validated statewide daily scan
       ========================================= */

    IF OBJECT_ID(
        'gold.Fact_RecruitmentDaily', 'U'
    ) IS NULL
    BEGIN
        CREATE TABLE gold.Fact_RecruitmentDaily
        (
            RecruitmentDailyKey BIGINT IDENTITY(1,1)
                PRIMARY KEY,

            ObservationDate DATE NOT NULL UNIQUE,

            CollectionID BIGINT NOT NULL,

            AdvertisedPostings INT NOT NULL,
            NewlyObservedPostings INT NOT NULL,
            NoLongerObservedPostings INT NOT NULL,
            ReactivatedPostings INT NOT NULL,
            CumulativeUniquePostings INT NOT NULL,

            LoadUTC DATETIME2(3) NOT NULL
                DEFAULT SYSUTCDATETIME(),

            FOREIGN KEY (CollectionID)
                REFERENCES
                    bronze.StateCareers_Collection
                    (CollectionID),

            CHECK (AdvertisedPostings >= 0),
            CHECK (NewlyObservedPostings >= 0),
            CHECK (NoLongerObservedPostings >= 0),
            CHECK (ReactivatedPostings >= 0),

            CHECK (
                CumulativeUniquePostings
                >= AdvertisedPostings
            )
        );
    END;


    /* =========================================
       GOLD: JOB-TO-SKILL BRIDGE
       ========================================= */

    IF OBJECT_ID(
        'gold.Bridge_JobPostingSkill', 'U'
    ) IS NULL
    BEGIN
        CREATE TABLE gold.Bridge_JobPostingSkill
        (
            PostingFactKey BIGINT NOT NULL,
            SkillKey INT NOT NULL,

            RequirementType VARCHAR(20)
                NOT NULL DEFAULT 'UNSPECIFIED',

            PRIMARY KEY
            (
                PostingFactKey,
                SkillKey,
                RequirementType
            ),

            FOREIGN KEY (PostingFactKey)
                REFERENCES gold.Fact_StateJobPosting
                    (PostingFactKey),

            FOREIGN KEY (SkillKey)
                REFERENCES gold.Dim_Skill
                    (SkillKey),

            CHECK (RequirementType IN
            (
                'REQUIRED',
                'PREFERRED',
                'UNSPECIFIED'
            ))
        );
    END;


    /* =========================================
       PERFORMANCE INDEXES
       ========================================= */

    IF NOT EXISTS
    (
        SELECT 1 FROM sys.indexes
        WHERE name = 'IX_SC_Raw_Posting'
        AND object_id =
            OBJECT_ID('bronze.StateCareers_Raw')
    )
    CREATE INDEX IX_SC_Raw_Posting
    ON bronze.StateCareers_Raw
        (SourcePostingID, CollectionUTC);


    IF NOT EXISTS
    (
        SELECT 1 FROM sys.indexes
        WHERE name = 'IX_SC_Silver_Requisition'
        AND object_id =
            OBJECT_ID(
                'silver.StateCareers_JobPosting'
            )
    )
    CREATE INDEX IX_SC_Silver_Requisition
    ON silver.StateCareers_JobPosting
        (RequisitionID);


    IF NOT EXISTS
    (
        SELECT 1 FROM sys.indexes
        WHERE name = 'IX_SC_Fact_ActiveDate'
        AND object_id =
            OBJECT_ID('gold.Fact_StateJobPosting')
    )
    CREATE INDEX IX_SC_Fact_ActiveDate
    ON gold.Fact_StateJobPosting
        (IsActive, DatePosted)
    INCLUDE
        (AgencyKey, GeographyKey,
         OccupationKey, AnnualizedSalary);


    IF NOT EXISTS
    (
        SELECT 1 FROM sys.indexes
        WHERE name = 'IX_SC_Bridge_Skill'
        AND object_id =
            OBJECT_ID(
                'gold.Bridge_JobPostingSkill'
            )
    )
    CREATE INDEX IX_SC_Bridge_Skill
    ON gold.Bridge_JobPostingSkill
        (SkillKey, PostingFactKey);


    /* =========================================
       GOVERNANCE SOURCE REGISTRATION
       ========================================= */

    IF NOT EXISTS
    (
        SELECT 1
        FROM control.DataSource
        WHERE SourceCode = 'STATE_CAREERS'
    )
    BEGIN
        INSERT INTO control.DataSource
        (
            SourceCode,
            SourceName,
            IngestionMethod,
            Classification,
            IsActive,
            CreatedUTC
        )
        VALUES
        (
            'STATE_CAREERS',
            N'State of Indiana Careers Website',
            'HTTPS_HTML',
            'PUBLIC',
            1,
            SYSUTCDATETIME()
        );
    END;

    COMMIT TRANSACTION;

    PRINT 'MEDALLION DEPLOYMENT SUCCESSFUL';

END TRY
BEGIN CATCH

    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    THROW;

END CATCH;
GO


/* =========================================
   POST-DEPLOYMENT VALIDATION
   ========================================= */

PRINT '=== RECRUITMENT TABLE VALIDATION ===';

SELECT
    SCHEMA_NAME(t.schema_id) AS SchemaName,
    t.name AS TableName,
    SUM(p.rows) AS RecordCount
FROM sys.tables t
JOIN sys.partitions p
    ON t.object_id = p.object_id
WHERE p.index_id IN (0,1)
AND t.name IN
(
    'StateCareers_Collection',
    'StateCareers_Raw',
    'StateCareers_JobPosting',
    'StateCareers_JobSkill',
    'Dim_Agency',
    'Dim_Skill',
    'Fact_StateJobPosting',
    'Fact_RecruitmentDaily',
    'Bridge_JobPostingSkill'
)
GROUP BY t.schema_id, t.name
ORDER BY SchemaName, TableName;


PRINT '=== SOURCE REGISTRY ===';

SELECT
    SourceID,
    SourceCode,
    SourceName,
    IngestionMethod,
    Classification,
    IsActive
FROM control.DataSource
ORDER BY SourceID;


PRINT '=== FOREIGN KEY VALIDATION ===';

SELECT
    SCHEMA_NAME(t.schema_id) AS SchemaName,
    t.name AS TableName,
    COUNT(*) AS ForeignKeyCount
FROM sys.foreign_keys fk
JOIN sys.tables t
    ON fk.parent_object_id = t.object_id
WHERE t.name IN
(
    'StateCareers_Raw',
    'StateCareers_JobPosting',
    'StateCareers_JobSkill',
    'Fact_StateJobPosting',
    'Fact_RecruitmentDaily',
    'Bridge_JobPostingSkill'
)
GROUP BY t.schema_id, t.name
ORDER BY SchemaName, TableName;


PRINT '=== DEPLOYMENT VALIDATION COMPLETE ===';
GO
