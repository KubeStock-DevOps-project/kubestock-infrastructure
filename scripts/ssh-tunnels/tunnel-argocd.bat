@echo off
REM ==================================================
REM KubeStock SSH Tunnel to ArgoCD UI (via NLB)
REM ==================================================

REM Path to your private key
set KEY_PATH=C:\Users\%USERNAME%\.ssh\kubestock-key

REM Bastion host (replace with your bastion IP)
set BASTION=ubuntu@<BASTION_IP>

REM Get NLB DNS from Terraform output first:
REM   cd infrastructure/terraform/prod
REM   terraform output -raw nlb_staging_dns_name
set REMOTE_NLB=<NLB_STAGING_DNS>
set REMOTE_PORT=8443

REM Local port
set LOCAL_PORT=8443

echo ========================================
echo KubeStock ArgoCD UI Tunnel
echo ========================================
echo Bastion:      %BASTION%
echo Remote:       %REMOTE_NLB%:%REMOTE_PORT%
echo Local:        https://localhost:%LOCAL_PORT%
echo ========================================
echo.
echo ArgoCD Credentials:
echo   Username: admin
echo   Password: (get from: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" ^| base64 -d)
echo.
echo Starting SSH tunnel...
echo Press Ctrl+C to stop
echo.

REM Start SSH tunnel (keep it running)
ssh -i "%KEY_PATH%" -L %LOCAL_PORT%:%REMOTE_NLB%:%REMOTE_PORT% %BASTION% -N
