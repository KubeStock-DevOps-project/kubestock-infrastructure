@echo off
REM ==================================================
REM KubeStock - Start ALL SSH Tunnels (Windows)
REM ==================================================
REM This script opens SSH tunnels for all commonly used
REM KubeStock endpoints in a single SSH session:
REM
REM   Staging HTTP:        http://localhost:5173  -> NLB:80
REM   Staging HTTPS:       https://localhost:5174 -> NLB:443
REM   Kubernetes API:      https://localhost:6443 -> NLB:6443
REM   ArgoCD UI:           https://localhost:8443 -> NLB:8443
REM   Grafana:             http://localhost:3000  -> NLB:3000
REM   Prometheus:          http://localhost:9090  -> NLB:9090
REM   Alertmanager (prod): http://localhost:9093  -> NLB:9093
REM
REM Environment variables used:
REM   KUBESTOCK_BASTION_IP  - bastion public IP
REM   KUBESTOCK_NLB_DNS     - internal NLB DNS name
REM   KUBESTOCK_SSH_KEY     - path to SSH private key (optional)

setlocal ENABLEDELAYEDEXPANSION

REM Resolve SSH key path
if "%KUBESTOCK_SSH_KEY%"=="" (
    set "KEY_PATH=%USERPROFILE%\.ssh\id_ed25519"
) else (
    set "KEY_PATH=%KUBESTOCK_SSH_KEY%"
)

REM Validate bastion host configuration
if "%KUBESTOCK_BASTION_IP%"=="" (
    echo ERROR: KUBESTOCK_BASTION_IP environment variable not set
    echo Please set it, for example:
    echo   set KUBESTOCK_BASTION_IP=13.202.52.3
    exit /b 1
)
set "BASTION=ubuntu@%KUBESTOCK_BASTION_IP%"

REM Validate NLB DNS configuration
if "%KUBESTOCK_NLB_DNS%"=="" (
    echo ERROR: KUBESTOCK_NLB_DNS environment variable not set
    echo Please set it, for example:
    echo   set KUBESTOCK_NLB_DNS=kubestock-nlb-xxx.elb.ap-south-1.amazonaws.com
    exit /b 1
)
set "REMOTE_NLB=%KUBESTOCK_NLB_DNS%"

echo ========================================
echo KubeStock - ALL Tunnels
echo ========================================
echo Bastion: %BASTION%
echo NLB:     %REMOTE_NLB%
echo SSH key: %KEY_PATH%
echo ----------------------------------------
echo Local endpoints that will be available:
echo   Staging HTTP:        http://localhost:5173
echo   Staging HTTPS:       https://localhost:5174
echo   Kubernetes API:      https://localhost:6443
echo   ArgoCD UI:           https://localhost:8443
echo   Grafana:             http://localhost:3000
echo   Prometheus:          http://localhost:9090
echo   Alertmanager (prod): http://localhost:9093
echo ========================================
echo Press Ctrl+C to close ALL tunnels.
echo.

ssh -i "%KEY_PATH%" ^
  -L 5173:%REMOTE_NLB%:80 ^
  -L 5174:%REMOTE_NLB%:443 ^
  -L 6443:%REMOTE_NLB%:6443 ^
  -L 8443:%REMOTE_NLB%:8443 ^
  -L 3000:%REMOTE_NLB%:3000 ^
  -L 9090:%REMOTE_NLB%:9090 ^
  -L 9093:%REMOTE_NLB%:9093 ^
  %BASTION% -N

endlocal
