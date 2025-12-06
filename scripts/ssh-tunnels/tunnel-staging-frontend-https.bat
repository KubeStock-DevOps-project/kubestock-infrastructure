@echo off
REM ==================================================
REM KubeStock SSH Tunnel to Staging Frontend HTTPS (via NLB)
REM ==================================================

REM Path to your private key
set KEY_PATH=C:\Users\%USERNAME%\.ssh\kubestock-key

REM Bastion host (replace with your bastion IP)
set BASTION=ubuntu@<BASTION_IP>

REM Get NLB DNS from Terraform output first:
REM   cd infrastructure/terraform/prod
REM   terraform output -raw nlb_staging_dns_name
set REMOTE_NLB=<NLB_STAGING_DNS>
set REMOTE_PORT=443

REM Local port
set LOCAL_PORT=5173

echo ========================================
echo KubeStock Staging Frontend Tunnel (HTTPS)
echo ========================================
echo Bastion:      %BASTION%
echo Remote:       %REMOTE_NLB%:%REMOTE_PORT%
echo Local:        https://localhost:%LOCAL_PORT%
echo ========================================
echo.
echo Note: You may need to accept a self-signed certificate warning
echo.
echo Starting SSH tunnel...
echo Press Ctrl+C to stop
echo.

REM Start SSH tunnel (keep it running)
ssh -i "%KEY_PATH%" -L %LOCAL_PORT%:%REMOTE_NLB%:%REMOTE_PORT% %BASTION% -N
