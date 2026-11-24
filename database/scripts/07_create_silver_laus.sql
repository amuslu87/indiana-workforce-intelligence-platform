USE IndianaWorkforceDW;
GO

CREATE TABLE silver.Laus_Unemployment
(
    -- Unique identifier for each Silver record
    LausID BIGINT IDENTITY(1,1) PRIMARY KEY,

    -- Geographic information
    Geography VARCHAR(100) NOT NULL,
    FIPSCode VARCHAR(5) NOT NULL,
    GeographyType VARCHAR(10) NOT NULL,

    -- Reporting period
    ReportingYear SMALLINT NOT NULL,
    MonthCode TINYINT NOT NULL,
    ReportingMonth VARCHAR(20) NOT NULL,
    PeriodType VARCHAR(20) NOT NULL,

    -- Validated unemployment rate
    UnemploymentRate DECIMAL(5,2) NOT NULL,

    -- Source lineage
    BronzeRawID BIGINT NOT NULL,
    SourceFile VARCHAR(255) NOT NULL,

    -- Transformation metadata
    TransformationTimestamp DATETIME2 NOT NULL
        DEFAULT SYSUTCDATETIME(),

    -- Prevent duplicate business observations
    CONSTRAINT UQ_Silver_Laus_BusinessKey
        UNIQUE (FIPSCode, ReportingYear, MonthCode),

    -- Validate unemployment rate
    CONSTRAINT CK_Silver_Laus_Rate
        CHECK (UnemploymentRate BETWEEN 0 AND 100),

    -- Validate reporting periods
    CONSTRAINT CK_Silver_Laus_MonthCode
        CHECK (MonthCode BETWEEN 1 AND 13),

    -- Restrict geographic classification
    CONSTRAINT CK_Silver_Laus_GeographyType
        CHECK (GeographyType IN ('State', 'County')),

    -- Restrict reporting-period classification
    CONSTRAINT CK_Silver_Laus_PeriodType
        CHECK (PeriodType IN ('Monthly', 'Annual Average')),
        -- Ensure reporting period classification matches MonthCode
    CONSTRAINT CK_Silver_Laus_PeriodConsistency
        CHECK (
         (MonthCode BETWEEN 1 AND 12 AND PeriodType = 'Monthly') OR
         (MonthCode = 13 AND PeriodType = 'Annual Average')),

    -- Maintain traceability to the Bronze record
    CONSTRAINT FK_Silver_Laus_Bronze
        FOREIGN KEY (BronzeRawID)
        REFERENCES bronze.Laus_Unemployment_Raw(RawID)
);
GO

