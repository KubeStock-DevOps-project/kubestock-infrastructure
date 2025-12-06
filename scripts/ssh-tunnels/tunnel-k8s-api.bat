@echo off
REM ==================================================
REM KubeStock SSH Tunnel to Kubernetes API (via NLB)
REM ==================================================

REM Path to your private key
set KEY_PATH=C:\Users\%USERNAME%\.ssh\kubestock-key

REM Bastion host (replace with your bastion IP)
set BASTION=ubuntu@<BASTION_IP>

REM Get NLB DNS from Terraform output first:
REM   cd infrastructure/terraform/prod
REM   terraform output -raw nlb_dns_name
set REMOTE_API=<NLB_API_DNS>
set REMOTE_PORT=6443

REM Local port
set LOCAL_PORT=6443

echo ========================================
echo KubeStock Kubernetes API Tunnel
echo ========================================
echo Bastion:      %BASTION%
echo Remote:       %REMOTE_API%:%REMOTE_PORT%
echo Local:        localhost:%LOCAL_PORT%
echo ========================================
echo.
echo Starting SSH tunnel...
echo Press Ctrl+C to stop
echo.

REM Start SSH tunnel (keep it running)
ssh -i "%KEY_PATH%" -L %LOCAL_PORT%:%REMOTE_API%:%REMOTE_PORT% %BASTION% -N
