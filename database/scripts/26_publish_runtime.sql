USE IndianaWorkforceDW;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

-- Run during a maintenance window.
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
BEGIN TRY
BEGIN TRAN;
DECLARE @LockResult int;
EXEC @LockResult=sys.sp_getapplock @Resource='WorkforcePublication', @LockMode='Exclusive', @LockOwner='Transaction', @LockTimeout=10000;
IF @LockResult<0 THROW 51000,'Publication lock unavailable',1;
DECLARE @Before bigint=(SELECT ISNULL(MAX(RunID),0) FROM control.PipelineRun);
DECLARE @RunID bigint, @SourceID int,
        @B bigint, @S bigint, @G bigint;

DROP TABLE IF EXISTS #Checks;
DROP TABLE IF EXISTS #Bad;

CREATE TABLE #Checks (
    RuleCode varchar(60),
    FailedCount bigint,
    Details nvarchar(1000)
);

CREATE TABLE #Bad (
    RecordKey nvarchar(300),
    Payload nvarchar(max)
);

-- STATS_LAUS
DELETE FROM #Checks; DELETE FROM #Bad;
SELECT @SourceID=SourceID FROM control.DataSource WHERE SourceCode='STATS_LAUS';
INSERT control.PipelineRun(SourceID) VALUES(@SourceID);
SET @RunID=CONVERT(bigint,SCOPE_IDENTITY());
BEGIN TRY
BEGIN TRAN;
SELECT @B=COUNT_BIG(*) FROM bronze.Laus_Unemployment_Raw WITH (HOLDLOCK);
SELECT @S=COUNT_BIG(*) FROM silver.Laus_Unemployment WITH (HOLDLOCK);
SELECT @G=COUNT_BIG(*) FROM gold.Fact_Unemployment WITH (HOLDLOCK);
INSERT #Checks VALUES ('SCHEMA',0,N'Expected columns referenced successfully; full source contract not assessed');
INSERT #Checks SELECT 'UNIQUENESS',COUNT_BIG(*),N'Duplicate Silver business-key groups' FROM (SELECT FIPSCode,ReportingYear,MonthCode FROM silver.Laus_Unemployment GROUP BY FIPSCode,ReportingYear,MonthCode HAVING COUNT_BIG(*)>1) d;
INSERT #Bad SELECT CONVERT(nvarchar(300),s.LausID),(SELECT s.* FOR JSON PATH,WITHOUT_ARRAY_WRAPPER) FROM silver.Laus_Unemployment s WHERE UnemploymentRate NOT BETWEEN 0 AND 100;
INSERT #Checks SELECT 'DOMAIN',COUNT_BIG(*),N'Silver records violating domain rules' FROM #Bad;
INSERT #Checks SELECT 'LINEAGE', (SELECT COUNT_BIG(*) FROM silver.Laus_Unemployment s LEFT JOIN bronze.Laus_Unemployment_Raw b ON b.RawID=s.BronzeRawID WHERE b.RawID IS NULL)+(SELECT COUNT_BIG(*) FROM gold.Fact_Unemployment g LEFT JOIN silver.Laus_Unemployment s ON s.LausID=g.SilverLausID WHERE s.LausID IS NULL),N'Orphaned Silver or Gold lineage';
INSERT #Checks SELECT 'RECONCILIATION', (SELECT COUNT_BIG(*) FROM silver.Laus_Unemployment s JOIN gold.Fact_Unemployment g ON s.LausID=g.SilverLausID WHERE s.UnemploymentRate<>g.UnemploymentRate)+ABS(@B-@S)+ABS(@S-@G),N'Count differences and Silver/Gold measure mismatches';
INSERT #Checks VALUES ('COMPLETENESS',CASE WHEN @S<4372 THEN 4372-@S ELSE 0 END,N'Baseline minimum row count only; full expected coverage not assessed');
INSERT #Checks VALUES ('FRESHNESS',1,N'Publication calendar not configured; freshness requires review');
INSERT control.DataQualityResult(RunID,RuleID,Outcome,FailedCount,Details)
SELECT @RunID,r.RuleID,CASE WHEN c.FailedCount=0 THEN 'PASS' WHEN r.IsBlocking=1 THEN 'FAIL' ELSE 'WARN' END,c.FailedCount,c.Details FROM #Checks c JOIN control.DataQualityRule r ON r.RuleCode=c.RuleCode WHERE r.IsActive=1;
INSERT quarantine.RejectedObservation(RunID,RuleID,SourceRecordKey,RawPayload,RejectionReason)
SELECT @RunID,r.RuleID,b.RecordKey,b.Payload,N'Silver domain validation failed; diagnostic copy only' FROM #Bad b CROSS JOIN control.DataQualityRule r WHERE r.RuleCode='DOMAIN' AND r.IsActive=1;
UPDATE control.PipelineRun SET EndedUTC=SYSUTCDATETIME(),Status=CASE WHEN EXISTS(SELECT 1 FROM control.DataQualityResult WHERE RunID=@RunID AND Outcome='FAIL') THEN 'REJECTED' ELSE 'SUCCEEDED' END,ErrorMessage=N'Baseline assessment of existing warehouse; not an ingestion or publication run' WHERE RunID=@RunID;
COMMIT;
END TRY
BEGIN CATCH
THROW;
END CATCH;

-- BLS_LAUS
DELETE FROM #Checks; DELETE FROM #Bad;
SELECT @SourceID=SourceID FROM control.DataSource WHERE SourceCode='BLS_LAUS';
INSERT control.PipelineRun(SourceID) VALUES(@SourceID);
SET @RunID=CONVERT(bigint,SCOPE_IDENTITY());
BEGIN TRY
BEGIN TRAN;
SELECT @B=COUNT_BIG(*) FROM bronze.BLS_LAUS_API_Raw WITH (HOLDLOCK);
SELECT @S=COUNT_BIG(*) FROM silver.BLS_LAUS_Indiana WITH (HOLDLOCK);
SELECT @G=COUNT_BIG(*) FROM gold.Fact_BLS_LaborMarket WITH (HOLDLOCK);
INSERT #Checks VALUES ('SCHEMA',0,N'Expected columns referenced successfully; full source contract not assessed');
INSERT #Checks SELECT 'UNIQUENESS',COUNT_BIG(*),N'Duplicate Silver business-key groups' FROM (SELECT SeriesID,ReportingYear,MonthCode FROM silver.BLS_LAUS_Indiana GROUP BY SeriesID,ReportingYear,MonthCode HAVING COUNT_BIG(*)>1) d;
INSERT #Bad SELECT CONVERT(nvarchar(300),s.SilverBLSID),(SELECT s.* FOR JSON PATH,WITHOUT_ARRAY_WRAPPER) FROM silver.BLS_LAUS_Indiana s WHERE MeasureValue<0 OR (MeasureCode='UNEMPLOYMENT_RATE' AND MeasureValue>100) OR MonthCode NOT BETWEEN 1 AND 12;
INSERT #Checks SELECT 'DOMAIN',COUNT_BIG(*),N'Silver records violating domain rules' FROM #Bad;
INSERT #Checks SELECT 'LINEAGE', (SELECT COUNT_BIG(*) FROM silver.BLS_LAUS_Indiana s LEFT JOIN bronze.BLS_LAUS_API_Raw b ON b.BronzeBLSID=s.BronzeBLSID WHERE b.BronzeBLSID IS NULL)+(SELECT COUNT_BIG(*) FROM gold.Fact_BLS_LaborMarket g LEFT JOIN silver.BLS_LAUS_Indiana s ON s.SilverBLSID=g.SilverBLSID WHERE s.SilverBLSID IS NULL),N'Orphaned Silver or Gold lineage';
INSERT #Checks SELECT 'RECONCILIATION', (SELECT COUNT_BIG(*) FROM silver.BLS_LAUS_Indiana s JOIN gold.Fact_BLS_LaborMarket g ON s.SilverBLSID=g.SilverBLSID WHERE s.MeasureValue<>g.MeasureValue)+ABS(@B-@S)+ABS(@S-@G),N'Count differences and Silver/Gold measure mismatches';
INSERT #Checks VALUES ('COMPLETENESS',CASE WHEN @S<132 THEN 132-@S ELSE 0 END,N'Baseline minimum row count only; full expected coverage not assessed');
INSERT #Checks VALUES ('FRESHNESS',1,N'Publication calendar not configured; freshness requires review');
INSERT control.DataQualityResult(RunID,RuleID,Outcome,FailedCount,Details)
SELECT @RunID,r.RuleID,CASE WHEN c.FailedCount=0 THEN 'PASS' WHEN r.IsBlocking=1 THEN 'FAIL' ELSE 'WARN' END,c.FailedCount,c.Details FROM #Checks c JOIN control.DataQualityRule r ON r.RuleCode=c.RuleCode WHERE r.IsActive=1;
INSERT quarantine.RejectedObservation(RunID,RuleID,SourceRecordKey,RawPayload,RejectionReason)
SELECT @RunID,r.RuleID,b.RecordKey,b.Payload,N'Silver domain validation failed; diagnostic copy only' FROM #Bad b CROSS JOIN control.DataQualityRule r WHERE r.RuleCode='DOMAIN' AND r.IsActive=1;
UPDATE control.PipelineRun SET EndedUTC=SYSUTCDATETIME(),Status=CASE WHEN EXISTS(SELECT 1 FROM control.DataQualityResult WHERE RunID=@RunID AND Outcome='FAIL') THEN 'REJECTED' ELSE 'SUCCEEDED' END,ErrorMessage=N'Baseline assessment of existing warehouse; not an ingestion or publication run' WHERE RunID=@RunID;
COMMIT;
END TRY
BEGIN CATCH
THROW;
END CATCH;

-- BLS_OEWS
DELETE FROM #Checks; DELETE FROM #Bad;
SELECT @SourceID=SourceID FROM control.DataSource WHERE SourceCode='BLS_OEWS';
INSERT control.PipelineRun(SourceID) VALUES(@SourceID);
SET @RunID=CONVERT(bigint,SCOPE_IDENTITY());
BEGIN TRY
BEGIN TRAN;
SELECT @B=COUNT_BIG(*) FROM bronze.BLS_OEWS_Raw WITH (HOLDLOCK);
SELECT @S=COUNT_BIG(*) FROM silver.BLS_OEWS_Indiana WITH (HOLDLOCK);
SELECT @G=COUNT_BIG(*) FROM gold.Fact_OccupationalWages WITH (HOLDLOCK);
INSERT #Checks VALUES ('SCHEMA',0,N'Expected columns referenced successfully; full source contract not assessed');
INSERT #Checks SELECT 'UNIQUENESS',COUNT_BIG(*),N'Duplicate Silver business-key groups' FROM (SELECT ReferenceYear,OccupationCode FROM silver.BLS_OEWS_Indiana GROUP BY ReferenceYear,OccupationCode HAVING COUNT_BIG(*)>1) d;
INSERT #Bad SELECT CONVERT(nvarchar(300),s.SilverID),(SELECT s.* FOR JSON PATH,WITHOUT_ARRAY_WRAPPER) FROM silver.BLS_OEWS_Indiana s WHERE EmploymentEstimate<0 OR MeanAnnualWage<0 OR MedianAnnualWage<0 OR AnnualP10<0 OR AnnualP10>AnnualP25 OR AnnualP25>MedianAnnualWage OR MedianAnnualWage>AnnualP75 OR AnnualP75>AnnualP90;
INSERT #Checks SELECT 'DOMAIN',COUNT_BIG(*),N'Silver records violating domain rules' FROM #Bad;
INSERT #Checks SELECT 'LINEAGE', (SELECT COUNT_BIG(*) FROM silver.BLS_OEWS_Indiana s LEFT JOIN bronze.BLS_OEWS_Raw b ON b.RawID=s.RawID WHERE b.RawID IS NULL)+(SELECT COUNT_BIG(*) FROM gold.Fact_OccupationalWages g LEFT JOIN silver.BLS_OEWS_Indiana s ON s.SilverID=g.SilverID WHERE s.SilverID IS NULL),N'Orphaned Silver or Gold lineage';
INSERT #Checks SELECT 'RECONCILIATION', (SELECT COUNT_BIG(*) FROM silver.BLS_OEWS_Indiana s JOIN gold.Fact_OccupationalWages g ON s.SilverID=g.SilverID WHERE EXISTS (SELECT s.EmploymentEstimate,s.MeanAnnualWage,s.MedianAnnualWage,s.AnnualP10,s.AnnualP25,s.AnnualP75,s.AnnualP90 EXCEPT SELECT g.EmploymentEstimate,g.MeanAnnualWage,g.MedianAnnualWage,g.AnnualP10,g.AnnualP25,g.AnnualP75,g.AnnualP90))+ABS(@B-@S)+ABS(@S-@G),N'Count differences and Silver/Gold measure mismatches';
INSERT #Checks VALUES ('COMPLETENESS',CASE WHEN @S<784 THEN 784-@S ELSE 0 END,N'Baseline minimum row count only; full expected coverage not assessed');
INSERT #Checks VALUES ('FRESHNESS',1,N'Publication calendar not configured; freshness requires review');
INSERT control.DataQualityResult(RunID,RuleID,Outcome,FailedCount,Details)
SELECT @RunID,r.RuleID,CASE WHEN c.FailedCount=0 THEN 'PASS' WHEN r.IsBlocking=1 THEN 'FAIL' ELSE 'WARN' END,c.FailedCount,c.Details FROM #Checks c JOIN control.DataQualityRule r ON r.RuleCode=c.RuleCode WHERE r.IsActive=1;
INSERT quarantine.RejectedObservation(RunID,RuleID,SourceRecordKey,RawPayload,RejectionReason)
SELECT @RunID,r.RuleID,b.RecordKey,b.Payload,N'Silver domain validation failed; diagnostic copy only' FROM #Bad b CROSS JOIN control.DataQualityRule r WHERE r.RuleCode='DOMAIN' AND r.IsActive=1;
UPDATE control.PipelineRun SET EndedUTC=SYSUTCDATETIME(),Status=CASE WHEN EXISTS(SELECT 1 FROM control.DataQualityResult WHERE RunID=@RunID AND Outcome='FAIL') THEN 'REJECTED' ELSE 'SUCCEEDED' END,ErrorMessage=N'Baseline assessment of existing warehouse; not an ingestion or publication run' WHERE RunID=@RunID;
COMMIT;
END TRY
BEGIN CATCH
THROW;
END CATCH;

-- IDWD_PROJECTION
DELETE FROM #Checks; DELETE FROM #Bad;
SELECT @SourceID=SourceID FROM control.DataSource WHERE SourceCode='IDWD_PROJECTION';
INSERT control.PipelineRun(SourceID) VALUES(@SourceID);
SET @RunID=CONVERT(bigint,SCOPE_IDENTITY());
BEGIN TRY
BEGIN TRAN;
SELECT @B=COUNT_BIG(*) FROM bronze.IDWD_Projection_Raw WITH (HOLDLOCK);
SELECT @S=COUNT_BIG(*) FROM silver.IDWD_OccupationalProjection WITH (HOLDLOCK);
SELECT @G=COUNT_BIG(*) FROM gold.Fact_OccupationalProjection WITH (HOLDLOCK);
INSERT #Checks VALUES ('SCHEMA',0,N'Expected columns referenced successfully; full source contract not assessed');
INSERT #Checks SELECT 'UNIQUENESS',COUNT_BIG(*),N'Duplicate Silver business-key groups' FROM (SELECT ProjectionYear,OccupationCode FROM silver.IDWD_OccupationalProjection GROUP BY ProjectionYear,OccupationCode HAVING COUNT_BIG(*)>1) d;
INSERT #Bad SELECT CONVERT(nvarchar(300),s.SilverID),(SELECT s.* FOR JSON PATH,WITHOUT_ARRAY_WRAPPER) FROM silver.IDWD_OccupationalProjection s WHERE BaseEmployment<0 OR ProjectedEmployment<0 OR BaseYear>=ProjectionYear;
INSERT #Checks SELECT 'DOMAIN',COUNT_BIG(*),N'Silver records violating domain rules' FROM #Bad;
INSERT #Checks SELECT 'LINEAGE', (SELECT COUNT_BIG(*) FROM silver.IDWD_OccupationalProjection s LEFT JOIN bronze.IDWD_Projection_Raw b ON b.RawID=s.RawID WHERE b.RawID IS NULL)+(SELECT COUNT_BIG(*) FROM gold.Fact_OccupationalProjection g LEFT JOIN silver.IDWD_OccupationalProjection s ON s.SilverID=g.SilverID WHERE s.SilverID IS NULL),N'Orphaned Silver or Gold lineage';
INSERT #Checks SELECT 'RECONCILIATION', (SELECT COUNT_BIG(*) FROM silver.IDWD_OccupationalProjection s JOIN gold.Fact_OccupationalProjection g ON s.SilverID=g.SilverID WHERE s.BaseEmployment<>g.BaseEmployment OR s.ProjectedEmployment<>g.ProjectedEmployment)+ABS(@B-@S)+ABS(@S-@G),N'Count differences and Silver/Gold measure mismatches';
INSERT #Checks VALUES ('COMPLETENESS',CASE WHEN @S<893 THEN 893-@S ELSE 0 END,N'Baseline minimum row count only; full expected coverage not assessed');
INSERT #Checks VALUES ('FRESHNESS',1,N'Publication calendar not configured; freshness requires review');
INSERT control.DataQualityResult(RunID,RuleID,Outcome,FailedCount,Details)
SELECT @RunID,r.RuleID,CASE WHEN c.FailedCount=0 THEN 'PASS' WHEN r.IsBlocking=1 THEN 'FAIL' ELSE 'WARN' END,c.FailedCount,c.Details FROM #Checks c JOIN control.DataQualityRule r ON r.RuleCode=c.RuleCode WHERE r.IsActive=1;
INSERT quarantine.RejectedObservation(RunID,RuleID,SourceRecordKey,RawPayload,RejectionReason)
SELECT @RunID,r.RuleID,b.RecordKey,b.Payload,N'Silver domain validation failed; diagnostic copy only' FROM #Bad b CROSS JOIN control.DataQualityRule r WHERE r.RuleCode='DOMAIN' AND r.IsActive=1;
UPDATE control.PipelineRun SET EndedUTC=SYSUTCDATETIME(),Status=CASE WHEN EXISTS(SELECT 1 FROM control.DataQualityResult WHERE RunID=@RunID AND Outcome='FAIL') THEN 'REJECTED' ELSE 'SUCCEEDED' END,ErrorMessage=N'Baseline assessment of existing warehouse; not an ingestion or publication run' WHERE RunID=@RunID;
COMMIT;
END TRY
BEGIN CATCH
THROW;
END CATCH;


IF (SELECT COUNT(*) FROM control.PipelineRun WHERE RunID>@Before AND Status='SUCCEEDED')<>4
 OR (SELECT COUNT(DISTINCT SourceID) FROM control.PipelineRun WHERE RunID>@Before)<>4
 OR EXISTS(SELECT 1 FROM control.PipelineRun p CROSS JOIN control.DataQualityRule q WHERE p.RunID>@Before AND q.IsActive=1 AND q.IsBlocking=1 AND NOT EXISTS(SELECT 1 FROM control.DataQualityResult r WHERE r.RunID=p.RunID AND r.RuleID=q.RuleID AND r.Outcome='PASS'))
BEGIN
 COMMIT; -- retain failed quality results; do not change publication pointers
 THROW 51001,'Publication rejected; previous snapshots retained',1;
END;
SELECT @RunID=p.RunID FROM control.PipelineRun p JOIN control.DataSource s ON s.SourceID=p.SourceID WHERE p.RunID>@Before AND s.SourceCode='STATS_LAUS';
INSERT serving.UnemploymentSnapshot SELECT @RunID,x.* FROM (SELECT f.UnemploymentFactKey,g.FIPSCode,g.GeographyName,g.GeographyType,p.ReportingYear,p.MonthCode,p.ReportingMonth,p.PeriodType,f.UnemploymentRate FROM gold.Fact_Unemployment f JOIN gold.Dim_Geography g ON g.GeographyKey=f.GeographyKey JOIN gold.Dim_ReportingPeriod p ON p.PeriodKey=f.PeriodKey) x;
IF @@ROWCOUNT <> (SELECT COUNT_BIG(*) FROM gold.Fact_Unemployment) THROW 51002,'Snapshot row count mismatch: Unemployment',1;
SELECT @RunID=p.RunID FROM control.PipelineRun p JOIN control.DataSource s ON s.SourceID=p.SourceID WHERE p.RunID>@Before AND s.SourceCode='BLS_LAUS';
INSERT serving.LaborMarketSnapshot SELECT @RunID,x.* FROM (SELECT f.BLSFactKey,g.FIPSCode,g.GeographyName,p.ReportingYear,p.MonthCode,p.ReportingDate,m.MeasureCode,m.MeasureUnit,f.MeasureValue FROM gold.Fact_BLS_LaborMarket f JOIN gold.Dim_Geography g ON g.GeographyKey=f.GeographyKey JOIN gold.Dim_BLS_ReportingPeriod p ON p.BLSPeriodKey=f.BLSPeriodKey JOIN gold.Dim_BLS_Measure m ON m.MeasureKey=f.MeasureKey) x;
IF @@ROWCOUNT <> (SELECT COUNT_BIG(*) FROM gold.Fact_BLS_LaborMarket) THROW 51002,'Snapshot row count mismatch: LaborMarket',1;
SELECT @RunID=p.RunID FROM control.PipelineRun p JOIN control.DataSource s ON s.SourceID=p.SourceID WHERE p.RunID>@Before AND s.SourceCode='BLS_OEWS';
INSERT serving.OccupationalWagesSnapshot SELECT @RunID,x.* FROM (SELECT f.FactKey,o.OccupationCode,o.OccupationTitle,o.OccupationGroup,f.GeographyCode,f.ReferenceYear,f.EmploymentEstimate,f.MeanAnnualWage,f.MedianAnnualWage,f.AnnualP10,f.AnnualP25,f.AnnualP75,f.AnnualP90 FROM gold.Fact_OccupationalWages f JOIN gold.Dim_Occupation o ON o.OccupationKey=f.OccupationKey) x;
IF @@ROWCOUNT <> (SELECT COUNT_BIG(*) FROM gold.Fact_OccupationalWages) THROW 51002,'Snapshot row count mismatch: OccupationalWages',1;
SELECT @RunID=p.RunID FROM control.PipelineRun p JOIN control.DataSource s ON s.SourceID=p.SourceID WHERE p.RunID>@Before AND s.SourceCode='IDWD_PROJECTION';
INSERT serving.OccupationalProjectionSnapshot SELECT @RunID,x.* FROM (SELECT f.FactKey,o.OccupationCode,o.OccupationTitle,o.OccupationGroup,f.GeographyCode,f.BaseYear,f.ProjectionYear,f.BaseEmployment,f.ProjectedEmployment FROM gold.Fact_OccupationalProjection f JOIN gold.Dim_Occupation o ON o.OccupationKey=f.OccupationKey) x;
IF @@ROWCOUNT <> (SELECT COUNT_BIG(*) FROM gold.Fact_OccupationalProjection) THROW 51002,'Snapshot row count mismatch: OccupationalProjection',1;
UPDATE b SET RunID=p.RunID,PublishedUTC=SYSUTCDATETIME() FROM control.PublishedBatch b JOIN control.PipelineRun p ON p.SourceID=b.SourceID WHERE p.RunID>@Before;
INSERT control.PublishedBatch(SourceID,RunID) SELECT p.SourceID,p.RunID FROM control.PipelineRun p WHERE p.RunID>@Before AND NOT EXISTS(SELECT 1 FROM control.PublishedBatch b WHERE b.SourceID=p.SourceID);
COMMIT;
END TRY
BEGIN CATCH
 IF @@TRANCOUNT>0 ROLLBACK;
 SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
 THROW;
END CATCH;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
SELECT * FROM control.vw_PipelineHealth;
SELECT 'Unemployment' AS Dataset, COUNT_BIG(*) AS PublishedRows FROM serving.vw_Unemployment;
SELECT 'LaborMarket' AS Dataset, COUNT_BIG(*) AS PublishedRows FROM serving.vw_LaborMarket;
SELECT 'OccupationalWages' AS Dataset, COUNT_BIG(*) AS PublishedRows FROM serving.vw_OccupationalWages;
SELECT 'OccupationalProjection' AS Dataset, COUNT_BIG(*) AS PublishedRows FROM serving.vw_OccupationalProjection;


