/* =====================================================================
   03-backup-restore.sql
   Purpose : Native backup of SalesDB to S3, then restore it under a new
             name to prove the backup works.
   Run as  : admin (RDS master user)
   Requires:
     - S3 bucket in the SAME Region as the RDS instance
     - IAM policy + role (iam/rds-sqlserver-s3-policy.json), role trusted
       by rds.amazonaws.com
     - Option group (engine: sqlserver-*, major version 15.00) containing
       SQLSERVER_BACKUP_RESTORE, attached to the instance and "in-sync"
   Notes   : Replace <your-backup-bucket> with your bucket name.
             RDS does not allow the native BACKUP/RESTORE DATABASE commands.
             Use the rds_* stored procedures below instead.
             Run each section separately and wait for SUCCESS before moving on.
   ===================================================================== */

-- SECTION 1: Back up SalesDB to S3 ---------------------------------------
EXEC msdb.dbo.rds_backup_database
    @source_db_name          = 'SalesDB',
    @s3_arn_to_backup_to     = 'arn:aws:s3:::<your-backup-bucket>/SalesDB.bak',
    @overwrite_s3_backup_file = 1;
GO

-- SECTION 2: Check backup progress ---------------------------------------
-- Repeat every 20-30 seconds until lifecycle = SUCCESS and % complete = 100.
EXEC msdb.dbo.rds_task_status @db_name = 'SalesDB';
GO

/* lifecycle values:
     CREATED      queued
     IN_PROGRESS  running
     SUCCESS      finished, SalesDB.bak is in S3
     ERROR        failed, read the task_info column

   Error: "Database backup/restore option is not enabled or is in the
   process of being enabled" means the option group is not attached yet,
   or is still applying. Wait for "in-sync" and retry.
*/

-- Verify in the S3 console that SalesDB.bak exists before restoring.

-- SECTION 3: Restore the backup under a NEW name -------------------------
-- The target database name must not already exist on the instance.
EXEC msdb.dbo.rds_restore_database
    @restore_db_name        = 'SalesDB_Restored',
    @s3_arn_to_restore_from = 'arn:aws:s3:::<your-backup-bucket>/SalesDB.bak';
GO

-- SECTION 4: Check restore progress --------------------------------------
EXEC msdb.dbo.rds_task_status @db_name = 'SalesDB_Restored';
GO

-- SECTION 5: Verify the restored data ------------------------------------
-- Run after lifecycle = SUCCESS. Refresh Databases in Object Explorer first.
SELECT * FROM SalesDB_Restored.dbo.Customers;
GO

-- SECTION 6: Optional cleanup --------------------------------------------
-- Uncomment to remove the restored copy (e.g. to retry a failed restore,
-- or to save storage).
-- DROP DATABASE SalesDB_Restored;
-- GO

/* Restoring a backup from another server:
   - Upload the .bak to the bucket (aws s3 cp MyDb.bak s3://<your-backup-bucket>/)
   - The backup must come from SQL Server 2019 or older (this instance is 15.00)
   - Use a restore name that does not already exist
*/
