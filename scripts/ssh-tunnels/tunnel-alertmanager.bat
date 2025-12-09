@echo off
REM ==================================================
REM KubeStock SSH Tunnel to Alertmanager UI (via NLB)
REM ==================================================
REM Access Alertmanager web UI to view/manage/silence alerts
REM Note: Alertmanager is only enabled in production environment

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
set REMOTE_NLB=%KUBESTOCK_NLB_DNS%
set REMOTE_PORT=9093

REM Local port
set LOCAL_PORT=9093

echo ========================================
echo KubeStock Alertmanager UI Tunnel
echo ========================================
echo Bastion:      %BASTION%
echo Remote:       %REMOTE_NLB%:%REMOTE_PORT%
echo Local:        http://localhost:%LOCAL_PORT%
echo ========================================
echo.
echo NOTE: Alertmanager is only deployed in PRODUCTION.
echo       This tunnel will not work for staging environment.
echo.
echo Useful URLs:
echo   - Alerts:   http://localhost:%LOCAL_PORT%/#/alerts
echo   - Silences: http://localhost:%LOCAL_PORT%/#/silences
echo   - Status:   http://localhost:%LOCAL_PORT%/#/status
echo.
echo Starting SSH tunnel...
echo Press Ctrl+C to stop
echo.

REM Start SSH tunnel (keep it running)
ssh -i "%KUBESTOCK_SSH_KEY%" -L %LOCAL_PORT%:%REMOTE_NLB%:%REMOTE_PORT% %BASTION% -N
