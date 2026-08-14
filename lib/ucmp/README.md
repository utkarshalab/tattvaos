# lib/ucmp — Master Compression Subsystem

The **`lib/ucmp`** library is the single, authoritative, high-performance 64-bit Assembly Data Compression Subsystem for Tattva OS, featuring hardware SIMD vector acceleration and multi-algorithm compression primitives.

---

## 1. Directory Structure

```
lib/ucmp/
├── include/
│   └── ucmp.inc               ← Master definitions, algorithm IDs, and stream state schemas
├── arch/
│   ├── common/
│   │   ├── macros.inc         ← Compiler & NASM assembly macros
│   │   ├── error.inc          ← Master error codes (UCMP_OK, UCMP_ERR_CORRUPT...)
│   │   ├── types.inc          ← Data type aliases & buffer sizes
│   │   └── bitops.inc         ← Bit manipulation macros (BSWAP, POPCNT, LZCNT)
│   └── x86_64/
│       └── simd/
│           └── scan.asm       ← AVX2 256-bit vector byte scanner & LZ77 match finder
├── algo/
│   ├── lz4/
│   │   ├── lz4.asm            ← Fast LZ4 byte streaming compressor (`ucmp_lz4_compress`)
│   │   └── lz4_decomp.asm     ← Fast LZ4 decompressor (`ucmp_lz4_decompress`)
│   ├── zstd/
│   │   └── zstd.asm           ← ZSTD Finite State Entropy compressor/decompressor
│   └── snappy/
│       └── snappy.asm         ← Ultra-low latency Snappy block compressor/decompressor
├── checksum/
│   └── crc32.asm              ← Intel SSE4.2 hardware-accelerated CRC32 checksum engine
├── mem/
│   └── arena.asm              ← Zero-allocation memory arena for streaming buffers
├── PROJECTSTRUCTURE.MD        ← Master Architecture Specification
├── README.md                  ← Master Subsystem Documentation
└── ucmp.asm                   ← Master Compression Dispatcher API (`ucmp_init`, `ucmp_compress`, `ucmp_decompress`)
```

---

## 2. Supported Algorithms

| Algorithm | Identifier | Target Use Case in Tattva OS |
| :--- | :--- | :--- |
| **LZ4** | `UCMP_ALGO_LZ4` | **Storage Hot Path** for `storage/uxfs/compress/compress.asm` & immutable boot images (`erofs.asm`) |
| **ZSTD** | `UCMP_ALGO_ZSTD` | High-ratio background data compression for archival storage volumes |
| **Snappy** | `UCMP_ALGO_SNAPPY` | Ultra-low latency transient RAMDisk (`tmpfs`) compression |
| **DEFLATE / Gzip** | `UCMP_ALGO_DEFLATE` | Network header and UPK package decompression |

---

## 3. Hardware SIMD Acceleration Highlights

- **AVX2 256-Bit Vector Byte Scanner (`arch/x86_64/simd/scan.asm`)**: Compares 32 bytes in parallel using `vmovdqu`, `vpcmpeqb`, and `vpmovmskb` instructions for maximum LZ77 match discovery speed.
- **SSE4.2 Hardware CRC32 Checksum (`checksum/crc32.asm`)**: High-throughput 64-bit hardware CRC32 accumulator using native `crc32` CPU instructions.
- **Zero-Allocation Arena (`mem/arena.asm`)**: Lock-free linear memory page allocator for sliding window ring buffers.
