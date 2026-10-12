#!/bin/bash
# Benchmarks: build bench_runner.img, record results to tests/bench/results/
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
make bench
echo "Boot build/img/bench_runner.img; append serial output to tests/bench/results/<machine>.md"
