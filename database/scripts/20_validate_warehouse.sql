USE IndianaWorkforceDW;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
-- Baseline assessment only. No publication or fact changes.
DECLARE @RunID bigint,@SourceID int,@B bigint,@S bigint,@G bigint;
CREATE TABLE #Checks (RuleCode varchar(60), FailedCount bigint, Details nvarchar(1000));
CREATE TABLE #Bad (RecordKey nvarchar(300), Payload nvarchar(max));

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
IF @@TRANCOUNT>0 ROLLBACK;
UPDATE control.PipelineRun SET Status='FAILED',EndedUTC=SYSUTCDATETIME(),ErrorMessage=ERROR_MESSAGE() WHERE RunID=@RunID;
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
IF @@TRANCOUNT>0 ROLLBACK;
UPDATE control.PipelineRun SET Status='FAILED',EndedUTC=SYSUTCDATETIME(),ErrorMessage=ERROR_MESSAGE() WHERE RunID=@RunID;
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
IF @@TRANCOUNT>0 ROLLBACK;
UPDATE control.PipelineRun SET Status='FAILED',EndedUTC=SYSUTCDATETIME(),ErrorMessage=ERROR_MESSAGE() WHERE RunID=@RunID;
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
IF @@TRANCOUNT>0 ROLLBACK;
UPDATE control.PipelineRun SET Status='FAILED',EndedUTC=SYSUTCDATETIME(),ErrorMessage=ERROR_MESSAGE() WHERE RunID=@RunID;
END CATCH;

SELECT * FROM control.vw_PipelineHealth;
SELECT s.SourceCode,r.RunID,q.RuleCode,d.Outcome,d.FailedCount,d.Details FROM control.vw_PipelineHealth s JOIN control.PipelineRun r ON r.RunID=s.RunID JOIN control.DataQualityResult d ON d.RunID=r.RunID JOIN control.DataQualityRule q ON q.RuleID=d.RuleID ORDER BY s.SourceCode,q.RuleID;
SELECT * FROM quarantine.RejectedObservation WHERE RunID IN (SELECT RunID FROM control.vw_PipelineHealth);
GO
