/* =====================================================================
   02-create-app-user.sql
   Purpose : Create a least-privilege login for applications.
             app_user can read and write data but cannot change the schema.
   Run as  : admin (RDS master user) for Parts 1 and 2
             app_user for Part 3 (the permission test)
   Notes   : Replace <STRONG_PASSWORD> before running. Use 12+ characters
             with upper and lower case, numbers, and symbols.
             NEVER commit the real password to GitHub.
   ===================================================================== */

-- PART 1: Create the server-level login (run as admin) -------------------
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'app_user')
BEGIN
    CREATE LOGIN app_user WITH PASSWORD = '<STRONG_PASSWORD>';
    PRINT 'Login app_user created.';
END
ELSE
BEGIN
    PRINT 'Login app_user already exists. To change the password use:';
    PRINT '  ALTER LOGIN app_user WITH PASSWORD = ''<NEW_STRONG_PASSWORD>'';';
END
GO

-- PART 2: Create the database user and grant roles (run as admin) --------
USE SalesDB;
GO

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'app_user')
BEGIN
    CREATE USER app_user FOR LOGIN app_user;
    PRINT 'Database user app_user created in SalesDB.';
END
GO

ALTER ROLE db_datareader ADD MEMBER app_user;   -- SELECT on all tables
ALTER ROLE db_datawriter ADD MEMBER app_user;   -- INSERT, UPDATE, DELETE on all tables
GO

-- Confirm membership
SELECT r.name AS role_name, m.name AS member_name
FROM sys.database_role_members rm
JOIN sys.database_principals r ON rm.role_principal_id = r.principal_id
JOIN sys.database_principals m ON rm.member_principal_id = m.principal_id
WHERE m.name = N'app_user';
GO

/* =====================================================================
   PART 3: Least-privilege test
   !! Run ONLY from a query window connected as app_user !!
   Check the status bar at the bottom of SSMS. It must say app_user.
   A window connected as admin WILL drop the table.

   How to open the right window:
   Object Explorer -> right-click the "... - app_user" server node
   -> New Query.

   Uncomment and run the statements one at a time.
   ===================================================================== */

-- USE SalesDB;
-- SELECT * FROM dbo.Customers;                                            -- expected: works
-- INSERT INTO dbo.Customers (Name, Email) VALUES (N'Test', N't@example.com'); -- expected: works
-- DROP TABLE dbo.Customers;                                               -- expected: FAILS
--   Msg 3701: Cannot drop the table 'Customers', because it does not exist
--   or you do not have permission.

/* Cleanup of the test row (run as admin):
   DELETE FROM SalesDB.dbo.Customers WHERE Name = N'Test';
*/
