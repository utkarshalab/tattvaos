#!/bin/bash
# =============================================================================
# tests/conformance/run.sh
# Compilation and execution wrapper for the Unicode Conformance suite.
#
# Part of Utkarsha Labs / Tattva OS — str library
# =============================================================================

set -e

# Base directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../../" && pwd)"

echo "==> Compiling str library objects..."

# Find all assembly source files
ASM_FILES=(
    "$LIB_DIR/unicode/combining_class.asm"
    "$LIB_DIR/unicode/decomposition.asm"
    "$LIB_DIR/unicode/composition_exclusion.asm"
    "$LIB_DIR/unicode/normalize.asm"
    "$LIB_DIR/unicode/security.asm"
    "$LIB_DIR/unicode/named_sequences.asm"
    "$LIB_DIR/unicode/standardized_variants.asm"
    "$LIB_DIR/unicode/emoji_sequences.asm"
    "$LIB_DIR/unicode/equivalent_ideograph.asm"
    "$LIB_DIR/unicode/do_not_emit.asm"
    "$LIB_DIR/unicode/property_aliases.asm"
    "$LIB_DIR/unicode/normalization_corrections.asm"
    "$LIB_DIR/unicode/nushu_tangut.asm"
    "$LIB_DIR/unicode/wordbreak.asm"
    "$LIB_DIR/unicode/grapheme.asm"
    "$LIB_DIR/unicode/sentence.asm"
)

# Object files output directory
OBJ_DIR="$LIB_DIR/build/obj"
mkdir -p "$OBJ_DIR"

OBJ_FILES=()

# Compile each file using NASM
for f in "${ASM_FILES[@]}"; do
    if [ -f "$f" ]; then
        filename=$(basename "$f" .asm)
        echo "  [NASM] $filename.asm"
        nasm -f elf64 -i "$LIB_DIR/" -o "$OBJ_DIR/$filename.o" "$f"
        OBJ_FILES+=("$OBJ_DIR/$filename.o")
    fi
done

# Output shared library path
LIB_OUT="$LIB_DIR/build/libstr.so"
echo "==> Linking shared library: $LIB_OUT"
gcc -shared -o "$LIB_OUT" "${OBJ_FILES[@]}"

echo "==> Running Python conformance test runner..."
python3 "$SCRIPT_DIR/unicode/run_conformance.py" "$LIB_OUT"
