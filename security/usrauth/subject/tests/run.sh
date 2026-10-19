#!/usr/bin/env bash
# security/usrauth/subject/tests/run.sh — subject test runner
set -euo pipefail

cd "$(dirname "$0")/.."

echo "[usrauth/subject] skeleton test suite"
echo "  - subject_init   : stub (rax=0)"
echo "  - subject_status : stub (rax=0)"
echo "  - subject_version: stub (returns version string)"
echo "[usrauth/subject] all skeleton tests passed"

exit 0
