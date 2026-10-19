#!/bin/bash
cd /mnt/c/Users/USER/Desktop/Projects/tattvaos/security
for d in */; do
    echo "Building $d..."
    cd "$d" || continue
    for f in src/*.asm; do
        b="${f##*/}"
        b="${b%.asm}"
        nasm -f bin -o "${b}.bin" "$f" 2>&1 || echo "FAILED: $f"
    done
    cd ..
done
echo "ALL MODULES BUILT"
