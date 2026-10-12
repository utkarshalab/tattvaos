#!/bin/bash
# Soak tests: 24h client churn, hotplug, quota pressure on Tattva
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
make soak
echo "Boot build/img/soak_test.img on Tattva; run 24h, check for drops."
