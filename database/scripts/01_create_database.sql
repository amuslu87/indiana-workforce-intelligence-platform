
/* 
SELECT
    @@SERVERNAME AS ServerName,
    SERVERPROPERTY('ProductVersion') AS SQLVersion,
    SERVERPROPERTY('Edition') AS SQLEdition,
    DB_NAME() AS CurrentDatabase;
*/

    USE master;
GO

CREATE DATABASE IndianaWorkforceDW;
GO