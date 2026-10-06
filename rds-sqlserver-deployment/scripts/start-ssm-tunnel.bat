@echo off
REM =====================================================================
REM  start-ssm-tunnel.bat
REM  Opens an AWS Systems Manager port-forwarding tunnel from this laptop
REM  to the private RDS SQL Server instance, through the bastion EC2.
REM
REM  After it prints "Waiting for connections...", connect SSMS to:
REM      127.0.0.1,%LOCAL_PORT%     (SQL Server Authentication)
REM
REM  KEEP THIS WINDOW OPEN. Closing it (or pressing Ctrl+C) closes the tunnel.
REM
REM  Requirements:
REM    - AWS CLI v2 configured (aws configure)
REM    - Session Manager plugin installed
REM    - Bastion shows "Online" in Systems Manager -> Fleet Manager
REM
REM  Edit the four values below. Do NOT commit real values to GitHub.
REM =====================================================================

REM ----- Settings (edit these) ------------------------------------------
set "BASTION_ID=<bastion-instance-id>"
set "RDS_ENDPOINT=<rds-endpoint>"
set "AWS_REGION=ap-northeast-3"
set "LOCAL_PORT=14330"
set "REMOTE_PORT=1433"
REM ---------------------------------------------------------------------

echo.
echo === RDS SQL Server SSM tunnel ===
echo.

REM ----- Check that the placeholders were replaced ----------------------
echo %BASTION_ID% | findstr /C:"<" >nul
if %errorlevel%==0 (
    echo [ERROR] BASTION_ID is still a placeholder. Edit this file first.
    goto :end
)
echo %RDS_ENDPOINT% | findstr /C:"<" >nul
if %errorlevel%==0 (
    echo [ERROR] RDS_ENDPOINT is still a placeholder. Edit this file first.
    goto :end
)

REM ----- Check that the AWS CLI is installed ----------------------------
where aws >nul 2>&1
if errorlevel 1 (
    echo [ERROR] AWS CLI not found. Install AWS CLI v2, then open a NEW terminal.
    goto :end
)

REM ----- Check that the Session Manager plugin is installed -------------
where session-manager-plugin >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Session Manager plugin not found.
    echo         Install it, then open a NEW terminal.
    goto :end
)

REM ----- Check that the local port is free ------------------------------
netstat -an | findstr /C:":%LOCAL_PORT% " | findstr /C:"LISTENING" >nul
if %errorlevel%==0 (
    echo [ERROR] Local port %LOCAL_PORT% is already in use.
    echo         Close any other tunnel window, or change LOCAL_PORT in this file
    echo         and use the same port in SSMS.
    goto :end
)

echo Region      : %AWS_REGION%
echo Bastion     : %BASTION_ID%
echo RDS endpoint: %RDS_ENDPOINT%
echo Local port  : %LOCAL_PORT%  -^>  remote %REMOTE_PORT%
echo.
echo Starting tunnel... wait for "Waiting for connections..."
echo Then connect SSMS to: 127.0.0.1,%LOCAL_PORT%
echo.

aws ssm start-session --target %BASTION_ID% --region %AWS_REGION% --document-name AWS-StartPortForwardingSessionToRemoteHost --parameters "{\"host\":[\"%RDS_ENDPOINT%\"],\"portNumber\":[\"%REMOTE_PORT%\"],\"localPortNumber\":[\"%LOCAL_PORT%\"]}"

echo.
echo Tunnel closed.
echo If it failed to start, check:
echo   1. Bastion is Online in Systems Manager -^> Fleet Manager
echo   2. Region is correct (%AWS_REGION%)
echo   3. Your IAM user has ssm:StartSession permission
echo   4. aws configure has valid credentials

:end
echo.
pause
