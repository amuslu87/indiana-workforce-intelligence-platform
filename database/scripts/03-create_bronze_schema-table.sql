USE IndianaWorkforceDW;
GO

CREATE TABLE bronze.Employment_Raw (
    RawID BIGINT IDENTITY(1,1) PRIMARY KEY,
    SourceSystem VARCHAR(100) NOT NULL,
    SourceRecordID VARCHAR(100) NULL,
    CountyCode VARCHAR(20) NULL,
    IndustryCode VARCHAR(20) NULL,
    ReportingYear VARCHAR(10) NULL,
    EmploymentCount VARCHAR(50) NULL,
    AverageWage VARCHAR(50) NULL,
    IngestionTimestamp DATETIME2 DEFAULT SYSUTCDATETIME()
);
GO
