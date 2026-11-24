USE IndianaWorkforceDW;
GO

-- Create the dashboard database role
IF DATABASE_PRINCIPAL_ID('rl_dashboard_reader') IS NULL
    CREATE ROLE rl_dashboard_reader AUTHORIZATION dbo;
GO

-- Grant access only to approved serving views
GRANT SELECT ON OBJECT::serving.vw_Unemployment
TO rl_dashboard_reader;

GRANT SELECT ON OBJECT::serving.vw_LaborMarket
TO rl_dashboard_reader;

GRANT SELECT ON OBJECT::serving.vw_OccupationalWages
TO rl_dashboard_reader;

GRANT SELECT ON OBJECT::serving.vw_OccupationalProjection
TO rl_dashboard_reader;
GO

-- Explicitly restrict internal schemas
DENY SELECT, INSERT, UPDATE, DELETE
ON SCHEMA::bronze TO rl_dashboard_reader;

DENY SELECT, INSERT, UPDATE, DELETE
ON SCHEMA::silver TO rl_dashboard_reader;

DENY SELECT, INSERT, UPDATE, DELETE
ON SCHEMA::gold TO rl_dashboard_reader;

DENY SELECT, INSERT, UPDATE, DELETE
ON SCHEMA::control TO rl_dashboard_reader;

DENY SELECT, INSERT, UPDATE, DELETE
ON SCHEMA::quarantine TO rl_dashboard_reader;

DENY INSERT, UPDATE, DELETE
ON SCHEMA::serving TO rl_dashboard_reader;
GO

-- Create a test identity
IF DATABASE_PRINCIPAL_ID('usr_dashboard_test') IS NULL
    CREATE USER usr_dashboard_test WITHOUT LOGIN;
GO

IF IS_ROLEMEMBER(
    'rl_dashboard_reader',
    'usr_dashboard_test'
) = 0
    ALTER ROLE rl_dashboard_reader
    ADD MEMBER usr_dashboard_test;
GO

-- Test permissions under the restricted identity
EXECUTE AS USER = 'usr_dashboard_test';

BEGIN TRY

    SELECT
        USER_NAME() AS CurrentDatabaseUser,
        HAS_PERMS_BY_NAME(
            'serving.vw_Unemployment',
            'OBJECT', 'SELECT'
        ) AS CanReadServing,
        HAS_PERMS_BY_NAME(
            'bronze', 'SCHEMA', 'SELECT'
        ) AS CanReadBronze,
        HAS_PERMS_BY_NAME(
            'silver', 'SCHEMA', 'SELECT'
        ) AS CanReadSilver,
        HAS_PERMS_BY_NAME(
            'gold', 'SCHEMA', 'SELECT'
        ) AS CanReadGold,
        HAS_PERMS_BY_NAME(
            'control', 'SCHEMA', 'SELECT'
        ) AS CanReadControl,
        HAS_PERMS_BY_NAME(
            'quarantine', 'SCHEMA', 'SELECT'
        ) AS CanReadQuarantine;

    SELECT 'Unemployment' AS Dataset,
           COUNT_BIG(*) AS AccessibleRows
    FROM serving.vw_Unemployment

    UNION ALL

    SELECT 'Labor Market', COUNT_BIG(*)
    FROM serving.vw_LaborMarket

    UNION ALL

    SELECT 'Occupational Wages', COUNT_BIG(*)
    FROM serving.vw_OccupationalWages

    UNION ALL

    SELECT 'Occupational Projections', COUNT_BIG(*)
    FROM serving.vw_OccupationalProjection;

END TRY
BEGIN CATCH
    REVERT;
    THROW;
END CATCH;

REVERT;
GO