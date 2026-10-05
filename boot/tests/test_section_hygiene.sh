#!/bin/sh
# Reject executable instructions emitted after a source file switches to a
# non-executable section without switching back to .text.  With ULF v2 this is
# a boot contract: stage2 maps only the declared text prefix executable.

set -eu

TEST_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$TEST_DIR/../.." && pwd)
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT HUP INT TERM

set +e
find "$ROOT/kernel" "$ROOT/lib" "$ROOT/crypto" "$ROOT/storage" \
     "$ROOT/security" "$ROOT/unet" -type f -name '*.asm' -print0 | \
    xargs -0 -r awk '
        FNR == 1 { section = "unknown"; in_macro = 0 }
        /^[[:space:]]*%macro([[:space:]]|$)/    { in_macro = 1; next }
        /^[[:space:]]*%endmacro([[:space:]]|$)/ { in_macro = 0; next }
        /^[[:space:]]*section[[:space:]]+\.(text|data|rodata|bss)/ {
            line = tolower($0)
            sub(/^.*section[[:space:]]+\./, "", line)
            sub(/[^a-z].*$/, "", line)
            section = line
            next
        }
        !in_macro && section != "text" && \
        section ~ /^(data|rodata|bss)$/ {
            line = tolower($0)
            if (line ~ /^[[:space:]]*([.$_a-z?][.$_a-z0-9?]*:[[:space:]]*)?(mov|lea|push|pop|call|ret|jmp|j[a-z]+|cmp|test|add|sub|xor|or|and|shl|shr|sar|sal|inc|dec|imul|mul|idiv|div|rep|lods|stos|cmov[a-z]*|set[a-z]+|cpuid|rdmsr|wrmsr|xgetbv|xsetbv|in|out|cli|sti|hlt|swapgs|sysret|syscall|iret|iretq|lock|bt|bts|btr|bsf|bsr|not|neg|xchg|bswap|invlpg|pause|pxor|vmov[a-z0-9]*|v[a-z0-9]+|aes[a-z0-9]+)([[:space:]]|$)/) {
                print FILENAME ":" FNR ": instruction in ." section ": " $0
                bad = 1
            }
        }
        END { exit bad ? 1 : 0 }
    ' >"$TMP"
STATUS=$?
set -e

if [ "$STATUS" -ne 0 ]; then
    cat "$TMP"
    echo "FAIL: executable instructions found in non-text sections"
    exit 1
fi

echo "PASS: kernel assembly section hygiene"
