USE IndianaWorkforceDW;
GO

CREATE OR ALTER VIEW serving.vw_StateRecruitment AS
SELECT
    p.JobPostingID,
    p.SourcePostingID,
    p.RequisitionID,
    p.JobTitle,
    p.AgencyRaw,
    p.AgencyName,
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

SELECT
    ObservationDate,
    ObservedActive,
    COUNT(*) AS Postings
FROM serving.vw_StateRecruitment
GROUP BY ObservationDate, ObservedActive;

SELECT
    COUNT(*) AS HistoricalPostings,
    SUM(CASE WHEN ObservedActive=1 THEN 1 ELSE 0 END)
        AS ActivePostings
FROM serving.vw_StateRecruitment;
GO
