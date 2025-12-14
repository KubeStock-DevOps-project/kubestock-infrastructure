@echo off
REM ==================================================
REM KubeStock - Start ALL SSH Tunnels (Windows)
REM ==================================================
REM This script opens SSH tunnels for all commonly used
REM KubeStock endpoints in a single SSH session:
REM
REM   Production (HTTP):   http://localhost:8080  -> NLB:80 (Kong prod)
REM   Staging (HTTP):      http://localhost:8081  -> NLB:81 (Kong staging)
REM   Kubernetes API:      https://localhost:6443 -> NLB:6443
REM   ArgoCD UI:           https://localhost:8443 -> NLB:8443
REM   Grafana (prod):      http://localhost:3000  -> NLB:3000
REM   Prometheus (prod):   http://localhost:9090  -> NLB:9090
REM   Alertmanager (prod): http://localhost:9093  -> NLB:9093
REM   Kiali (Istio UI):    http://localhost:20001 -> NLB:20001
REM
REM NOTE: Production HTTPS traffic goes through ALB with TLS termination
REM       Use https://kubestock.dpiyumal.me for production HTTPS access
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
echo   Production (HTTP):   http://localhost:8080  (Kong prod)
echo   Staging (HTTP):      http://localhost:8081  (Kong staging)
echo   Kubernetes API:      https://localhost:6443
echo   ArgoCD UI:           https://localhost:8443
echo   Grafana (prod):      http://localhost:3000
echo   Prometheus (prod):   http://localhost:9090
echo   Alertmanager (prod): http://localhost:9093
echo   Kiali (Istio UI):    http://localhost:20001
echo.
echo NOTE: For HTTPS production access, use https://kubestock.dpiyumal.me
echo       (ALB handles TLS termination)
echo ========================================
echo Press Ctrl+C to close ALL tunnels.
echo.

REM Port mappings:
REM   8080 -> NLB:80  = Kong Production (HTTP)
REM   8081 -> NLB:81  = Kong Staging (HTTP)
REM   6443 -> NLB:6443 = Kubernetes API
REM   8443 -> NLB:8443 = ArgoCD
REM   3000 -> NLB:3000 = Grafana (prod)
REM   9090 -> NLB:9090 = Prometheus (prod)
REM   9093 -> NLB:9093 = Alertmanager (prod)
REM   20001 -> NLB:20001 = Kiali
ssh -i "%KEY_PATH%" ^
  -L 8080:%REMOTE_NLB%:80 ^
  -L 8081:%REMOTE_NLB%:81 ^
  -L 6443:%REMOTE_NLB%:6443 ^
  -L 8443:%REMOTE_NLB%:8443 ^
  -L 3000:%REMOTE_NLB%:3000 ^
  -L 9090:%REMOTE_NLB%:9090 ^
  -L 9093:%REMOTE_NLB%:9093 ^
  -L 20001:%REMOTE_NLB%:20001 ^
  %BASTION% -N

endlocal
