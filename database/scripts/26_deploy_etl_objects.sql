USE IndianaWorkforceDW;
GO
SET XACT_ABORT ON;
GO
IF OBJECT_ID('bronze.BLS_LAUS_API_Raw','U') IS NULL
    CREATE TABLE bronze.BLS_LAUS_API_Raw (
      BronzeBLSID BIGINT IDENTITY(1,1) PRIMARY KEY,
      SeriesID VARCHAR(30) NOT NULL,
      ReportingYear SMALLINT NOT NULL,
      PeriodCode VARCHAR(3) NOT NULL,
      RawValue VARCHAR(60) NOT NULL,
      RawObservationJson NVARCHAR(MAX) NOT NULL,
      SourceURL VARCHAR(500) NOT NULL,
      IngestedAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
      CONSTRAINT UQ_BLS_Bronze_SeriesPeriod UNIQUE (SeriesID,ReportingYear,PeriodCode)
    )
GO
IF OBJECT_ID('silver.BLS_LAUS_Indiana','U') IS NULL
    CREATE TABLE silver.BLS_LAUS_Indiana (
      SilverBLSID BIGINT IDENTITY(1,1) PRIMARY KEY,
      BronzeBLSID BIGINT NOT NULL UNIQUE,
      SeriesID VARCHAR(30) NOT NULL,
      FIPSCode CHAR(5) NOT NULL DEFAULT '18000',
      ReportingYear SMALLINT NOT NULL,
      MonthCode TINYINT NOT NULL,
      ReportingDate DATE NOT NULL,
      MeasureCode VARCHAR(40) NOT NULL,
      MeasureUnit VARCHAR(15) NOT NULL,
      MeasureValue DECIMAL(18,3) NOT NULL,
      TransformedAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
      CONSTRAINT FK_BLS_Silver_Bronze FOREIGN KEY (BronzeBLSID)
        REFERENCES bronze.BLS_LAUS_API_Raw(BronzeBLSID),
      CONSTRAINT UQ_BLS_Silver_SeriesDate UNIQUE(SeriesID,ReportingDate),
      CONSTRAINT CK_BLS_Silver_Month CHECK(MonthCode BETWEEN 1 AND 12),
      CONSTRAINT CK_BLS_Silver_Value CHECK(MeasureValue >= 0)
    )
GO
IF OBJECT_ID('gold.Dim_BLS_Measure','U') IS NULL
    CREATE TABLE gold.Dim_BLS_Measure (
      MeasureKey INT IDENTITY(1,1) PRIMARY KEY,
      SeriesID VARCHAR(30) NOT NULL UNIQUE,
      MeasureCode VARCHAR(40) NOT NULL UNIQUE,
      MeasureUnit VARCHAR(15) NOT NULL
    )
GO
IF OBJECT_ID('gold.Dim_BLS_ReportingPeriod','U') IS NULL
    CREATE TABLE gold.Dim_BLS_ReportingPeriod (
      BLSPeriodKey INT IDENTITY(1,1) PRIMARY KEY,
      ReportingYear SMALLINT NOT NULL,
      MonthCode TINYINT NOT NULL,
      ReportingDate DATE NOT NULL UNIQUE,
      CONSTRAINT UQ_BLS_Period_YearMonth UNIQUE(ReportingYear,MonthCode),
      CONSTRAINT CK_BLS_Period_Month CHECK(MonthCode BETWEEN 1 AND 12)
    )
GO
IF OBJECT_ID('gold.Fact_BLS_LaborMarket','U') IS NULL
    CREATE TABLE gold.Fact_BLS_LaborMarket (
      BLSFactKey BIGINT IDENTITY(1,1) PRIMARY KEY,
      SilverBLSID BIGINT NOT NULL UNIQUE,
      GeographyKey INT NOT NULL,
      BLSPeriodKey INT NOT NULL,
      MeasureKey INT NOT NULL,
      MeasureValue DECIMAL(18,3) NOT NULL,
      LoadedAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
      CONSTRAINT FK_BLS_Fact_Silver FOREIGN KEY(SilverBLSID)
        REFERENCES silver.BLS_LAUS_Indiana(SilverBLSID),
      CONSTRAINT FK_BLS_Fact_Geography FOREIGN KEY(GeographyKey)
        REFERENCES gold.Dim_Geography(GeographyKey),
      CONSTRAINT FK_BLS_Fact_Period FOREIGN KEY(BLSPeriodKey)
        REFERENCES gold.Dim_BLS_ReportingPeriod(BLSPeriodKey),
      CONSTRAINT FK_BLS_Fact_Measure FOREIGN KEY(MeasureKey)
        REFERENCES gold.Dim_BLS_Measure(MeasureKey),
      CONSTRAINT UQ_BLS_Fact_Grain UNIQUE(GeographyKey,BLSPeriodKey,MeasureKey)
    )
GO
IF OBJECT_ID('bronze.BLS_API_IngestionRun','U') IS NULL
    CREATE TABLE bronze.BLS_API_IngestionRun (
      RunID BIGINT IDENTITY(1,1) PRIMARY KEY,
      StartedAt DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
      CompletedAt DATETIME2(3) NULL,
      RunStatus VARCHAR(20) NOT NULL,
      SeriesRequested INT NOT NULL,
      ObservationsReceived INT NULL,
      BronzeInserted INT NULL,
      SilverInserted INT NULL,
      GoldInserted INT NULL,
      ErrorMessage NVARCHAR(2000) NULL
    )
GO
IF OBJECT_ID('bronze.BLS_OEWS_Raw','U') IS NULL CREATE TABLE bronze.BLS_OEWS_Raw (
        RawID BIGINT IDENTITY(1,1) PRIMARY KEY, ReferenceYear INT NOT NULL, AreaCode VARCHAR(12) NOT NULL,
        OccupationCode VARCHAR(20) NOT NULL, OccupationTitle NVARCHAR(300) NOT NULL,
        RawJSON NVARCHAR(MAX) NOT NULL, SourceURL NVARCHAR(1000) NOT NULL,
        SourceSHA256 CHAR(64) NOT NULL, IngestedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
        CONSTRAINT UQ_BLS_OEWS_Raw UNIQUE(ReferenceYear,AreaCode,OccupationCode))
GO
IF OBJECT_ID('silver.BLS_OEWS_Indiana','U') IS NULL CREATE TABLE silver.BLS_OEWS_Indiana (
        SilverID BIGINT IDENTITY(1,1) PRIMARY KEY, RawID BIGINT NOT NULL UNIQUE REFERENCES bronze.BLS_OEWS_Raw(RawID),
        ReferenceYear INT NOT NULL, OccupationCode VARCHAR(20) NOT NULL, OccupationTitle NVARCHAR(300) NOT NULL,
        OccupationGroup NVARCHAR(80) NULL, EmploymentEstimate FLOAT NULL, MeanHourlyWage FLOAT NULL,
        MeanAnnualWage FLOAT NULL, MedianHourlyWage FLOAT NULL, MedianAnnualWage FLOAT NULL,
        AnnualP10 FLOAT NULL, AnnualP25 FLOAT NULL, AnnualP75 FLOAT NULL, AnnualP90 FLOAT NULL,
        CONSTRAINT UQ_BLS_OEWS_Silver UNIQUE(ReferenceYear,OccupationCode))
GO
IF OBJECT_ID('gold.Dim_Occupation','U') IS NULL CREATE TABLE gold.Dim_Occupation (
        OccupationKey INT IDENTITY(1,1) PRIMARY KEY, OccupationCode VARCHAR(20) NOT NULL UNIQUE,
        OccupationTitle NVARCHAR(300) NOT NULL, OccupationGroup NVARCHAR(80) NULL)
GO
IF OBJECT_ID('gold.Fact_OccupationalWages','U') IS NULL CREATE TABLE gold.Fact_OccupationalWages (
        FactKey BIGINT IDENTITY(1,1) PRIMARY KEY, SilverID BIGINT NOT NULL UNIQUE REFERENCES silver.BLS_OEWS_Indiana(SilverID),
        OccupationKey INT NOT NULL REFERENCES gold.Dim_Occupation(OccupationKey),
        ReferenceYear INT NOT NULL, GeographyCode VARCHAR(12) NOT NULL DEFAULT '18',
        EmploymentEstimate FLOAT NULL, MeanAnnualWage FLOAT NULL, MedianAnnualWage FLOAT NULL,
        AnnualP10 FLOAT NULL, AnnualP25 FLOAT NULL, AnnualP75 FLOAT NULL, AnnualP90 FLOAT NULL,
        CONSTRAINT UQ_BLS_OEWS_Gold UNIQUE(ReferenceYear,GeographyCode,OccupationKey))
GO
IF OBJECT_ID('bronze.IDWD_Projection_Raw','U') IS NULL CREATE TABLE bronze.IDWD_Projection_Raw (RawID BIGINT IDENTITY PRIMARY KEY, ProjectionYear INT NOT NULL, OccupationCode VARCHAR(20) NOT NULL, RawJSON NVARCHAR(MAX) NOT NULL, SourceFile NVARCHAR(260) NOT NULL, SourceSHA256 CHAR(64) NOT NULL, LoadedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(), UNIQUE(ProjectionYear,OccupationCode))
GO
IF OBJECT_ID('silver.IDWD_OccupationalProjection','U') IS NULL CREATE TABLE silver.IDWD_OccupationalProjection (SilverID BIGINT IDENTITY PRIMARY KEY, RawID BIGINT NOT NULL UNIQUE REFERENCES bronze.IDWD_Projection_Raw(RawID), ProjectionYear INT NOT NULL, BaseYear INT NULL, OccupationCode VARCHAR(20) NOT NULL, OccupationTitle NVARCHAR(300) NOT NULL, BaseEmployment INT NOT NULL CHECK(BaseEmployment>=0), ProjectedEmployment INT NOT NULL CHECK(ProjectedEmployment>=0), UNIQUE(ProjectionYear,OccupationCode))
GO
IF OBJECT_ID('gold.Fact_OccupationalProjection','U') IS NULL CREATE TABLE gold.Fact_OccupationalProjection (FactKey BIGINT IDENTITY PRIMARY KEY, SilverID BIGINT NOT NULL UNIQUE REFERENCES silver.IDWD_OccupationalProjection(SilverID), OccupationKey INT NOT NULL REFERENCES gold.Dim_Occupation(OccupationKey), GeographyCode VARCHAR(12) NOT NULL, BaseYear INT NULL, ProjectionYear INT NOT NULL, BaseEmployment INT NOT NULL, ProjectedEmployment INT NOT NULL, UNIQUE(GeographyCode,ProjectionYear,OccupationKey))
GO
CREATE OR ALTER VIEW gold.vw_OccupationalOpportunity AS SELECT d.OccupationCode,d.OccupationTitle,d.OccupationGroup,p.GeographyCode,p.BaseYear,p.ProjectionYear,p.BaseEmployment,p.ProjectedEmployment,p.ProjectedEmployment-p.BaseEmployment AS NetEmploymentGrowth,100.0*(p.ProjectedEmployment-p.BaseEmployment)/NULLIF(p.BaseEmployment,0) AS ProjectedGrowthPct,w.ReferenceYear AS WageReferenceYear,w.EmploymentEstimate,w.MedianAnnualWage,w.MeanAnnualWage FROM gold.Fact_OccupationalProjection p JOIN gold.Dim_Occupation d ON d.OccupationKey=p.OccupationKey LEFT JOIN gold.Fact_OccupationalWages w ON w.OccupationKey=p.OccupationKey AND w.GeographyCode=p.GeographyCode AND w.ReferenceYear=2025
GO
