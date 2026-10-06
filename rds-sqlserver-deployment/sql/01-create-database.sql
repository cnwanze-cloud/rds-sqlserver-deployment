/* =====================================================================
   01-create-database.sql
   Purpose : Create the SalesDB database, the Customers table, and sample data
   Run as  : admin (RDS master user)
   Connect : 127.0.0.1,14330 (through the SSM tunnel)
   Notes   : Safe to re-run. Each step checks whether the object exists.
             CREATE DATABASE must be in its own batch, so keep the GO lines.
   ===================================================================== */

-- 1. Create the database ------------------------------------------------
IF DB_ID(N'SalesDB') IS NULL
BEGIN
    CREATE DATABASE SalesDB;
    PRINT 'Database SalesDB created.';
END
ELSE
    PRINT 'Database SalesDB already exists.';
GO

-- 2. Create the table ---------------------------------------------------
USE SalesDB;
GO

IF OBJECT_ID(N'dbo.Customers', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.Customers (
        CustomerID INT IDENTITY(1,1) PRIMARY KEY,
        Name       NVARCHAR(100) NOT NULL,
        Email      NVARCHAR(150) NULL
    );
    PRINT 'Table dbo.Customers created.';
END
ELSE
    PRINT 'Table dbo.Customers already exists.';
GO

-- 3. Insert sample data (only if the table is empty) -------------------
IF NOT EXISTS (SELECT 1 FROM dbo.Customers)
BEGIN
    INSERT INTO dbo.Customers (Name, Email) VALUES
        (N'Ada Obi',     N'ada@example.com'),
        (N'Chidi Eze',   N'chidi@example.com'),
        (N'Ngozi Bello', N'ngozi@example.com');
    PRINT 'Sample rows inserted.';
END
ELSE
    PRINT 'Table already has data. No rows inserted.';
GO

-- 4. Verify -------------------------------------------------------------
SELECT CustomerID, Name, Email FROM dbo.Customers;
GO
