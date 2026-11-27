USE IndianaWorkforceDW;
GO

SET XACT_ABORT ON;
BEGIN TRAN;

-- Correct clustered index key limitation
DECLARE @PKName sysname;

SELECT @PKName = name
FROM sys.key_constraints
WHERE parent_object_id = OBJECT_ID('control.AgencyAlias')
AND type = 'PK';

IF @PKName IS NOT NULL
BEGIN
    DECLARE @SQL nvarchar(max);

    SET @SQL =
        N'ALTER TABLE control.AgencyAlias DROP CONSTRAINT '
        + QUOTENAME(@PKName);

    EXEC sp_executesql @SQL;
END;

ALTER TABLE control.AgencyAlias
ADD CONSTRAINT PK_AgencyAlias
PRIMARY KEY NONCLUSTERED (AliasName);

GO

-- Integrate canonical organization names
CREATE OR ALTER VIEW serving.vw_StateRecruitment AS
SELECT
    p.JobPostingID,
    p.SourcePostingID,
    p.RequisitionID,
    p.JobTitle,
    p.AgencyRaw,

    control.fn_CanonicalAgency(
        COALESCE(
            NULLIF(p.AgencyName,''),
            NULLIF(p.AgencyRaw,'')
        )
    ) AS AgencyName,

    p.City,
    p.StateCode,
    p.ZIPCode,
    p.CountyFIPS,
    p.SOCCode,
    p.MinimumSalaryRaw,
    p.JobDescription,
    p.Responsibilities,
    p.Qualifications,
    p.DatePosted,
    p.FirstSeenUTC,
    p.LastSeenUTC,
    p.FirstNotSeenUTC,
    p.IsActive AS ObservedActive,
    p.DetailStatus,
    p.JobURL,
    c.CollectionDate AS ObservationDate,
    p.SalaryValidationStatus

FROM silver.StateCareers_JobPosting p

JOIN bronze.StateCareers_Raw r
    ON r.RawID = p.LatestListingRawID

JOIN bronze.StateCareers_Collection c
    ON c.CollectionID = r.CollectionID

WHERE c.IsListingComplete = 1
AND c.CollectionStatus IN ('SUCCEEDED','PARTIAL');
GO

-- Reconcile active inventory with latest daily observation
DECLARE @Expected bigint;
DECLARE @Actual bigint;

SELECT TOP 1 @Expected = AdvertisedPostings
FROM serving.vw_RecruitmentDaily
ORDER BY ObservationDate DESC;

SELECT @Actual = COUNT_BIG(*)
FROM serving.vw_StateRecruitment
WHERE ObservedActive = 1;

IF @Expected IS NULL OR @Expected <> @Actual
    THROW 51000,'Recruitment reconciliation failed',1;

SELECT
    COUNT(*) AS StandardizedOrganizationLabels,
    SUM(ObservedPostings) AS TotalPostings
FROM serving.vw_RecruitmentAgency;

SELECT TOP 10
    AgencyName,
    ObservedPostings
FROM serving.vw_RecruitmentAgency
ORDER BY ObservedPostings DESC;

-- Verify dashboard reader access
EXECUTE AS USER = 'usr_dashboard_test';

SELECT COUNT(*) AS DashboardReadablePostings
FROM serving.vw_StateRecruitment;

SELECT COUNT(*) AS DashboardReadableOrganizations
FROM serving.vw_RecruitmentAgency;

REVERT;

COMMIT;

PRINT 'AGENCY MASTER DATA INTEGRATION PASSED';
GO
