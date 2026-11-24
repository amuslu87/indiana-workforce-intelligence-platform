USE IndianaWorkforceDW;
GO
SET XACT_ABORT ON;
BEGIN TRY
BEGIN TRAN;
IF SCHEMA_ID('control') IS NULL EXEC('CREATE SCHEMA control AUTHORIZATION dbo');
IF SCHEMA_ID('quarantine') IS NULL EXEC('CREATE SCHEMA quarantine AUTHORIZATION dbo');
IF OBJECT_ID('control.DataSource','U') IS NULL
CREATE TABLE control.DataSource(
 SourceID int IDENTITY PRIMARY KEY, SourceCode varchar(50) NOT NULL UNIQUE,
 SourceName nvarchar(200) NOT NULL, IngestionMethod varchar(30) NOT NULL,
 Classification varchar(30) NOT NULL DEFAULT 'PUBLIC', IsActive bit NOT NULL DEFAULT 1,
 CreatedUTC datetime2 NOT NULL DEFAULT SYSUTCDATETIME());
IF OBJECT_ID('control.PipelineRun','U') IS NULL
CREATE TABLE control.PipelineRun(
 RunID bigint IDENTITY PRIMARY KEY, SourceID int NOT NULL REFERENCES control.DataSource(SourceID),
 StartedUTC datetime2 NOT NULL DEFAULT SYSUTCDATETIME(), EndedUTC datetime2 NULL,
 Status varchar(20) NOT NULL DEFAULT 'RUNNING' CHECK(Status IN ('RUNNING','SUCCEEDED','FAILED','REJECTED')),
 RowsReceived bigint NULL CHECK(RowsReceived>=0), RowsAccepted bigint NULL CHECK(RowsAccepted>=0),
 RowsRejected bigint NULL CHECK(RowsRejected>=0), ErrorMessage nvarchar(max) NULL,
 CONSTRAINT UQ_PipelineRun_Source UNIQUE(SourceID,RunID));
IF OBJECT_ID('control.DataQualityRule','U') IS NULL
CREATE TABLE control.DataQualityRule(
 RuleID int IDENTITY PRIMARY KEY, RuleCode varchar(60) NOT NULL UNIQUE,
 RuleDescription nvarchar(500) NOT NULL, IsBlocking bit NOT NULL DEFAULT 1, IsActive bit NOT NULL DEFAULT 1);
IF OBJECT_ID('control.DataQualityResult','U') IS NULL
CREATE TABLE control.DataQualityResult(
 ResultID bigint IDENTITY PRIMARY KEY, RunID bigint NOT NULL REFERENCES control.PipelineRun(RunID),
 RuleID int NOT NULL REFERENCES control.DataQualityRule(RuleID),
 Outcome varchar(10) NOT NULL CHECK(Outcome IN ('PASS','FAIL','WARN')),
 FailedCount bigint NOT NULL DEFAULT 0 CHECK(FailedCount>=0), Details nvarchar(max) NULL,
 CheckedUTC datetime2 NOT NULL DEFAULT SYSUTCDATETIME(), UNIQUE(RunID,RuleID));
IF OBJECT_ID('quarantine.RejectedObservation','U') IS NULL
CREATE TABLE quarantine.RejectedObservation(
 RejectionID bigint IDENTITY PRIMARY KEY, RunID bigint NOT NULL REFERENCES control.PipelineRun(RunID),
 RuleID int NULL REFERENCES control.DataQualityRule(RuleID), SourceRecordKey nvarchar(300) NULL,
 RawPayload nvarchar(max) NULL, RejectionReason nvarchar(1000) NOT NULL,
 RejectedUTC datetime2 NOT NULL DEFAULT SYSUTCDATETIME(),
 ResolutionStatus varchar(20) NOT NULL DEFAULT 'OPEN' CHECK(ResolutionStatus IN ('OPEN','RESOLVED','DISMISSED')));
IF OBJECT_ID('control.PublishedBatch','U') IS NULL
CREATE TABLE control.PublishedBatch(
 SourceID int NOT NULL PRIMARY KEY, RunID bigint NOT NULL,
 PublishedUTC datetime2 NOT NULL DEFAULT SYSUTCDATETIME(),
 FOREIGN KEY(SourceID,RunID) REFERENCES control.PipelineRun(SourceID,RunID));
INSERT control.DataSource(SourceCode,SourceName,IngestionMethod)
SELECT v.Code,v.Name,v.Method FROM (VALUES
 ('STATS_LAUS','STATS Indiana LAUS','FLAT_FILE'),('BLS_LAUS','BLS LAUS','REST_API'),
 ('BLS_OEWS','BLS OEWS','REMOTE_FILE'),('IDWD_PROJECTION','IDWD occupational projections','FLAT_FILE')) v(Code,Name,Method)
WHERE NOT EXISTS(SELECT 1 FROM control.DataSource s WHERE s.SourceCode=v.Code);
INSERT control.DataQualityRule(RuleCode,RuleDescription,IsBlocking)
SELECT v.Code,v.Description,v.Blocking FROM (VALUES
 ('SCHEMA','Required fields and compatible data types',1),('UNIQUENESS','No duplicate business keys',1),
 ('DOMAIN','Values satisfy source-specific business rules',1),('LINEAGE','Source lineage is complete',1),
 ('RECONCILIATION','Accepted records reconcile across layers',1),('COMPLETENESS','Required source coverage is present',1),
 ('FRESHNESS','Data freshness meets source-specific expectations',0)) v(Code,Description,Blocking)
WHERE NOT EXISTS(SELECT 1 FROM control.DataQualityRule r WHERE r.RuleCode=v.Code);
EXEC(N'CREATE OR ALTER VIEW control.vw_PipelineHealth AS
SELECT s.SourceCode,s.SourceName,r.RunID,r.Status,r.StartedUTC,r.EndedUTC,r.RowsReceived,r.RowsAccepted,r.RowsRejected,r.ErrorMessage,p.RunID AS PublishedRunID,p.PublishedUTC
FROM control.DataSource s OUTER APPLY (SELECT TOP (1) * FROM control.PipelineRun x WHERE x.SourceID=s.SourceID ORDER BY x.RunID DESC) r
LEFT JOIN control.PublishedBatch p ON p.SourceID=s.SourceID');
COMMIT;
END TRY
BEGIN CATCH
 IF @@TRANCOUNT>0 ROLLBACK;
 THROW;
END CATCH;
GO
SELECT * FROM control.DataSource;
SELECT * FROM control.DataQualityRule;
SELECT * FROM control.vw_PipelineHealth;
GO


---Active Data Quality Enforcement
USE IndianaWorkforceDW;

SELECT * FROM control.DataSource;
SELECT * FROM control.DataQualityRule;
SELECT * FROM control.vw_PipelineHealth;

--
USE IndianaWorkforceDW;

SELECT
    TABLE_SCHEMA,
    TABLE_NAME,
    COLUMN_NAME,
    DATA_TYPE,
    IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA IN (
    'bronze',
    'silver',
    'gold',
    'control',
    'quarantine'
)
ORDER BY
    TABLE_SCHEMA,
    TABLE_NAME,
    ORDINAL_POSITION;