#!/bin/bash
set -euxo pipefail

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y python3 python3-apt python3-venv python3-pip

# Ensure cloud-init does not rerun this script
exit 0
