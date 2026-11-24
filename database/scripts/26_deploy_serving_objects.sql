USE IndianaWorkforceDW;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF SCHEMA_ID('serving') IS NULL EXEC('CREATE SCHEMA serving AUTHORIZATION dbo');
GO
IF OBJECT_ID('serving.UnemploymentSnapshot','U') IS NULL
 SELECT TOP (0) CAST(0 AS bigint) AS RunID, x.* INTO serving.UnemploymentSnapshot FROM (SELECT f.UnemploymentFactKey,g.FIPSCode,g.GeographyName,g.GeographyType,p.ReportingYear,p.MonthCode,p.ReportingMonth,p.PeriodType,f.UnemploymentRate FROM gold.Fact_Unemployment f JOIN gold.Dim_Geography g ON g.GeographyKey=f.GeographyKey JOIN gold.Dim_ReportingPeriod p ON p.PeriodKey=f.PeriodKey) x CROSS JOIN (SELECT 1 AS dummy) d;
GO
CREATE OR ALTER VIEW serving.vw_Unemployment AS
SELECT x.* FROM serving.UnemploymentSnapshot x JOIN control.PublishedBatch b ON b.RunID=x.RunID JOIN control.DataSource s ON s.SourceID=b.SourceID AND s.SourceCode='STATS_LAUS';
GO
IF OBJECT_ID('serving.LaborMarketSnapshot','U') IS NULL
 SELECT TOP (0) CAST(0 AS bigint) AS RunID, x.* INTO serving.LaborMarketSnapshot FROM (SELECT f.BLSFactKey,g.FIPSCode,g.GeographyName,p.ReportingYear,p.MonthCode,p.ReportingDate,m.MeasureCode,m.MeasureUnit,f.MeasureValue FROM gold.Fact_BLS_LaborMarket f JOIN gold.Dim_Geography g ON g.GeographyKey=f.GeographyKey JOIN gold.Dim_BLS_ReportingPeriod p ON p.BLSPeriodKey=f.BLSPeriodKey JOIN gold.Dim_BLS_Measure m ON m.MeasureKey=f.MeasureKey) x CROSS JOIN (SELECT 1 AS dummy) d;
GO
CREATE OR ALTER VIEW serving.vw_LaborMarket AS
SELECT x.* FROM serving.LaborMarketSnapshot x JOIN control.PublishedBatch b ON b.RunID=x.RunID JOIN control.DataSource s ON s.SourceID=b.SourceID AND s.SourceCode='BLS_LAUS';
GO
IF OBJECT_ID('serving.OccupationalWagesSnapshot','U') IS NULL
 SELECT TOP (0) CAST(0 AS bigint) AS RunID, x.* INTO serving.OccupationalWagesSnapshot FROM (SELECT f.FactKey,o.OccupationCode,o.OccupationTitle,o.OccupationGroup,f.GeographyCode,f.ReferenceYear,f.EmploymentEstimate,f.MeanAnnualWage,f.MedianAnnualWage,f.AnnualP10,f.AnnualP25,f.AnnualP75,f.AnnualP90 FROM gold.Fact_OccupationalWages f JOIN gold.Dim_Occupation o ON o.OccupationKey=f.OccupationKey) x CROSS JOIN (SELECT 1 AS dummy) d;
GO
CREATE OR ALTER VIEW serving.vw_OccupationalWages AS
SELECT x.* FROM serving.OccupationalWagesSnapshot x JOIN control.PublishedBatch b ON b.RunID=x.RunID JOIN control.DataSource s ON s.SourceID=b.SourceID AND s.SourceCode='BLS_OEWS';
GO
IF OBJECT_ID('serving.OccupationalProjectionSnapshot','U') IS NULL
 SELECT TOP (0) CAST(0 AS bigint) AS RunID, x.* INTO serving.OccupationalProjectionSnapshot FROM (SELECT f.FactKey,o.OccupationCode,o.OccupationTitle,o.OccupationGroup,f.GeographyCode,f.BaseYear,f.ProjectionYear,f.BaseEmployment,f.ProjectedEmployment FROM gold.Fact_OccupationalProjection f JOIN gold.Dim_Occupation o ON o.OccupationKey=f.OccupationKey) x CROSS JOIN (SELECT 1 AS dummy) d;
GO
CREATE OR ALTER VIEW serving.vw_OccupationalProjection AS
SELECT x.* FROM serving.OccupationalProjectionSnapshot x JOIN control.PublishedBatch b ON b.RunID=x.RunID JOIN control.DataSource s ON s.SourceID=b.SourceID AND s.SourceCode='IDWD_PROJECTION';
GO

