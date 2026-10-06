/* =====================================================================
   04-validation.sql
   Purpose : Final checks to confirm the deployment works. Take a
             screenshot of each result for your project documentation.
   Run as  : admin (RDS master user)
   Notes   : Read-only. Nothing here changes data.
   ===================================================================== */

-- 1. Engine version (expect Microsoft SQL Server 2019, version 15.x) -----
SELECT @@VERSION AS sql_server_version;
GO

SELECT SERVERPROPERTY('ProductVersion')  AS product_version,
       SERVERPROPERTY('Edition')         AS edition,
       SERVERPROPERTY('EngineEdition')   AS engine_edition;
GO

-- 2. Databases on the instance -------------------------------------------
-- Expect master, tempdb, model, msdb, rdsadmin, SalesDB, SalesDB_Restored.
-- Do not modify rdsadmin. RDS uses it to manage the instance.
SELECT name, state_desc, create_date
FROM sys.databases
ORDER BY name;
GO

-- 3. Row counts: original vs restored (should match) ---------------------
SELECT COUNT(*) AS salesdb_customers FROM SalesDB.dbo.Customers;
GO

-- Guarded so the script still runs if the restore has not been done.
IF DB_ID(N'SalesDB_Restored') IS NOT NULL
    EXEC sp_executesql
        N'SELECT COUNT(*) AS salesdb_restored_customers FROM SalesDB_Restored.dbo.Customers;';
ELSE
    PRINT 'SalesDB_Restored does not exist yet. Run sql/03-backup-restore.sql first.';
GO

-- 4. Least-privilege check for app_user ----------------------------------
-- Expect: SELECT/INSERT = 1, DROP/ALTER = 0 (can only touch data).
USE SalesDB;
GO

SELECT
    HAS_PERMS_BY_NAME('dbo.Customers', 'OBJECT', 'SELECT')  AS admin_can_select,
    HAS_PERMS_BY_NAME('dbo.Customers', 'OBJECT', 'INSERT')  AS admin_can_insert,
    HAS_PERMS_BY_NAME('dbo.Customers', 'OBJECT', 'ALTER')   AS admin_can_alter;
GO

-- Roles held by app_user (expect db_datareader and db_datawriter only)
SELECT r.name AS role_name, m.name AS member_name
FROM sys.database_role_members rm
JOIN sys.database_principals r ON rm.role_principal_id = r.principal_id
JOIN sys.database_principals m ON rm.member_principal_id = m.principal_id
WHERE m.name = N'app_user';
GO

-- Test the permissions as app_user without opening a second connection
-- (admin can impersonate). Expect SELECT = 1, INSERT = 1, ALTER = 0.
EXECUTE AS USER = 'app_user';
SELECT
    USER_NAME() AS running_as,
    HAS_PERMS_BY_NAME('dbo.Customers', 'OBJECT', 'SELECT') AS can_select,
    HAS_PERMS_BY_NAME('dbo.Customers', 'OBJECT', 'INSERT') AS can_insert,
    HAS_PERMS_BY_NAME('dbo.Customers', 'OBJECT', 'ALTER')  AS can_alter;
REVERT;
GO

-- 5. Backup and restore task history -------------------------------------
-- Expect BACKUP_DB and RESTORE_DB tasks with lifecycle = SUCCESS.
EXEC msdb.dbo.rds_task_status @db_name = 'SalesDB';
GO

-- 6. Recent backup history recorded by SQL Server ------------------------
SELECT TOP (5)
    database_name,
    backup_start_date,
    backup_finish_date,
    type,   -- D = full, I = differential, L = log
    CAST(backup_size / 1024.0 / 1024.0 AS DECIMAL(10,2)) AS backup_size_mb
FROM msdb.dbo.backupset
WHERE database_name = N'SalesDB'
ORDER BY backup_finish_date DESC;
GO

/* Checks done outside SQL (use the AWS console):
   [ ] RDS instance status = Available
   [ ] Publicly accessible = No
   [ ] Database security group: only MSSQL 1433 from the bastion's SG
   [ ] Backup retention = 7 days or more; manual snapshot Available
   [ ] CloudWatch alarms = OK; SNS subscription = Confirmed
   [ ] SalesDB.bak present in the S3 bucket
*/
