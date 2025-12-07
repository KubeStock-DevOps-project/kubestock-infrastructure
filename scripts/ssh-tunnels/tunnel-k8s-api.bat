@echo off
REM ==================================================
REM KubeStock SSH Tunnel to Kubernetes API (via NLB)
REM ==================================================

REM Path to your private key (override with KUBESTOCK_SSH_KEY env var)
if not defined KUBESTOCK_SSH_KEY set KUBESTOCK_SSH_KEY=C:\Users\%USERNAME%\.ssh\id_ed25519

REM Bastion host (set KUBESTOCK_BASTION_IP env var)
if not defined KUBESTOCK_BASTION_IP (
    echo ERROR: KUBESTOCK_BASTION_IP environment variable not set
    echo Please set it: set KUBESTOCK_BASTION_IP=13.202.52.3
    exit /b 1
)
set BASTION=ubuntu@%KUBESTOCK_BASTION_IP%

REM NLB DNS (set KUBESTOCK_NLB_DNS env var)
if not defined KUBESTOCK_NLB_DNS (
    echo ERROR: KUBESTOCK_NLB_DNS environment variable not set
    echo Please set it: set KUBESTOCK_NLB_DNS=kubestock-nlb-xxx.elb.ap-south-1.amazonaws.com
    exit /b 1
)
set REMOTE_API=%KUBESTOCK_NLB_DNS%
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
ssh -i "%KUBESTOCK_SSH_KEY%" -L %LOCAL_PORT%:%REMOTE_API%:%REMOTE_PORT% %BASTION% -N
