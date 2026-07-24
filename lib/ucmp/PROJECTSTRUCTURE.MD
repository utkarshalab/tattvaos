ucmp/
├── arch/
│   ├── common/
│   │   ├── macros.inc
│   │   ├── error.inc
│   │   ├── types.inc
│   │   └── bitops.inc        ← bit manipulation macros (shifts, rotates)
│   ├── aarch64/
│   │   ├── entry.asm
│   │   ├── syscall.asm
│   │   ├── string.asm
│   │   └── simd/
│   │       ├── crc32.asm       ← NEON CRC32 hardware acceleration
│   │       ├── adler32.asm     ← NEON Adler32
│   │       ├── xxhash.asm      ← NEON xxHash
│   │       └── scan.asm        ← NEON byte scanning
│   ├── x86_64/
│   │   ├── entry.asm
│   │   ├── syscall.asm
│   │   ├── string.asm
│   │   └── simd/
│   │       ├── crc32.asm       ← SSE4.2 CRC32 instruction
│   │       ├── adler32.asm     ← AVX2 Adler32
│   │       ├── xxhash.asm      ← AVX2 xxHash
│   │       ├── scan.asm        ← AVX2 byte scanning
│   │       └── avx512.asm      ← AVX512 hot paths
│   └── riscv/
│       ├── entry.asm
│       ├── syscall.asm
│       ├── string.asm
│       └── simd/
│           ├── crc32.asm
│           ├── adler32.asm
│           ├── xxhash.asm
│           └── scan.asm
│
├── core/
│   ├── stream.asm              ← streaming compress/decompress abstraction
│   ├── buffer.asm              ← sliding window buffer management
│   ├── bitstream.asm           ← bit-level read/write (deflate needs this)
│   ├── huffman.asm             ← huffman tree build/encode/decode
│   ├── lz77.asm                ← base LZ77 match finding
│   ├── matchfinder.asm         ← hash chain + binary tree match finder
│   └── entropy.asm             ← entropy coding primitives (ANS/FSE)
│
├── algo/
│   ├── deflate/
│   │   ├── deflate.asm         ← deflate compressor
│   │   ├── inflate.asm         ← deflate decompressor
│   │   ├── huffman_static.asm  ← static huffman trees
│   │   ├── huffman_dynamic.asm ← dynamic huffman trees
│   │   └── window.asm          ← 32KB sliding window
│   ├── zlib/
│   │   ├── zlib.asm            ← zlib wrapper over deflate
│   │   ├── header.asm          ← zlib header read/write
│   │   └── adler32.asm         ← zlib checksum
│   ├── gzip/
│   │   ├── gzip.asm            ← gzip wrapper over deflate
│   │   ├── header.asm          ← gzip header read/write
│   │   └── crc32.asm           ← gzip checksum
│   ├── zstd/
│   │   ├── zstd.asm            ← zstd compressor entry
│   │   ├── zstd_decomp.asm     ← zstd decompressor entry
│   │   ├── frame.asm           ← zstd frame format
│   │   ├── block.asm           ← zstd block types (raw/rle/compressed)
│   │   ├── fse.asm             ← finite state entropy coding
│   │   ├── huf.asm             ← huffman coding (zstd variant)
│   │   ├── sequences.asm       ← literal/match sequence coding
│   │   ├── dict.asm            ← zstd dictionary support
│   │   └── xxhash.asm          ← zstd checksum
│   ├── lz4/
│   │   ├── lz4.asm             ← lz4 compressor
│   │   ├── lz4_decomp.asm      ← lz4 decompressor
│   │   ├── lz4hc.asm           ← lz4 high compression
│   │   ├── frame.asm           ← lz4 frame format
│   │   └── xxhash.asm          ← lz4 checksum
│   ├── lzma/
│   │   ├── lzma.asm            ← lzma compressor
│   │   ├── lzma_decomp.asm     ← lzma decompressor
│   │   ├── range_enc.asm       ← range encoder
│   │   ├── range_dec.asm       ← range decoder
│   │   ├── lz.asm              ← lz match finding
│   │   └── literals.asm        ← literal coding
│   ├── xz/
│   │   ├── xz.asm              ← xz wrapper over lzma2
│   │   ├── stream.asm          ← xz stream format
│   │   ├── block.asm           ← xz block format
│   │   ├── index.asm           ← xz index
│   │   ├── header.asm          ← xz stream header/footer
│   │   └── crc64.asm           ← xz checksum
│   ├── brotli/
│   │   ├── brotli.asm          ← brotli compressor
│   │   ├── brotli_decomp.asm   ← brotli decompressor
│   │   ├── prefix.asm          ← prefix codes
│   │   ├── context.asm         ← context modeling
│   │   ├── metablock.asm       ← metablock format
│   │   ├── transform.asm       ← word transforms
│   │   └── dictionary.asm      ← brotli static dictionary
│   ├── bzip2/
│   │   ├── bzip2.asm           ← bzip2 compressor
│   │   ├── bzip2_decomp.asm    ← bzip2 decompressor
│   │   ├── bwt.asm             ← Burrows-Wheeler transform
│   │   ├── mtf.asm             ← move-to-front transform
│   │   ├── rle.asm             ← run-length encoding
│   │   └── huffman.asm         ← bzip2 huffman coding
│   ├── snappy/
│   │   ├── snappy.asm          ← snappy compressor
│   │   ├── snappy_decomp.asm   ← snappy decompressor
│   │   └── varint.asm          ← snappy varint encoding
│   ├── lzo/
│   │   ├── lzo.asm             ← lzo compressor
│   │   └── lzo_decomp.asm      ← lzo decompressor
│   ├── zopfli/
│   │   ├── zopfli.asm          ← zopfli deflate optimizer
│   │   ├── blocksplitter.asm   ← optimal block splitting
│   │   ├── squeeze.asm         ← optimal match finding
│   │   └── cache.asm           ← match cache
│   ├── lzss/
│   │   ├── lzss.asm            ← lzss compressor
│   │   └── lzss_decomp.asm     ← lzss decompressor
│   └── compress_z/
│       ├── compress.asm        ← .Z compressor (LZW)
│       └── uncompress.asm      ← .Z decompressor
│
├── checksum/
│   ├── crc32.asm               ← CRC32 (gzip, ZIP)
│   ├── crc64.asm               ← CRC64 (xz)
│   ├── adler32.asm             ← Adler32 (zlib)
│   ├── xxhash32.asm            ← xxHash32 (lz4)
│   ├── xxhash64.asm            ← xxHash64 (zstd)
│   └── xxhash3.asm             ← xxHash3 (zstd modern)
│
├── dict/
│   ├── zstd_dict.asm           ← zstd dictionary training + loading
│   ├── brotli_dict.asm         ← brotli static dictionary tables
│   └── dict_common.asm         ← shared dictionary primitives
│
├── mem/
│   ├── arena.asm
│   ├── alloc.asm
│   ├── pool.asm
│   └── align.asm
│
├── include/
│   └── ucmp.inc
│
├── bindings/
│   └── rust/
│       ├── Cargo.toml
│       ├── build.rs
│       ├── src/
│       │   ├── lib.rs
│       │   ├── sys.rs
│       │   ├── error.rs
│       │   ├── compress.rs
│       │   ├── decompress.rs
│       │   ├── stream.rs
│       │   ├── dict.rs
│       │   └── checksum.rs
│       └── tests/
│           └── integration.rs
│
├── tests/
│   ├── unit/
│   │   ├── arch/
│   │   │   ├── aarch64/
│   │   │   │   ├── crc32_test.asm
│   │   │   │   ├── adler32_test.asm
│   │   │   │   └── xxhash_test.asm
│   │   │   ├── x86_64/
│   │   │   │   ├── crc32_test.asm
│   │   │   │   ├── adler32_test.asm
│   │   │   │   └── xxhash_test.asm
│   │   │   └── riscv/
│   │   │       ├── crc32_test.asm
│   │   │       ├── adler32_test.asm
│   │   │       └── xxhash_test.asm
│   │   ├── core/
│   │   │   ├── stream_test.asm
│   │   │   ├── buffer_test.asm
│   │   │   ├── bitstream_test.asm
│   │   │   ├── huffman_test.asm
│   │   │   ├── lz77_test.asm
│   │   │   ├── matchfinder_test.asm
│   │   │   └── entropy_test.asm
│   │   ├── algo/
│   │   │   ├── deflate/
│   │   │   │   ├── deflate_test.asm
│   │   │   │   ├── inflate_test.asm
│   │   │   │   ├── huffman_static_test.asm
│   │   │   │   ├── huffman_dynamic_test.asm
│   │   │   │   └── window_test.asm
│   │   │   ├── zlib/
│   │   │   │   ├── zlib_test.asm
│   │   │   │   ├── header_test.asm
│   │   │   │   └── adler32_test.asm
│   │   │   ├── gzip/
│   │   │   │   ├── gzip_test.asm
│   │   │   │   ├── header_test.asm
│   │   │   │   └── crc32_test.asm
│   │   │   ├── zstd/
│   │   │   │   ├── zstd_test.asm
│   │   │   │   ├── zstd_decomp_test.asm
│   │   │   │   ├── frame_test.asm
│   │   │   │   ├── block_test.asm
│   │   │   │   ├── fse_test.asm
│   │   │   │   ├── huf_test.asm
│   │   │   │   ├── sequences_test.asm
│   │   │   │   └── dict_test.asm
│   │   │   ├── lz4/
│   │   │   │   ├── lz4_test.asm
│   │   │   │   ├── lz4_decomp_test.asm
│   │   │   │   ├── lz4hc_test.asm
│   │   │   │   └── frame_test.asm
│   │   │   ├── lzma/
│   │   │   │   ├── lzma_test.asm
│   │   │   │   ├── lzma_decomp_test.asm
│   │   │   │   ├── range_enc_test.asm
│   │   │   │   ├── range_dec_test.asm
│   │   │   │   ├── lz_test.asm
│   │   │   │   └── literals_test.asm
│   │   │   ├── xz/
│   │   │   │   ├── xz_test.asm
│   │   │   │   ├── stream_test.asm
│   │   │   │   ├── block_test.asm
│   │   │   │   ├── index_test.asm
│   │   │   │   ├── header_test.asm
│   │   │   │   └── crc64_test.asm
│   │   │   ├── brotli/
│   │   │   │   ├── brotli_test.asm
│   │   │   │   ├── brotli_decomp_test.asm
│   │   │   │   ├── prefix_test.asm
│   │   │   │   ├── context_test.asm
│   │   │   │   ├── metablock_test.asm
│   │   │   │   ├── transform_test.asm
│   │   │   │   └── dictionary_test.asm
│   │   │   ├── bzip2/
│   │   │   │   ├── bzip2_test.asm
│   │   │   │   ├── bzip2_decomp_test.asm
│   │   │   │   ├── bwt_test.asm
│   │   │   │   ├── mtf_test.asm
│   │   │   │   ├── rle_test.asm
│   │   │   │   └── huffman_test.asm
│   │   │   ├── snappy/
│   │   │   │   ├── snappy_test.asm
│   │   │   │   ├── snappy_decomp_test.asm
│   │   │   │   └── varint_test.asm
│   │   │   ├── lzo/
│   │   │   │   ├── lzo_test.asm
│   │   │   │   └── lzo_decomp_test.asm
│   │   │   ├── zopfli/
│   │   │   │   ├── zopfli_test.asm
│   │   │   │   ├── blocksplitter_test.asm
│   │   │   │   ├── squeeze_test.asm
│   │   │   │   └── cache_test.asm
│   │   │   ├── lzss/
│   │   │   │   ├── lzss_test.asm
│   │   │   │   └── lzss_decomp_test.asm
│   │   │   └── compress_z/
│   │   │       ├── compress_test.asm
│   │   │       └── uncompress_test.asm
│   │   ├── checksum/
│   │   │   ├── crc32_test.asm
│   │   │   ├── crc64_test.asm
│   │   │   ├── adler32_test.asm
│   │   │   ├── xxhash32_test.asm
│   │   │   ├── xxhash64_test.asm
│   │   │   └── xxhash3_test.asm
│   │   ├── dict/
│   │   │   ├── zstd_dict_test.asm
│   │   │   ├── brotli_dict_test.asm
│   │   │   └── dict_common_test.asm
│   │   └── mem/
│   │       ├── arena_test.asm
│   │       ├── alloc_test.asm
│   │       ├── pool_test.asm
│   │       └── align_test.asm
│   ├── integration/
│   │   ├── roundtrip_test.asm          ← compress → decompress → verify
│   │   ├── streaming_test.asm          ← streaming compress/decompress
│   │   ├── dict_roundtrip_test.asm     ← dictionary compress/decompress
│   │   ├── checksum_verify_test.asm    ← checksum correctness
│   │   ├── corrupt_input_test.asm      ← handle corrupt data gracefully
│   │   ├── empty_input_test.asm        ← edge case: empty input
│   │   ├── large_input_test.asm        ← multi-GB streams
│   │   ├── cross_algo_test.asm         ← compare ratios across algorithms
│   │   └── interop_test.asm            ← verify against reference impls
│   └── conformance/
│       ├── run.sh
│       ├── samples/
│       └── expected/
│
├── bench/
│   ├── micro/
│   │   ├── crc32_bench.asm
│   │   ├── adler32_bench.asm
│   │   ├── xxhash_bench.asm
│   │   ├── huffman_bench.asm
│   │   ├── matchfinder_bench.asm
│   │   ├── fse_bench.asm
│   │   └── mem_arena_bench.asm
│   └── macro/
│       ├── deflate_bench.asm
│       ├── zlib_bench.asm
│       ├── gzip_bench.asm
│       ├── zstd_bench.asm
│       ├── lz4_bench.asm
│       ├── lzma_bench.asm
│       ├── xz_bench.asm
│       ├── brotli_bench.asm
│       ├── bzip2_bench.asm
│       ├── snappy_bench.asm
│       ├── lzo_bench.asm
│       ├── ratio_comparison_bench.asm  ← all algos, same input, compare ratio
│       └── speed_comparison_bench.asm  ← all algos, same input, compare speed
│
├── docs/
│   ├── spec/
│   │   ├── deflate_spec.md
│   │   ├── zlib_spec.md
│   │   ├── gzip_spec.md
│   │   ├── zstd_spec.md
│   │   ├── lz4_spec.md
│   │   ├── lzma_spec.md
│   │   ├── xz_spec.md
│   │   ├── brotli_spec.md
│   │   ├── bzip2_spec.md
│   │   ├── snappy_spec.md
│   │   ├── lzo_spec.md
│   │   ├── zopfli_spec.md
│   │   └── checksum_spec.md
│   ├── api/
│   │   ├── ucmp_inc.md
│   │   └── rust_bindings.md
│   └── internals/
│       ├── architecture.md
│       ├── memory_model.md
│       ├── simd_strategy.md
│       ├── build_system.md
│       ├── algorithm_comparison.md
│       ├── dictionary_training.md
│       └── phase_roadmap.md
│
├── examples/
│   ├── c/
│   │   ├── compress_file.c
│   │   ├── decompress_file.c
│   │   ├── streaming_compress.c
│   │   ├── dict_compress.c
│   │   ├── checksum.c
│   │   └── arena_usage.c
│   └── rust/
│       ├── compress_file.rs
│       ├── decompress_file.rs
│       ├── streaming_compress.rs
│       ├── dict_compress.rs
│       └── checksum.rs
│
├── scripts/
│   ├── run_tests.sh
│   ├── run_bench.sh
│   └── gen_bindings.sh
│
├── third_party/
│   ├── samples/
│   └── specs/
│       ├── rfc1950_zlib.md
│       ├── rfc1951_deflate.md
│       ├── rfc1952_gzip.md
│       ├── rfc7932_brotli.md
│       ├── zstd_spec.md
│       ├── lz4_spec.md
│       └── xz_spec.md
│
├── Makefile
├── build.sh
├── README.md
├── CHANGELOG.md
├── LICENSE
├── CONTRIBUTING.md
└── .gitignore