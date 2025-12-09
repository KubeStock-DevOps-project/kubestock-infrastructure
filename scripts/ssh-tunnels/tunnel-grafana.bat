@echo off
REM ==================================================
REM KubeStock SSH Tunnel to Grafana UI (via NLB)
REM ==================================================
REM Access Grafana dashboards for metrics visualization and logs
REM Grafana serves as the unified UI for Prometheus metrics and Loki logs

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
set REMOTE_PORT=3000

REM Local port
set LOCAL_PORT=3000

echo ========================================
echo KubeStock Grafana UI Tunnel
echo ========================================
echo Bastion:      %BASTION%
echo Remote:       %REMOTE_NLB%:%REMOTE_PORT%
echo Local:        http://localhost:%LOCAL_PORT%
echo ========================================
echo.
echo Grafana Credentials:
echo   Username: admin
echo   Password: admin (change on first login)
echo.
echo Available Datasources:
echo   - Prometheus (metrics)
echo   - Loki (logs)
echo.
echo Starting SSH tunnel...
echo Press Ctrl+C to stop
echo.

REM Start SSH tunnel (keep it running)
ssh -i "%KUBESTOCK_SSH_KEY%" -L %LOCAL_PORT%:%REMOTE_NLB%:%REMOTE_PORT% %BASTION% -N
