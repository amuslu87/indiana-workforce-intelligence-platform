USE IndianaWorkforceDW;
GO

-- Gold Geography Dimension
CREATE TABLE gold.Dim_Geography
(
    GeographyKey INT IDENTITY(1,1) NOT NULL,

    FIPSCode VARCHAR(5) NOT NULL,
    GeographyName VARCHAR(100) NOT NULL,
    GeographyType VARCHAR(10) NOT NULL,

    CONSTRAINT PK_Gold_Dim_Geography
        PRIMARY KEY (GeographyKey),

    CONSTRAINT UQ_Gold_Dim_Geography_FIPS
        UNIQUE (FIPSCode),

    CONSTRAINT CK_Gold_Dim_Geography_Type
        CHECK (GeographyType IN ('State', 'County'))
);
GO

-- Gold Reporting Period Dimension
CREATE TABLE gold.Dim_ReportingPeriod
(
    PeriodKey INT IDENTITY(1,1) NOT NULL,

    ReportingYear SMALLINT NOT NULL,
    MonthCode TINYINT NOT NULL,
    ReportingMonth VARCHAR(20) NOT NULL,
    PeriodType VARCHAR(20) NOT NULL,

    CONSTRAINT PK_Gold_Dim_ReportingPeriod
        PRIMARY KEY (PeriodKey),

    CONSTRAINT UQ_Gold_Dim_ReportingPeriod
        UNIQUE (ReportingYear, MonthCode),

    CONSTRAINT CK_Gold_Dim_ReportingPeriod_Month
        CHECK (MonthCode BETWEEN 1 AND 13),

    CONSTRAINT CK_Gold_Dim_ReportingPeriod_Type
        CHECK (
            (MonthCode BETWEEN 1 AND 12 AND PeriodType = 'Monthly')
            OR
            (MonthCode = 13 AND PeriodType = 'Annual Average')
        )
);
GO

-- Gold Unemployment Fact Table
CREATE TABLE gold.Fact_Unemployment
(
    UnemploymentFactKey BIGINT IDENTITY(1,1) NOT NULL,

    GeographyKey INT NOT NULL,
    PeriodKey INT NOT NULL,

    UnemploymentRate DECIMAL(5,2) NOT NULL,

    SilverLausID BIGINT NOT NULL,

    LoadTimestamp DATETIME2 NOT NULL
        DEFAULT SYSUTCDATETIME(),

    CONSTRAINT PK_Gold_Fact_Unemployment
        PRIMARY KEY (UnemploymentFactKey),

    -- Enforce one observation per geography and period
    CONSTRAINT UQ_Gold_Fact_Unemployment_Grain
        UNIQUE (GeographyKey, PeriodKey),

    -- Link to Geography dimension
    CONSTRAINT FK_Gold_Fact_Geography
        FOREIGN KEY (GeographyKey)
        REFERENCES gold.Dim_Geography(GeographyKey),

    -- Link to Reporting Period dimension
    CONSTRAINT FK_Gold_Fact_Period
        FOREIGN KEY (PeriodKey)
        REFERENCES gold.Dim_ReportingPeriod(PeriodKey),

    -- Preserve lineage to Silver
    CONSTRAINT FK_Gold_Fact_Silver
        FOREIGN KEY (SilverLausID)
        REFERENCES silver.Laus_Unemployment(LausID),

    -- Validate unemployment rates
    CONSTRAINT CK_Gold_Fact_UnemploymentRate
        CHECK (UnemploymentRate BETWEEN 0 AND 100)
);
GO