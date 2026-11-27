USE IndianaWorkforceDW;
GO

SET XACT_ABORT ON;
GO

IF OBJECT_ID('control.AgencyAlias','U') IS NULL
BEGIN
    CREATE TABLE control.AgencyAlias (
        AliasName nvarchar(500)
            COLLATE Latin1_General_100_BIN2 NOT NULL
            PRIMARY KEY,
        CanonicalName nvarchar(300) NOT NULL,
        MappingReason nvarchar(200) NOT NULL,
        IsActive bit NOT NULL DEFAULT 1,
        CreatedUTC datetime2(3) NOT NULL
            DEFAULT SYSUTCDATETIME()
    );
END;
GO

BEGIN TRAN;

INSERT INTO control.AgencyAlias
    (AliasName,CanonicalName,MappingReason)
SELECT v.AliasName,v.CanonicalName,v.MappingReason
FROM (VALUES
    (N'Adjutant General Office',
     N'Adjutant General''s Office',
     N'Naming variation'),

    (N'Chain O'+NCHAR(8217)+N'Lakes Correctional Facility',
     N'Chain O''Lakes Correctional Facility',
     N'Unicode apostrophe normalization'),

    (N'Department of Child Services',
     N'Department of Child Services (DCS)',
     N'Agency abbreviation variation'),

    (N'Family & Social Services Administration',
     N'Family & Social Services Administration (FSSA)',
     N'Agency abbreviation variation'),

    (N'Indiana School for the Blind & Visually Impaired (ISBVI)',
     N'Indiana School for the Blind and Visually Impaired (ISBVI)',
     N'Ampersand variation'),

    (N'Indiana State Parks Inns',
     N'Indiana State Park Inns',
     N'Singular and plural variation'),

    (N'Indiana Women'+NCHAR(8217)+N's Prison',
     N'Indiana Women''s Prison',
     N'Unicode apostrophe normalization')

) v(AliasName,CanonicalName,MappingReason)
WHERE NOT EXISTS (
    SELECT 1
    FROM control.AgencyAlias a
    WHERE a.AliasName =
        v.AliasName COLLATE Latin1_General_100_BIN2
);

COMMIT;
GO

CREATE OR ALTER FUNCTION control.fn_CanonicalAgency
(
    @AgencyName nvarchar(500)
)
RETURNS nvarchar(500)
AS
BEGIN
    DECLARE @Canonical nvarchar(500);

    SELECT @Canonical = CanonicalName
    FROM control.AgencyAlias
    WHERE AliasName =
        @AgencyName COLLATE Latin1_General_100_BIN2
      AND IsActive = 1;

    RETURN COALESCE(
        @Canonical,
        NULLIF(
            LTRIM(RTRIM(
                REPLACE(@AgencyName,NCHAR(8217),N'''')
            )),N''
        ),
        N'Unknown'
    );
END;
GO

SELECT AliasName,CanonicalName,MappingReason
FROM control.AgencyAlias;

SELECT
    control.fn_CanonicalAgency(AgencyName)
        AS CanonicalAgency,
    SUM(ObservedPostings) AS ObservedPostings
FROM serving.vw_RecruitmentAgency
GROUP BY control.fn_CanonicalAgency(AgencyName)
ORDER BY ObservedPostings DESC;

SELECT
    COUNT(*) AS OriginalOrganizationLabels,
    COUNT(DISTINCT control.fn_CanonicalAgency(AgencyName))
        AS StandardizedOrganizationLabels,
    SUM(ObservedPostings) AS TotalPostings
FROM serving.vw_RecruitmentAgency;
GO
