USE [master];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF SUSER_ID(N'Matt\svc_workforce_etl') IS NULL
BEGIN
    CREATE LOGIN [Matt\svc_workforce_etl]
        FROM WINDOWS
        WITH DEFAULT_DATABASE = [IndianaWorkforceDW];

    PRINT 'Windows login created.';
END
ELSE
    PRINT 'Windows login already exists.';
GO

USE [IndianaWorkforceDW];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DATABASE_PRINCIPAL_ID(N'rl_workforce_etl') IS NULL
    THROW 50001, 'Required ETL role does not exist.', 1;

BEGIN TRY
    BEGIN TRANSACTION;

    IF DATABASE_PRINCIPAL_ID(N'svc_workforce_etl') IS NULL
    BEGIN
        CREATE USER [svc_workforce_etl]
            FOR LOGIN [Matt\svc_workforce_etl];

        PRINT 'Database user created.';
    END;

    IF NOT EXISTS (
        SELECT 1
        FROM sys.database_principals
        WHERE name = N'svc_workforce_etl'
          AND sid = SUSER_SID(N'Matt\svc_workforce_etl')
    )
        THROW 50002, 'Database identity mapping mismatch.', 1;

    IF NOT EXISTS (
        SELECT 1
        FROM sys.database_role_members
        WHERE role_principal_id =
            DATABASE_PRINCIPAL_ID(N'rl_workforce_etl')
          AND member_principal_id =
            DATABASE_PRINCIPAL_ID(N'svc_workforce_etl')
    )
    BEGIN
        ALTER ROLE [rl_workforce_etl]
            ADD MEMBER [svc_workforce_etl];

        PRINT 'ETL role membership assigned.';
    END;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO

PRINT '=== SERVER LOGIN ===';

SELECT
    name,
    type_desc,
    is_disabled,
    default_database_name
FROM sys.server_principals
WHERE name = N'Matt\svc_workforce_etl';

PRINT '=== DATABASE IDENTITY ===';

SELECT
    name,
    type_desc,
    authentication_type_desc
FROM sys.database_principals
WHERE name = N'svc_workforce_etl';

PRINT '=== SERVER ROLE MEMBERSHIP ===';

SELECT
    r.name AS ServerRole,
    m.name AS MemberName
FROM sys.server_role_members rm
JOIN sys.server_principals r
    ON rm.role_principal_id = r.principal_id
JOIN sys.server_principals m
    ON rm.member_principal_id = m.principal_id
WHERE m.name = N'Matt\svc_workforce_etl';

PRINT '=== DATABASE ROLE MEMBERSHIP ===';

SELECT
    r.name AS DatabaseRole,
    m.name AS MemberName
FROM sys.database_role_members rm
JOIN sys.database_principals r
    ON rm.role_principal_id = r.principal_id
JOIN sys.database_principals m
    ON rm.member_principal_id = m.principal_id
WHERE m.name = N'svc_workforce_etl';

PRINT '=== DIRECT DATABASE PERMISSIONS ===';

SELECT
    state_desc,
    permission_name,
    class_desc
FROM sys.database_permissions
WHERE grantee_principal_id =
    DATABASE_PRINCIPAL_ID(N'svc_workforce_etl');
GO
