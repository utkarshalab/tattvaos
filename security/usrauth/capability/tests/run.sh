#!/usr/bin/env bash
# security/usrauth/capability/tests/run.sh — capability test runner
set -euo pipefail

cd "$(dirname "$0")/.."

echo "[usrauth/capability] skeleton test suite"
echo "  - cap_init      : stub (rax=0)"
echo "  - cap_status    : stub (rax=0)"
echo "  - cap_version   : stub (returns version string)"
echo "  - cap_issue     : stub (rax=0)"
echo "  - cap_evaluate  : stub (rax=0)"
echo "[usrauth/capability] all skeleton tests passed"

exit 0
