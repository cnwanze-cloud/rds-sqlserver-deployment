# Troubleshooting Guide

Problems I hit while deploying SQL Server 2019 on Amazon RDS (Osaka, `ap-northeast-3`) behind an SSM bastion, with the cause and the fix for each. Replace values in `<angle brackets>` with your own.

## Quick index

| # | Symptom | Section |
|---|---|---|
| 1 | Option dropdown shows `MARIADB_AUDIT_PLUGIN` | [Wrong option group engine](#1-wrong-option-group-engine) |
| 2 | SSMS error 258, wait operation timed out | [Timeout from laptop to private RDS](#2-ssms-error-258-timeout) |
| 3 | `Test-NetConnection` not recognized | [Wrong shell](#3-test-netconnection-not-recognized) |
| 4 | `start-session` hangs after "Starting session" | [Slow or stuck SSM session](#4-ssm-session-hangs) |
| 5 | SSMS error 1225, connection refused | [Tunnel refused](#5-ssms-error-1225) |
| 6 | Login failed for `app_user` (18456) | [Login failure](#6-login-failed-error-18456) |
| 7 | `DROP TABLE` worked when it should fail | [Wrong connection in query window](#7-least-privilege-test-passed-for-the-wrong-reason) |
| 8 | "Database backup/restore option is not enabled" | [Option group not applied](#8-backuprestore-option-not-enabled) |
| 9 | Agent log not offered | [Log exports](#9-agent-log-not-available) |
| 10 | Can't find the CloudWatch metric tile | [Console navigation](#10-cloudwatch-metric-selection) |

---

## 1. Wrong option group engine

**Symptom:** When adding an option, the only choice is `MARIADB_AUDIT_PLUGIN`, and `SQLSERVER_BACKUP_RESTORE` is missing.

**Cause:** The option group was created with a MySQL (or MariaDB) engine. The Option name list only shows options for the engine the group was created with, and an option group's engine cannot be changed afterward.

**Fix:**
1. **RDS → Option groups**, delete the wrong group.
2. **Create group** with:
   - Engine: the **sqlserver** entry matching your edition (`sqlserver-ex`, `-web`, `-se`, or `-ee`)
   - Major engine version: `15.00` (SQL Server 2019)
3. Open the group, **Add option → SQLSERVER_BACKUP_RESTORE**, choose the IAM role, scheduling **Immediately**.

**Prevent it:** Check the Engine field before clicking Create. The MySQL, MariaDB, Oracle, and SQL Server entries are listed close together.

---

## 2. SSMS error 258 (timeout)

**Symptom:**
```
A network-related or instance-specific error occurred ... (provider: TCP Provider,
error: 0 - The wait operation timed out.) (Microsoft SQL Server, Error: 258)
```

**Diagnosis:**
```powershell
nslookup <rds-endpoint>
Test-NetConnection <rds-endpoint> -Port 1433
```
- `nslookup` returned a public IP, so the instance had the *Publicly accessible* flag.
- `TcpTestSucceeded : False`, so port 1433 was unreachable.

**Cause:** The DB subnet group contained **private subnets** whose route table sends `0.0.0.0/0` to a **NAT gateway**. A NAT gateway only handles *outbound* traffic from the subnet. Without an internet gateway route, inbound connections from a laptop never arrive, regardless of the public IP flag or the security group.

**Fix:** Keep the database private and connect through an SSM bastion with port forwarding (see the README, steps 3 to 5). The alternative, for learning only, is a DB subnet group of public subnets (route to an `igw-...`) plus a My IP rule on port 1433.

**Also check:** Some ISPs and offices block outbound port 1433. Test on a phone hotspot to rule that out.

---

## 3. `Test-NetConnection` not recognized

**Symptom:**
```
'Test-NetConnection' is not recognized as an internal or external command
```

**Cause:** It is a PowerShell cmdlet, and the command was run in Command Prompt.

**Fix:** Open PowerShell, or prefix the command from Command Prompt:
```
powershell Test-NetConnection <rds-endpoint> -Port 1433
```

**Note:** `PingSucceeded : False` is normal because AWS doesn't answer pings. Only `TcpTestSucceeded` matters.

---

## 4. SSM session hangs

**Symptom:** `Starting session with SessionId: ...` appears, and then nothing for a long time.

**Checks, in order:**
1. Wait up to about 60 seconds. The first session can be slow.
2. **Systems Manager → Fleet Manager:** the bastion's Ping status must be **Online**.
3. The bastion's subnet route table must have `0.0.0.0/0 → nat-...`, and the NAT gateway must be **Available** (SSM needs outbound access).
4. The instance profile `bastion-ssm-role` (with `AmazonSSMManagedInstanceCore`) must be attached. Reboot the instance after attaching a role late.
5. Try another network if a VPN or firewall blocks WebSocket traffic.

**Success looks like:**
```
Port 14330 opened for sessionId ...
Waiting for connections...
```
Leave that window open. Closing it closes the tunnel.

---

## 5. SSMS error 1225

**Symptom:**
```
provider: TCP Provider, error: 0 - The remote computer refused the network connection.
(Microsoft SQL Server, Error: 1225)
```

**What it means:** Error 258 means nothing was reachable, but **1225 means something answered and refused**. Here, the local tunnel port or the far end rejected the connection.

**Diagnosis steps:**

1. Confirm the tunnel is listening on your laptop:
   ```
   netstat -an | findstr 14330
   ```
   Expected: `127.0.0.1:14330   LISTENING`.
2. Test the bastion-to-RDS leg from the bastion itself (**EC2 → bastion → Connect → Session Manager**):
   ```bash
   nc -zv <rds-endpoint> 1433
   ```
   Expected: `Connected to 10.x.x.x:1433`. That proved the security group rule (`app-sg` to port 1433) and RDS were fine.
3. Check the database security group's inbound rule: **MSSQL, TCP 1433, source = the bastion's security group**, and that the bastion actually uses that group.

**Fix that worked:**
- Stop the tunnel (`Ctrl+C`), confirm the port is free, and restart it.
- In SSMS use **`127.0.0.1,14330`** instead of `localhost`, which can resolve to IPv6 (`::1`) where the tunnel isn't listening.
- Tick **Trust Server Certificate**.

**If the port is stuck:** use a different local port (for example `14331`) in both the tunnel command and SSMS.

---

## 6. Login failed (error 18456)

**Symptom:** `Login failed for user 'app_user'. (Microsoft SQL Server, Error: 18456)`

**What it means:** The network path is fine. SQL Server itself rejected the credentials.

**Checks (run as `admin`):**
```sql
SELECT name, is_disabled FROM sys.server_principals WHERE name = 'app_user';
```
- No row: the `CREATE LOGIN` never ran. Run it again.
- Row exists: reset the password and type it manually (don't paste), in case of stray spaces:
```sql
ALTER LOGIN app_user WITH PASSWORD = '<NEW_STRONG_PASSWORD>';
```

**Also verify:**
- Authentication is **SQL Server Authentication**, not Windows.
- The database-level user exists:
  ```sql
  USE SalesDB;
  SELECT name FROM sys.database_principals WHERE name = 'app_user';
  ```
- To see the real reason: `EXEC sp_readerrorlog 0, 1, 'app_user';`

**Master user:** If `admin` fails, reset it at **RDS → Modify → New master password → Apply immediately**.

---

## 7. Least-privilege test passed for the wrong reason

**Symptom:** `DROP TABLE SalesDB.dbo.Customers;` succeeded, so the table was deleted and the test proved nothing.

**Cause:** The query window was connected as **`admin`** (status bar showed `admin`), not `app_user`. A new query window inherits the connection selected in Object Explorer.

**Fix:**
1. Recreate the table and data as `admin` (script in `sql/01-create-database.sql`).
2. Right-click the **`app_user`** server node in Object Explorer, choose **New Query**, and check the status bar says `app_user`.
3. Rerun the tests:
   ```sql
   USE SalesDB;
   SELECT * FROM Customers;      -- works
   INSERT INTO Customers (Name, Email) VALUES ('Test', 't@example.com');  -- works
   DROP TABLE Customers;         -- fails
   ```
   Expected failure: `Msg 3701 ... Cannot drop the table 'Customers', because it does not exist or you do not have permission.`

**Cleanup:** remove the test row as `admin`: `DELETE FROM Customers WHERE Name = 'Test';`

**Lesson:** Always read the connection name in the status bar before running anything destructive.

---

## 8. Backup/restore option not enabled

**Symptom:**
```
Msg 50000, Level 16 ... Database backup/restore option is not enabled or is in the
process of being enabled. Please try again later.
```

**Cause:** The option group with `SQLSERVER_BACKUP_RESTORE` wasn't attached to the instance yet, or was still applying.

**Fix:**
1. **RDS → instance → Configuration:** the option group must be your custom group with status **in-sync**.
2. If it isn't attached: **Modify → Additional configuration → DB option group**, choose it, **Apply immediately**.
3. Verify the option group has the correct engine (`sqlserver-*`), major version `15.00`, and the option with your IAM role.
4. Verify the IAM role's trust principal is `rds.amazonaws.com`, and that the policy covers both the bucket ARN and `bucket/*`. The bucket must be in the same Region as the instance.
5. Rerun the backup, then poll:
   ```sql
   EXEC msdb.dbo.rds_task_status @db_name = 'SalesDB';
   ```

**Task lifecycle:**

| lifecycle | Meaning |
|---|---|
| `CREATED` | Queued |
| `IN_PROGRESS` | Running (see `% complete`) |
| `SUCCESS` | Finished; `.bak` is in S3 |
| `ERROR` | Failed; read the `task_info` column |

**Common task errors:**

| Message | Fix |
|---|---|
| Access denied (S3) | Policy bucket name must match exactly, with both ARNs |
| Bucket not found | Bucket must be in the same Region as RDS |
| Database already exists (restore) | Use a new `@restore_db_name` or drop the old one |

---

## 9. Agent log not available

**Symptom:** Under **Log exports**, only **Error log** is listed.

**Explanation:** RDS shows only the log types supported by the engine and edition. Not an error. The error log covers startup, login failures, and backup/restore activity, which is enough for this project.

---

## 10. CloudWatch metric selection

**Symptom:** After searching "Per-Database Metrics" in the Select metric dialog, no matching tile appears.

**Fix:** Clear the search box. In the current console, tiles are named by dimension. Use **RDS → DBInstanceIdentifier**, search for your instance name, and tick `FreeStorageSpace`, `CPUUtilization`, or `DatabaseConnections`.

**Alarm states:** `Insufficient data` is normal for the first 5 to 10 minutes. It should change to `OK`. The SNS email subscription must show **Confirmed**, or alarms fire without sending email.

---

## Useful diagnostic commands

| Purpose | Command |
|---|---|
| Resolve endpoint | `nslookup <rds-endpoint>` |
| Test port from laptop | `powershell Test-NetConnection <rds-endpoint> -Port 1433` |
| Check tunnel is listening | `netstat -an \| findstr 14330` |
| Test RDS from bastion | `nc -zv <rds-endpoint> 1433` |
| Engine version | `SELECT @@VERSION;` |
| List databases | `SELECT name FROM sys.databases;` |
| Backup/restore status | `EXEC msdb.dbo.rds_task_status @db_name = '<db>';` |
| Login exists | `SELECT name FROM sys.server_principals WHERE name = '<login>';` |

## Error code cheat sheet

| Error | Meaning | First thing to check |
|---|---|---|
| 258 | Timed out, nothing reachable | Subnet routing, security group, public access |
| 1225 | Reached something, connection refused | Is the tunnel running? Use `127.0.0.1` |
| 18456 | Reached SQL Server, login rejected | Password, login exists, SQL auth selected |
| 3701 | Object missing or no permission | Which user is the query window connected as? |
