#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
build_dir=$(mktemp -d)
trap 'rm -f "$build_dir/test_cli.o" "$build_dir/test_cli"; rmdir "$build_dir"' EXIT HUP INT TERM
nasm -w+error -f elf64 -I ./ tests/unit/test_cli.asm -o "$build_dir/test_cli.o"
ld -z noexecstack -o "$build_dir/test_cli" "$build_dir/test_cli.o"
"$build_dir/test_cli"
printf 'VCS CLI: PASS\n'
