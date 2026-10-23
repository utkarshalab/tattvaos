#!/bin/bash
# Soak tests: 24h client churn, hotplug, quota pressure on Utkarsha
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
make soak
echo "Boot build/img/soak_test.img on Utkarsha; run 24h, check for drops."
