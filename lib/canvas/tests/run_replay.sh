#!/bin/bash
# Replay tests: build replay_test.img, replay tests/replays/*.cwprec on Tattva
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
make test
echo "Boot build/img/replay_test.img on Tattva; frames+events must match."
