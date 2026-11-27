USE IndianaWorkforceDW;
GO
SET XACT_ABORT ON;
BEGIN TRAN;
GO
CREATE OR ALTER VIEW serving.vw_StateRecruitment AS
SELECT p.JobPostingID,p.SourcePostingID,p.RequisitionID,p.JobTitle,p.AgencyRaw,p.AgencyName,p.City,p.StateCode,p.ZIPCode,p.CountyFIPS,p.SOCCode,p.MinimumSalaryRaw,p.JobDescription,p.Responsibilities,p.Qualifications,p.DatePosted,p.FirstSeenUTC,p.LastSeenUTC,p.FirstNotSeenUTC,p.IsActive AS ObservedActive,p.DetailStatus,p.JobURL,c.CollectionDate AS ObservationDate,p.SalaryValidationStatus
FROM silver.StateCareers_JobPosting p JOIN bronze.StateCareers_Raw r ON r.RawID=p.LatestRawID JOIN bronze.StateCareers_Collection c ON c.CollectionID=r.CollectionID WHERE c.IsListingComplete=1 AND c.CollectionStatus IN ('SUCCEEDED','PARTIAL');
GO
CREATE OR ALTER VIEW serving.vw_RecruitmentDaily AS
SELECT d.ObservationDate,d.AdvertisedPostings,d.NewlyObservedPostings,d.NoLongerObservedPostings,d.ReactivatedPostings,d.CumulativeUniquePostings,CONVERT(bit,CASE WHEN d.ObservationDate=(SELECT MIN(ObservationDate) FROM gold.Fact_RecruitmentDaily) THEN 1 ELSE 0 END) AS IsBaseline
FROM gold.Fact_RecruitmentDaily d JOIN bronze.StateCareers_Collection c ON c.CollectionID=d.CollectionID WHERE c.IsListingComplete=1 AND c.CollectionStatus IN ('SUCCEEDED','PARTIAL');
GO
CREATE OR ALTER VIEW serving.vw_RecruitmentAgency AS
SELECT COALESCE(NULLIF(AgencyName,''),NULLIF(AgencyRaw,''),'Unknown') AS AgencyName,COUNT_BIG(*) AS ObservedPostings FROM serving.vw_StateRecruitment WHERE ObservedActive=1 GROUP BY COALESCE(NULLIF(AgencyName,''),NULLIF(AgencyRaw,''),'Unknown');
GO
CREATE OR ALTER VIEW serving.vw_RecruitmentLocation AS
SELECT City,StateCode,ZIPCode,COUNT_BIG(*) AS ObservedPostings FROM serving.vw_StateRecruitment WHERE ObservedActive=1 GROUP BY City,StateCode,ZIPCode;
GO
CREATE OR ALTER VIEW serving.vw_RecruitmentCompensation AS
SELECT p.JobPostingID,p.JobTitle,c.CompensationID,c.RoleName,c.SalaryAmount,c.SalaryFrequency,c.AnnualizedSalary,c.AnnualizationHours,c.TipsEligible,c.SalaryEvidence FROM serving.vw_StateRecruitment p JOIN silver.StateCareers_JobCompensation c ON c.JobPostingID=p.JobPostingID JOIN silver.StateCareers_JobPosting s ON s.JobPostingID=p.JobPostingID AND s.LatestRawID=c.SourceRawID WHERE c.ValidationStatus='VALIDATED' AND p.ObservedActive=1;
GO
CREATE OR ALTER VIEW serving.vw_RecruitmentSkills AS
SELECT s.SkillName,s.RequirementType,COUNT_BIG(DISTINCT p.JobPostingID) AS ObservedPostings FROM serving.vw_StateRecruitment p JOIN silver.StateCareers_JobSkill s ON s.JobPostingID=p.JobPostingID WHERE p.ObservedActive=1 GROUP BY s.SkillName,s.RequirementType;
GO
CREATE OR ALTER VIEW serving.vw_RecruitmentQuality AS
SELECT c.CollectionDate,c.SourceCollectionKey,c.CollectionStatus,c.ReportedPostings,c.RetrievedPostings,c.DetailsRetrieved,c.IsListingComplete,c.IsDetailComplete,(SELECT COUNT_BIG(*) FROM silver.StateCareers_JobCompensation x JOIN bronze.StateCareers_Raw r ON r.RawID=x.SourceRawID WHERE r.CollectionID=c.CollectionID AND x.ValidationStatus='REVIEW_REQUIRED') AS CompensationCandidatesPending FROM bronze.StateCareers_Collection c;
GO
GRANT SELECT ON serving.vw_StateRecruitment TO rl_dashboard_reader;
GRANT SELECT ON serving.vw_RecruitmentDaily TO rl_dashboard_reader;
GRANT SELECT ON serving.vw_RecruitmentAgency TO rl_dashboard_reader;
GRANT SELECT ON serving.vw_RecruitmentLocation TO rl_dashboard_reader;
GRANT SELECT ON serving.vw_RecruitmentCompensation TO rl_dashboard_reader;
GRANT SELECT ON serving.vw_RecruitmentSkills TO rl_dashboard_reader;
GRANT SELECT ON serving.vw_RecruitmentQuality TO rl_dashboard_reader;
IF (SELECT COUNT(*) FROM serving.vw_StateRecruitment)<>468 THROW 51000,'Baseline posting reconciliation failed',1;
IF (SELECT COUNT(*) FROM serving.vw_RecruitmentDaily)<>1 THROW 51001,'Baseline daily reconciliation failed',1;
IF EXISTS (SELECT 1 FROM serving.vw_RecruitmentCompensation) THROW 51002,'Unexpected validated compensation',1;
EXECUTE AS USER='usr_dashboard_test';
SELECT COUNT(*) AS DashboardReadablePostings FROM serving.vw_StateRecruitment;
SELECT COUNT(*) AS DashboardReadableDailyRows FROM serving.vw_RecruitmentDaily;
SELECT COUNT(*) AS DashboardReadableAgencyRows FROM serving.vw_RecruitmentAgency;
SELECT COUNT(*) AS DashboardReadableLocationRows FROM serving.vw_RecruitmentLocation;
SELECT COUNT(*) AS DashboardReadableCompensationRows FROM serving.vw_RecruitmentCompensation;
SELECT COUNT(*) AS DashboardReadableSkillRows FROM serving.vw_RecruitmentSkills;
SELECT COUNT(*) AS DashboardReadableQualityRows FROM serving.vw_RecruitmentQuality;
SELECT HAS_PERMS_BY_NAME('silver.StateCareers_JobPosting','OBJECT','SELECT') AS DirectSilverReadPermission;
REVERT;
COMMIT;
PRINT 'Recruitment serving deployment committed';
GO
