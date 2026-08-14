# Tattva OS — Project Structure

> Assembly-native unikernel OS and inference stack by Utkarsha Labs.
> AArch64 · x86-64 · RISC-V

---

## Repository Root

```
tattva/
├── PROJECTSTRUCTURE.md     ← this file
├── STACK.html              ← full stack reference
├── README.md               ← project overview
├── LICENSE
├── .gitignore
│
├── boot/                   ← uboot — bootloader
├── asm/                    ← utasm — assembler/linker/disassembler
├── kernel/                 ← Tattva OS kernel
├── lib/                    ← all u-libraries (foundation stack)
├── crypto/                 ← crypto stack
├── net/                    ← network stack
├── storage/                ← filesystem + database
├── ai/                     ← inference + training stack
├── serve/                  ← serving + security layer
├── tools/                  ← coretools + devtools
├── utils/                  ← coreutils (linux compat commands)
├── obs/                    ← observability
├── bin/                    ← binary analysis + code intelligence
├── apps/                   ← first-party applications
├── pkg/                    ← package system + .upk packages
├── dist/                   ← distributed computing layer
├── hw/                     ← hardware abstraction (NUMA, GPU, CPU)
├── platform/               ← platform-specific code per arch
├── tests/                  ← global test suite
├── bench/                  ← benchmarks (umark)
├── docs/                   ← documentation
├── scripts/                ← build scripts, CI, tooling
└── third_party/            ← NASM bridge (temporary, replaced by utasm)
```

---

## boot/ — uboot Bootloader

```
boot/
├── stage1/                 ← MBR entry, exactly 512 bytes
│   ├── entry.asm           ← MBR entry point
│   ├── disk_read.asm       ← BIOS int 13h CHS/LBA
│   ├── lba_detect.asm      ← detect LBA support
│   ├── load_stage2.asm     ← find + load stage2
│   ├── relocate.asm        ← relocate self to 0x0600
│   └── signature.asm       ← 0x55AA boot signature
│
├── stage2/
│   ├── entry.asm
│   ├── a20/                ← A20 line enabling
│   │   ├── a20.asm
│   │   ├── a20_bios.asm
│   │   ├── a20_port92.asm
│   │   ├── a20_kbd.asm
│   │   └── a20_verify.asm
│   ├── cpu/                ← CPU feature detection
│   │   ├── cpuid.asm
│   │   ├── longmode.asm
│   │   ├── features.asm    ← SSE/AVX/NX/AMX detection
│   │   ├── vendor.asm      ← Intel/AMD/ARM
│   │   ├── cores.asm
│   │   ├── cache.asm
│   │   └── msr.asm
│   ├── gdt/                ← Global Descriptor Table
│   │   ├── gdt.asm
│   │   ├── gdt_load.asm
│   │   └── selectors.asm
│   ├── idt/                ← Interrupt Descriptor Table
│   │   ├── idt.asm
│   │   ├── idt_load.asm
│   │   └── idt_handlers.asm
│   ├── paging/             ← Page table setup
│   │   ├── paging.asm
│   │   ├── paging_map.asm
│   │   ├── paging_huge.asm ← 2MB huge pages
│   │   └── paging_nx.asm   ← NX bit enforcement
│   ├── memory/             ← Memory detection
│   │   ├── e820.asm        ← BIOS memory map
│   │   ├── e820_parse.asm
│   │   └── mtrr.asm
│   └── fs/                 ← Filesystem detection for kernel load
│       ├── bxp.asm         ← BXP native format (priority 1)
│       ├── gpt.asm         ← GPT partition table
│       ├── mbr.asm         ← MBR legacy
│       ├── fat32.asm       ← FAT32 fallback
│       └── ext2.asm        ← ext2 Linux compat
│
├── uefi/                   ← UEFI boot path (AArch64, x86)
│   ├── entry.asm
│   ├── protocol.asm        ← UEFI protocol handling
│   └── handoff.asm         ← handoff to kernel
│
├── survive/                ← Panic recovery — unique to Tattva
│   ├── snapshot.asm        ← hardware state snapshot
│   ├── hide.asm            ← hide page from e820
│   ├── vector.asm          ← panic vector installation
│   ├── wakeup.asm          ← panic handler entry
│   ├── diff.asm            ← state diff on panic
│   └── recover.asm         ← warm reload attempt
│
├── tpm/                    ← TPM integration
│   └── tpm.asm
│
└── tests/
    ├── stage1_test.asm
    ├── paging_test.asm
    └── survive_test.asm
```

---

## asm/ — utasm Assembler

```
asm/
├── assembler/
│   ├── lexer.asm           ← tokenize source
│   ├── parser.asm          ← parse tokens to AST
│   ├── encoder/            ← instruction encoding per arch
│   │   ├── aarch64/
│   │   │   ├── encode.asm
│   │   │   ├── simd.asm    ← NEON/SVE encoding
│   │   │   └── capabi.asm  ← capability register encoding (CHERI)
│   │   ├── x86_64/
│   │   │   ├── encode.asm
│   │   │   ├── avx.asm
│   │   │   └── amx.asm     ← Intel AMX encoding
│   │   └── riscv/
│   │       ├── encode.asm
│   │       └── cheri.asm   ← CHERI-RISC-V encoding
│   ├── directives.asm      ← .section .global .align etc
│   └── macros.asm          ← macro expansion
│
├── linker/
│   ├── linker.asm          ← main linker
│   ├── elf.asm             ← ELF output generation
│   ├── relocations.asm     ← relocation processing
│   ├── sections.asm        ← section merging
│   └── scripts/            ← default linker scripts
│       ├── tattva.ld       ← Tattva OS binary
│       ├── unikernel.ld    ← unikernel layout
│       └── upk.ld          ← .upk package layout
│
├── disassembler/
│   ├── dis.asm             ← main disassembler (udis)
│   ├── aarch64_dis.asm
│   ├── x86_64_dis.asm
│   └── riscv_dis.asm
│
├── safety/                 ← memory safety checker (ucheck)
│   ├── ownership.asm       ← ownership tracking
│   ├── borrow.asm          ← borrow checker
│   ├── lifetime.asm        ← lifetime analysis
│   ├── cfg.asm             ← control flow graph builder
│   ├── dataflow.asm        ← dataflow analysis
│   └── report.asm          ← violation reporting
│
├── linter/                 ← ulint
│   ├── style.asm           ← style checks
│   ├── convention.asm      ← calling convention checks
│   └── security.asm        ← uvuln patterns
│
├── annotations/            ← ownership annotation syntax
│   ├── own.asm             ← @own directive
│   ├── borrow.asm          ← @borrow directive
│   └── lifetime.asm        ← @lifetime directive
│
└── tests/
    ├── encode_test/
    ├── link_test/
    └── safety_test/
```

---

## kernel/ — Tattva OS Kernel

```
kernel/
├── entry/
│   ├── start.asm           ← kernel entry point from bootloader
│   ├── init.asm            ← kernel initialization sequence
│   └── main.asm            ← main kernel loop
│
├── arch/                   ← architecture-specific kernel code
│   ├── aarch64/
│   │   ├── exceptions.asm  ← exception vectors
│   │   ├── mmu.asm         ← MMU setup
│   │   └── smp.asm         ← multi-core bring-up
│   ├── x86_64/
│   │   ├── interrupts.asm  ← IDT, IRQ handling
│   │   ├── mmu.asm
│   │   └── smp.asm
│   └── riscv/
│       ├── traps.asm
│       ├── mmu.asm
│       └── smp.asm
│
├── mm/                     ← memory management
│   ├── pmm.asm             ← physical memory manager
│   ├── vmm.asm             ← virtual memory manager
│   ├── heap.asm            ← kernel heap
│   ├── arena.asm           ← arena allocator
│   ├── huge.asm            ← uhuge — huge page management
│   ├── pinmem.asm          ← upinmem — pinned memory
│   ├── swap.asm            ← uswap — CPU/NVMe offload
│   └── numa.asm            ← unuma — NUMA topology + affinity
│
├── sched/                  ← scheduler
│   ├── sched.asm           ← main scheduler
│   ├── rt.asm              ← usched_rt — real-time scheduler
│   ├── fair.asm            ← ufair — fair/weighted scheduler
│   ├── gang.asm            ← ugang — gang scheduling
│   ├── preempt.asm         ← upreempt — preemption
│   └── elastic.asm         ← uelastic — elastic worker pools
│
├── ipc/                    ← inter-process communication
│   ├── ipc.asm             ← IPC core
│   ├── signal.asm          ← usig — signal handling
│   ├── pipe.asm            ← pipes
│   └── shm.asm             ← shared memory
│
├── drivers/                ← device drivers
│   ├── gpu/
│   │   ├── gpu.asm         ← ugpu — GPU topology + management
│   │   ├── cuda.asm        ← CUDA driver API direct calls
│   │   └── metal.asm       ← Apple Metal (AMX)
│   ├── nvme/
│   │   └── nvme.asm        ← unvme — NVMe direct access
│   ├── net/
│   │   ├── nic.asm         ← NIC driver
│   │   └── xdp.asm         ← uafxdp — AF_XDP kernel bypass
│   ├── tpm/
│   │   └── tpm.asm         ← TPM driver
│   └── serial/
│       └── uart.asm        ← UART for early boot debug
│
├── security/
│   ├── iommu.asm           ← uiommu — IOMMU management
│   ├── tee.asm             ← utee — TEE/SGX/TrustZone
│   ├── attest.asm          ← uattest — remote attestation
│   ├── secboot.asm         ← usecboot — secure boot chain
│   └── chmod_ttl.asm       ← expiring permissions syscall
│
├── power/
│   └── power.asm           ← upower — freq scaling, thermal
│
├── ebpf/
│   └── ebpf.asm            ← uebpf — eBPF runtime
│
├── syscall/
│   ├── syscall.asm         ← syscall dispatch table
│   ├── table_aarch64.asm
│   ├── table_x86_64.asm
│   └── table_riscv.asm
│
└── tests/
    ├── mm_test/
    ├── sched_test/
    └── driver_test/
```

---

## lib/ — Foundation Libraries

```
lib/
├── mem/                    ← mem — memory primitives
│   ├── alloc.asm           ← malloc/free
│   ├── arena.asm           ← arena allocator
│   ├── pool.asm            ← pool allocator
│   ├── ops.asm             ← memcpy/set/cmp/move
│   └── tests/
│
├── io/                     ← io — I/O primitives
│   ├── fd.asm              ← file descriptor ops
│   ├── read.asm
│   ├── write.asm
│   ├── device.asm          ← device abstraction
│   ├── dma.asm             ← DMA primitives
│   ├── irq.asm             ← interrupt handling
│   └── tests/
│
├── str/                    ← str — string primitives
│   ├── basic.asm           ← strlen/cpy/cmp/cat
│   ├── format.asm          ← sprintf/snprintf
│   ├── convert.asm         ← atoi/itoa/atof
│   └── tests/
│
├── utf8/                   ← utf8 — Unicode primitives
│   ├── encode.asm          ← codepoint → bytes
│   ├── decode.asm          ← bytes → codepoint
│   ├── validate.asm        ← sequence validation
│   ├── iter.asm            ← forward/backward iteration
│   └── tests/
│
├── time/                   ← time — time primitives
│   ├── clock.asm           ← wall clock, monotonic
│   ├── tsc.asm             ← TSC cycle counter
│   ├── sleep.asm
│   └── tests/
│
├── cal/                    ← cal — calendar
│   ├── calendar.asm        ← Gregorian ops
│   ├── bikram.asm          ← Bikram Sambat (Nepali)
│   ├── timezone.asm
│   ├── format.asm          ← date formatting
│   └── tests/
│
├── urand/                  ← urand — CSPRNG
│   ├── entropy.asm         ← hardware entropy (RDRAND)
│   ├── csprng.asm          ← CSPRNG implementation
│   └── tests/
│
├── umath/                  ← umath — math + SIMD
│   ├── float.asm           ← float ops
│   ├── trig.asm            ← sin/cos/tan/log
│   ├── simd/
│   │   ├── neon.asm        ← AArch64 NEON
│   │   ├── sve.asm         ← AArch64 SVE
│   │   ├── avx2.asm        ← x86 AVX2
│   │   ├── avx512.asm      ← x86 AVX-512
│   │   └── amx.asm         ← Intel AMX / Apple AMX
│   ├── gemm/
│   │   ├── gemm.asm        ← general GEMM
│   │   ├── gemm_aarch64.asm
│   │   ├── gemm_x86.asm
│   │   └── gemm_bench.asm
│   ├── tensor.asm          ← tensor primitives
│   └── tests/
│
├── ulib/                   ← ulib — data structures
│   ├── vec.asm             ← dynamic array
│   ├── map.asm             ← hashmap
│   ├── set.asm             ← hash set
│   ├── list.asm            ← linked list
│   ├── queue.asm           ← FIFO queue
│   ├── deque.asm           ← double-ended queue
│   ├── stack.asm           ← LIFO stack
│   ├── ring.asm            ← ring buffer
│   ├── heap.asm            ← priority queue (min/max)
│   ├── btree.asm           ← B-tree
│   ├── bitset.asm          ← bit manipulation
│   ├── trie.asm            ← prefix tree
│   ├── serial/
│   │   ├── base64.asm
│   │   ├── varint.asm
│   │   └── uuid.asm
│   ├── error.asm           ← error types, result pattern
│   └── tests/
│
├── regex/                  ← regex — pattern matching
│   ├── compile.asm         ← compile pattern to NFA
│   ├── match.asm           ← NFA execution
│   ├── pcre.asm            ← PCRE compat layer
│   └── tests/
│
├── uparser/                ← uparser — grammar/AST engine
│   ├── lexer.asm           ← generic lexer
│   ├── ast.asm             ← AST node types
│   ├── grammars/
│   │   ├── surrealql.asm   ← SurrealQL grammar
│   │   ├── http.asm        ← HTTP header grammar
│   │   ├── toml.asm        ← TOML config
│   │   ├── json.asm        ← JSON
│   │   └── bxp.asm         ← BXP protocol grammar
│   └── tests/
│
├── ucmp/                   ← ucmp — compression
│   ├── zstd.asm            ← Zstandard
│   ├── lz4.asm             ← LZ4
│   ├── snappy.asm          ← Snappy
│   ├── deflate.asm         ← DEFLATE
│   ├── stream.asm          ← streaming compress/decompress
│   └── tests/
│
├── ulog/                   ← ulog — structured logging
│   ├── log.asm             ← core logger
│   ├── levels.asm          ← debug/info/warn/error
│   ├── fields.asm          ← structured fields
│   ├── sinks/
│   │   ├── file.asm
│   │   ├── serial.asm      ← early boot logging
│   │   └── net.asm         ← remote logging
│   └── tests/
│
├── ufile/                  ← ufile — magic bytes / MIME
│   ├── magic.asm           ← magic byte detection
│   ├── mime.asm            ← MIME type mapping
│   ├── signatures/         ← signature database
│   │   ├── elf.asm
│   │   ├── bxp.asm
│   │   ├── image.asm
│   │   ├── archive.asm
│   │   └── model.asm       ← GGUF, safetensors, ONNX
│   └── tests/
│
└── hw/                     ← hardware abstraction
    ├── unuma/              ← NUMA topology
    │   ├── detect.asm      ← NUMA node detection
    │   ├── affinity.asm    ← memory affinity binding
    │   └── distance.asm    ← NUMA distance matrix
    ├── ucpu/               ← CPU topology
    │   ├── topology.asm    ← core/thread/cache hierarchy
    │   └── pinning.asm     ← core pinning
    ├── ugpu/               ← GPU topology
    │   ├── detect.asm      ← GPU detection
    │   ├── pcie.asm        ← PCIe bandwidth mapping
    │   └── nvlink.asm      ← NVLink topology
    ├── uhwloc/             ← unified hardware locality
    │   └── hwloc.asm       ← combined topology map
    ├── uhbm/               ← HBM optimizations
    │   └── layout.asm      ← memory layout for HBM
    └── ucxl/               ← CXL memory
        └── cxl.asm         ← CXL memory pooling
```

---

## crypto/ — Crypto Stack

```
crypto/
├── uhash/                  ← hashing (no keys)
│   ├── sha256.asm
│   ├── sha384.asm
│   ├── sha512.asm
│   ├── sha3.asm
│   ├── blake3.asm          ← SIMD accelerated
│   ├── md5.asm             ← legacy compat
│   ├── stream.asm          ← streaming API
│   └── tests/
│
├── ucrypt/                 ← everything with keys
│   ├── symmetric/
│   │   ├── aes_gcm.asm
│   │   ├── chacha20.asm
│   │   └── xchacha20.asm
│   ├── asymmetric/
│   │   ├── ed25519.asm
│   │   ├── x25519.asm
│   │   ├── rsa.asm
│   │   └── ecdsa.asm
│   ├── pqc/                ← post-quantum
│   │   ├── kyber.asm       ← KEM
│   │   ├── dilithium.asm   ← signatures
│   │   ├── falcon.asm      ← compact signatures
│   │   └── sphincs.asm     ← stateless hash-based
│   ├── kdf/
│   │   ├── hkdf.asm
│   │   ├── pbkdf2.asm
│   │   ├── argon2id.asm
│   │   └── scrypt.asm
│   ├── mac/
│   │   ├── hmac.asm
│   │   ├── gmac.asm
│   │   └── poly1305.asm
│   └── tests/
│
├── uSSL/                   ← TLS implementation
│   ├── handshake.asm       ← TLS 1.3 handshake
│   ├── record.asm          ← record layer
│   ├── ktls.asm            ← kernel TLS
│   ├── cert.asm            ← certificate parsing
│   ├── session.asm         ← session management
│   └── tests/
│
├── usign/                  ← signing CLI tool
│   ├── sign.asm
│   ├── verify.asm
│   └── formats/
│       ├── ed25519.asm
│       └── upk_sign.asm    ← .upk package signing
│
└── umtls/                  ← mutual TLS
    ├── mtls.asm
    └── tests/
```

---

## net/ — Network Stack

```
net/
├── unet/                   ← TCP/IP core
│   ├── tcp.asm
│   ├── udp.asm
│   ├── ip4.asm
│   ├── ip6.asm
│   ├── icmp.asm
│   ├── arp.asm
│   ├── socket.asm          ← socket API
│   ├── xdp/                ← uafxdp kernel bypass
│   │   ├── xdp.asm
│   │   └── zerocopy.asm
│   └── tests/
│
├── udns/                   ← DNS resolver
│   ├── resolve.asm
│   ├── cache.asm
│   ├── mdns.asm            ← mDNS for local discovery
│   └── tests/
│
├── uhttp/                  ← HTTP primitives
│   ├── http1.asm
│   ├── http2.asm
│   ├── quic.asm            ← QUIC protocol
│   ├── headers.asm
│   └── tests/
│
├── uSSH/                   ← SSH
│   ├── server.asm
│   ├── client.asm
│   ├── auth.asm
│   └── tests/
│
├── urdma/                  ← RDMA
│   ├── rdma.asm
│   ├── roce.asm            ← RoCE (RDMA over Ethernet)
│   └── ib.asm              ← InfiniBand
│
├── ugossip/                ← gossip protocol
│   ├── gossip.asm          ← node discovery, state propagation
│   └── failure.asm         ← failure detection
│
├── tools/                  ← network tools
│   ├── uping.asm
│   ├── knock.asm
│   ├── utcp.asm
│   ├── usniff.asm
│   ├── upkt.asm
│   ├── ulatency.asm
│   ├── silent.asm
│   ├── arp.asm
│   ├── ip.asm
│   ├── route.asm
│   ├── host.asm
│   ├── whois.asm
│   └── netmon.asm
│
└── tests/
```

---

## storage/ — Storage Stack

```
storage/
├── uxfs/                    ← Tattva filesystem
│   ├── inode.asm           ← inode structure (includes TTL field)
│   ├── journal.asm         ← journaling
│   ├── alloc.asm           ← block allocation
│   ├── path.asm            ← path resolution
│   ├── mount.asm           ← mount/unmount (umount lives here)
│   ├── dir.asm             ← directory ops
│   ├── chmod_ttl.asm       ← expiring permissions
│   └── tests/
│
├── uwal/                   ← write-ahead log
│   ├── wal.asm             ← WAL core
│   ├── segment.asm         ← segment management
│   ├── recovery.asm        ← crash recovery
│   ├── fsync.asm           ← durability guarantees
│   └── tests/
│
├── ubxp/                   ← BXP binary protocol
│   ├── encode.asm
│   ├── decode.asm
│   ├── schema.asm          ← schema definitions
│   └── tests/
│
├── udb/                    ← multi-model database (rename TBD)
│   ├── core/
│   │   ├── engine.asm      ← database engine core
│   │   ├── txn.asm         ← transactions, MVCC
│   │   ├── lock.asm        ← locking primitives
│   │   └── buffer.asm      ← buffer pool manager
│   ├── kv/                 ← key-value store
│   │   ├── kv.asm
│   │   └── lsm.asm         ← LSM tree
│   ├── sql/                ← SQL engine
│   │   ├── parser.asm      ← SQL parser (uses uparser)
│   │   ├── planner.asm     ← query planner
│   │   ├── optimizer.asm   ← cost-based optimizer
│   │   ├── executor.asm    ← query executor
│   │   └── storage.asm     ← columnar storage
│   ├── vector/             ← vector store
│   │   ├── index.asm       ← HNSW, IVF index
│   │   ├── search.asm      ← ANN search
│   │   └── quantize.asm    ← vector quantization
│   ├── graph/              ← graph database
│   │   ├── graph.asm
│   │   └── traverse.asm
│   ├── timeseries/         ← time-series store
│   │   └── ts.asm
│   ├── distributed/        ← distributed mode
│   │   ├── raft.asm        ← uraft consensus
│   │   ├── shard.asm       ← sharding
│   │   └── replicate.asm   ← replication
│   ├── inspect/            ← storage adjacent tools
│   │   ├── upage.asm       ← page inspector
│   │   ├── uquery.asm      ← standalone query tester
│   │   └── uidx.asm        ← index integrity checker
│   └── tests/
│
├── uobject/                ← object storage (was Sangraha)
│   ├── object.asm          ← S3-compatible API
│   ├── bucket.asm
│   └── tests/
│
├── ummapf/                 ← memory-mapped files
│   ├── mmap.asm
│   └── tests/
│
├── unvme/                  ← NVMe direct access
│   ├── nvme.asm
│   └── tests/
│
└── utiered/                ← tiered storage manager
    ├── tier.asm            ← HBM→DRAM→NVMe→S3 hierarchy
    ├── migrate.asm         ← auto data migration
    └── tests/
```

---

## ai/ — AI / Inference Stack

```
ai/
├── kernels/                ← low-level compute kernels
│   ├── uattn/              ← attention
│   │   ├── attn.asm        ← standard attention
│   │   ├── flash.asm       ← FlashAttention style
│   │   ├── causal.asm      ← causal mask
│   │   └── gqa.asm         ← grouped query attention
│   ├── uffn/               ← feed-forward network
│   │   ├── ffn.asm         ← fused linear + activation
│   │   ├── swiglu.asm      ← SwiGLU
│   │   └── geglu.asm       ← GeGLU
│   ├── unorm/              ← normalization
│   │   ├── rmsnorm.asm     ← RMSNorm (LLaMA)
│   │   └── layernorm.asm   ← LayerNorm (GPT)
│   ├── uact/               ← activation functions
│   │   ├── gelu.asm
│   │   ├── silu.asm
│   │   └── relu.asm
│   ├── uembed/             ← embeddings
│   │   ├── embed.asm       ← token embedding lookup
│   │   ├── rope.asm        ← RoPE position embedding
│   │   ├── alibi.asm       ← ALiBi
│   │   └── sinusoidal.asm
│   ├── usparse/            ← sparse attention
│   │   ├── sliding.asm     ← sliding window (Mistral)
│   │   └── local_global.asm
│   └── uquant/             ← quantization kernels
│       ├── int8.asm
│       ├── int4.asm
│       ├── fp8.asm         ← H100 native
│       ├── nf4.asm         ← QLoRA format
│       ├── gptq.asm        ← GPTQ post-training quant
│       ├── awq.asm         ← activation-aware quant
│       └── dequant.asm     ← dequantize for compute
│
├── memory/                 ← KV cache + memory management
│   ├── upaged/             ← PagedAttention
│   │   ├── paged.asm       ← non-contiguous KV blocks
│   │   └── alloc.asm       ← block allocator
│   ├── ukvcache/           ← KV cache manager
│   │   ├── kvcache.asm
│   │   ├── evict.asm       ← LRU eviction
│   │   └── persist.asm     ← udb-backed persistence
│   ├── uprefix/            ← prefix caching
│   │   ├── prefix.asm      ← hash + reuse prefixes
│   │   └── store.asm       ← udb-backed prefix store
│   └── uswap/              ← CPU/NVMe offload
│       ├── offload.asm     ← weight offloading
│       └── stream.asm      ← streaming weights
│
├── tokenize/               ← tokenization
│   ├── utok/
│   │   ├── bpe.asm         ← Byte Pair Encoding (GPT)
│   │   ├── wordpiece.asm   ← WordPiece (BERT)
│   │   ├── sentpiece.asm   ← SentencePiece (LLaMA)
│   │   ├── tiktoken.asm    ← Tiktoken compat (GPT-4)
│   │   └── vocab.asm       ← vocabulary management
│   └── uencode/            ← multimodal encoding
│       ├── text.asm        ← text → tokens
│       ├── image.asm       ← image → patch embeddings
│       ├── audio.asm       ← audio → mel spectrogram
│       └── video.asm       ← video → frame embeddings
│
├── decode/                 ← decoding strategies
│   └── udecode/
│       ├── greedy.asm      ← greedy decoding
│       ├── beam.asm        ← beam search
│       ├── topk.asm        ← top-K sampling
│       ├── topp.asm        ← nucleus sampling
│       ├── minp.asm        ← min-P sampling
│       ├── temperature.asm ← temperature scaling
│       ├── mirostat.asm    ← perplexity-controlled
│       ├── typical.asm     ← typical sampling
│       ├── penalty.asm     ← repetition penalty
│       └── speculate/      ← uspeculate
│           ├── draft.asm   ← draft model generation
│           ├── verify.asm  ← large model verification
│           └── accept.asm  ← accept/reject logic
│
├── models/                 ← model architecture support
│   ├── ullama/             ← LLaMA family
│   │   ├── llama.asm       ← LLaMA architecture
│   │   ├── llama2.asm
│   │   └── llama3.asm
│   ├── umistral/           ← Mistral family
│   │   ├── mistral.asm
│   │   └── mixtral.asm     ← Mixtral MoE
│   ├── umoe/               ← Mixture of Experts
│   │   ├── router.asm      ← expert routing
│   │   ├── expert.asm      ← expert execution
│   │   └── balance.asm     ← load balancing
│   ├── uvision/            ← vision encoder
│   │   ├── vit.asm         ← Vision Transformer
│   │   └── patch.asm       ← patch embedding
│   └── uwhisper/           ← audio encoder-decoder
│       ├── encoder.asm
│       ├── decoder.asm
│       └── mel.asm         ← mel spectrogram
│
├── formats/                ← model format support
│   ├── ugguf/              ← GGUF (llama.cpp)
│   │   ├── read.asm
│   │   └── write.asm
│   ├── usafetensor/        ← safetensors (HuggingFace)
│   │   ├── read.asm
│   │   └── write.asm
│   ├── uonnx/              ← ONNX
│   │   ├── read.asm
│   │   ├── write.asm
│   │   └── ops.asm         ← ONNX op implementations
│   ├── uggml/              ← GGML (legacy)
│   │   └── read.asm
│   ├── upickle/            ← PyTorch pickle reader
│   │   └── read.asm        ← dangerous but needed for compat
│   └── uconvert/           ← format converter
│       ├── convert.asm     ← main converter
│       └── targets/
│           ├── to_tattva.asm
│           ├── to_gguf.asm
│           └── to_onnx.asm
│
├── umodel/                 ← model loader (uses formats/)
│   ├── loader.asm          ← weight loading
│   ├── mmap.asm            ← memory-mapped loading
│   └── shard.asm           ← sharded model loading
│
├── uinfer/                 ← inference engine
│   ├── engine.asm          ← transformer runtime loop
│   ├── forward.asm         ← forward pass
│   ├── batch.asm           ← request batching
│   ├── sample.asm          ← sampling (calls udecode)
│   └── tests/
│
├── ubatch/                 ← batch processing engine
│   ├── queue.asm           ← job queue (udb backed)
│   ├── scheduler.asm       ← priority scheduler
│   ├── workers.asm         ← worker pool
│   ├── continuous.asm      ← continuous batching
│   ├── prefix_cache.asm    ← prefix cache management
│   ├── result.asm          ← async result store
│   └── tests/
│
├── utrain/                 ← training loop
│   ├── forward.asm         ← forward pass
│   ├── backward.asm        ← backward pass
│   ├── grad.asm            ← gradient accumulation
│   ├── checkpoint.asm      ← udb checkpoint
│   └── tests/
│
├── uoptim/                 ← optimizer kernels
│   ├── adam.asm            ← fused Adam
│   ├── adamw.asm           ← AdamW
│   └── tests/
│
└── distributed/            ← distributed training
    ├── uallreduce/         ← gradient aggregation
    │   ├── ring.asm        ← ring-AllReduce
    │   └── tree.asm        ← tree-AllReduce
    ├── ucollective/        ← collective ops
    │   ├── allgather.asm
    │   ├── reducescatter.asm
    │   ├── broadcast.asm
    │   └── barrier.asm
    ├── uppipe/             ← pipeline parallelism
    │   ├── pipeline.asm
    │   ├── microbatch.asm
    │   └── bubble.asm      ← bubble minimization
    ├── utensor/            ← tensor parallelism
    │   ├── col_parallel.asm
    │   └── row_parallel.asm
    ├── usharding/          ← ZeRO sharding
    │   ├── zero1.asm       ← optimizer state sharding
    │   ├── zero2.asm       ← + gradient sharding
    │   └── zero3.asm       ← + parameter sharding
    ├── ucheckpoint/        ← distributed checkpoint
    │   ├── save.asm
    │   ├── restore.asm
    │   └── async.asm       ← async checkpoint during training
    └── uelastic/           ← elastic training
        ├── elastic.asm     ← add/remove nodes mid-training
        └── recover.asm     ← node failure recovery
```

---

## serve/ — Serving + Security Layer

```
serve/
├── userve/                 ← HTTP/3 + QUIC server (was Garuda)
│   ├── server.asm
│   ├── quic.asm
│   ├── router.asm
│   └── tests/
│
├── uauth/                  ← auth server (was Dvara)
│   ├── jwt.asm
│   ├── session.asm
│   ├── oauth2.asm
│   └── tests/
│
├── niti/                   ← firewall
│   ├── filter.asm          ← packet filtering
│   ├── rules.asm           ← rule engine
│   ├── ebpf/               ← eBPF test layer (test here first)
│   └── tests/
│
├── ugate/                  ← API gateway (was Sangam)
│   ├── gateway.asm
│   ├── ratelimit.asm
│   ├── routing.asm
│   └── tests/
│
├── ulb/                    ← load balancer
│   ├── lb.asm
│   ├── health.asm          ← health checking
│   └── tests/
│
├── uaudit/                 ← audit trail
│   ├── audit.asm
│   └── tests/
│
├── uopenai/                ← OpenAI API compat layer
│   ├── chat.asm            ← /v1/chat/completions
│   ├── completions.asm     ← /v1/completions
│   ├── embeddings.asm      ← /v1/embeddings
│   └── tests/
│
├── ustream/                ← streaming responses
│   ├── sse.asm             ← Server-Sent Events
│   ├── delta.asm           ← delta encoding
│   └── tests/
│
├── uembedding/             ← embedding serving
│   ├── embed.asm           ← batch embed documents
│   └── tests/
│
└── urerank/                ← reranking model serving
    ├── rerank.asm
    └── tests/
```

---

## dist/ — Distributed Computing Layer

```
dist/
├── udist/                  ← distributed runtime
│   ├── node.asm            ← node identity + membership
│   ├── discover.asm        ← node discovery
│   ├── heartbeat.asm       ← failure detection
│   └── tests/
│
├── uraft/                  ← Raft consensus
│   ├── raft.asm
│   ├── leader.asm          ← leader election
│   ├── log.asm             ← log replication
│   └── tests/
│
├── urpc/                   ← RPC framework
│   ├── rpc.asm             ← BXP-based async RPC
│   ├── call.asm
│   └── tests/
│
├── umesh/                  ← service mesh
│   ├── mesh.asm
│   ├── lb.asm              ← mesh load balancing
│   └── tests/
│
└── uchord/                 ← distributed hash table
    ├── chord.asm           ← consistent hashing
    ├── join.asm            ← node join/leave
    └── tests/
```

---

## obs/ — Observability

```
obs/
├── umetric/                ← metrics (was Drishti)
│   ├── counter.asm
│   ├── gauge.asm
│   ├── histogram.asm
│   └── tests/
│
├── utrace/                 ← distributed tracing
│   ├── span.asm
│   ├── propagate.asm
│   └── tests/
│
├── umark/                  ← benchmark suite (was Mapana)
│   ├── pmu.asm             ← PMU hardware counters
│   ├── cycle.asm           ← cycle accurate timing
│   ├── bench/              ← benchmark suites
│   │   ├── compute/
│   │   │   ├── gemm_bench.asm
│   │   │   ├── attn_bench.asm
│   │   │   └── simd_bench.asm
│   │   ├── memory/
│   │   │   ├── alloc_bench.asm
│   │   │   ├── bandwidth_bench.asm
│   │   │   └── cache_bench.asm
│   │   ├── storage/
│   │   │   ├── udb_bench.asm
│   │   │   └── io_bench.asm
│   │   ├── network/
│   │   │   ├── userve_bench.asm
│   │   │   └── latency_bench.asm
│   │   └── inference/
│   │       ├── tokens_sec.asm
│   │       ├── ttft_bench.asm
│   │       └── batch_bench.asm
│   └── tests/
│
├── uprof/                  ← sampling profiler
│   ├── profiler.asm
│   └── tests/
│
├── usym/                   ← symbol table inspector
│   └── sym.asm
│
├── umap_proc/              ← memory map visualizer
│   └── mmap.asm
│
├── uleak/                  ← memory leak detector
│   └── leak.asm
│
├── uflame/                 ← flame graph generator
│   └── flame.asm
│
├── utopology/              ← cluster topology visualizer
│   └── topology.asm
│
├── udash/                  ← web dashboard (was Tribhuvan)
│   └── dash.asm            ← served by userve
│
└── utui/                   ← terminal UI dashboard
    └── tui.asm
```

---

## tools/ — Coretools + Devtools

```
tools/
├── coretools/
│   ├── ush/                ← shell + init (PID 1)
│   │   ├── shell.asm
│   │   ├── init.asm        ← PID 1
│   │   ├── jobs.asm        ← job control
│   │   └── script.asm      ← scripting
│   ├── udbg/               ← debugger
│   │   ├── dbg.asm
│   │   ├── break.asm       ← breakpoints
│   │   ├── watch.asm       ← watchpoints
│   │   └── inspect.asm     ← memory inspection
│   ├── ucore/              ← core dump analyzer
│   │   └── core.asm
│   ├── ustep/              ← single-step executor
│   │   └── step.asm
│   ├── ustack/             ← stack unwinder
│   │   └── unwind.asm
│   ├── usched_vis/         ← scheduler visualizer
│   │   └── sched.asm
│   ├── usig/               ← signal inspector
│   │   └── sig.asm
│   ├── ulock/              ← deadlock detector
│   │   └── lock.asm
│   ├── uproc/              ← process inspector
│   │   └── proc.asm
│   ├── ubuild/             ← build system
│   │   ├── build.asm
│   │   ├── deps.asm        ← dependency graph
│   │   └── cache.asm       ← build cache
│   ├── utest/              ← test runner
│   │   ├── runner.asm
│   │   ├── assert.asm
│   │   └── coverage.asm    ← ucov
│   ├── ucov/               ← code coverage
│   │   └── cov.asm
│   ├── ufuzz/              ← fuzzer
│   │   └── fuzz.asm
│   ├── uperf/              ← profiler CLI
│   │   └── perf.asm
│   ├── uget/               ← downloader
│   │   └── get.asm
│   └── uscan/              ← scanner
│       ├── portscan.asm
│       └── secscan.asm     ← static security scan
│
├── binary/                 ← binary analysis + code intelligence
│   ├── udis.asm            ← disassembler
│   ├── uelf.asm            ← ELF inspector
│   ├── usect.asm           ← section manipulator
│   ├── urel.asm            ← relocation viewer
│   ├── ubind.asm           ← linker inspector
│   ├── uimport.asm         ← import/export analyzer
│   ├── usize.asm           ← size analyzer
│   ├── ucall.asm           ← call graph extractor
│   ├── uabi.asm            ← ABI checker
│   ├── ustrip.asm          ← strip debug symbols
│   ├── uhex.asm            ← hex dump
│   ├── usym.asm            ← symbol inspector
│   ├── utags.asm           ← ctags for asm
│   ├── uxref.asm           ← cross-reference
│   ├── ugrep.asm           ← asm-aware grep
│   ├── ucount.asm          ← LOC counter
│   ├── ureg.asm            ← register pressure visualizer
│   ├── usimd.asm           ← SIMD validator
│   ├── uisa.asm            ← ISA coverage report
│   └── fossil.asm          ← binary behavior diff
│
├── unix/                   ← unix-style sharp tools
│   ├── cost.asm            ← resource usage after command
│   ├── why.asm             ← which source line caused instruction
│   ├── blame.asm           ← which function owns binary size
│   ├── cold.asm            ← cold-start timing
│   ├── noise.asm           ← variance across N runs
│   ├── knock.asm           ← raw TCP handshake timer
│   ├── utcp.asm            ← TCP session inspector
│   ├── usniff.asm          ← network sniffer
│   ├── upkt.asm            ← BXP packet inspector
│   ├── ulatency.asm        ← inter-service latency
│   ├── silent.asm          ← outbound connection watcher
│   └── fossil.asm          ← binary behavior diff
│
└── devtools/
    ├── upm/                ← package manager
    │   ├── pm.asm
    │   ├── install.asm
    │   ├── resolve.asm     ← dependency resolution
    │   └── sign.asm        ← package signing
    ├── smriti/             ← version control (git alt)
    │   ├── smriti.asm
    │   ├── commit.asm
    │   ├── branch.asm
    │   ├── merge.asm
    │   └── pack.asm        ← pack format
    ├── uedit/              ← text editor
    │   └── edit.asm
    ├── ufont/              ← glyph rendering
    │   ├── font.asm
    │   ├── ttf.asm         ← TTF parser
    │   └── raster.asm      ← rasterizer
    ├── udoc/               ← doc generator
    │   └── doc.asm
    ├── uenv/               ← environment manager
    │   └── env.asm
    ├── drift.asm           ← live file diff
    ├── shadow.asm          ← auto-rerun + diff
    ├── spine.asm           ← structural skeleton viewer
    ├── usim/               ← hardware simulator
    │   └── sim.asm
    ├── uqemu/              ← QEMU integration
    │   └── qemu.asm
    ├── ucross/             ← cross-compiler support
    │   └── cross.asm
    └── udeploy/            ← deployment tool
        └── deploy.asm
```

---

## utils/ — Coreutils (Linux Compat)

```
utils/
├── file/
│   ├── cat.asm
│   ├── head.asm
│   ├── tail.asm
│   ├── less.asm
│   ├── more.asm
│   ├── cp.asm
│   ├── mv.asm
│   ├── rm.asm
│   ├── mkdir.asm
│   └── rmdir.asm
├── dir/
│   ├── ls.asm
│   ├── size.asm            ← du equiv
│   └── disk.asm            ← df equiv
├── text/
│   ├── echo.asm
│   ├── clear.asm
│   ├── wc.asm
│   ├── search.asm          ← find + grep unified
│   ├── diff.asm
│   └── patch.asm
├── process/
│   ├── top.asm
│   ├── uptime.asm
│   ├── ps.asm
│   ├── kill.asm
│   └── pkill.asm
├── system/
│   ├── chmod.asm
│   ├── chown.asm
│   ├── env.asm
│   ├── whoami.asm
│   ├── which.asm
│   ├── where.asm
│   ├── cron.asm
│   └── power.asm
├── archive/
│   ├── tar.asm
│   └── zip.asm
└── docs/
    ├── man.asm
    ├── help.asm
    ├── info.asm
    └── gnulist.asm
```

---

## apps/ — First-Party Applications

```
apps/
├── smriti/                 ← version control (also in devtools, standalone app)
├── doot/                   ← messaging (was Doot)
│   └── doot.asm
├── raga/                   ← audio AI (was Raga)
│   └── raga.asm
└── OxideChat/              ← post-quantum secure chat (final year project)
    ├── client.asm
    ├── server.asm
    └── protocol.asm        ← uses uSSL + ucrypt PQC
```

---

## pkg/ — Package System

```
pkg/
├── format/
│   ├── upk.asm             ← .upk package format spec
│   ├── manifest.asm        ← package manifest
│   └── sign.asm            ← package signature
├── registry/               ← package registry
│   └── registry.asm
└── packages/               ← official Utkarsha packages
    ├── core.upk
    ├── net.upk
    └── ai.upk
```

---

## platform/ — Architecture-Specific Code

```
platform/
├── aarch64/
│   ├── boot.asm            ← AArch64 boot specifics
│   ├── simd.asm            ← NEON/SVE
│   ├── amx.asm             ← Apple AMX
│   └── cheri.asm           ← Morello CHERI support
├── x86_64/
│   ├── boot.asm
│   ├── avx.asm             ← AVX/AVX2/AVX-512
│   ├── amx.asm             ← Intel AMX
│   └── cet.asm             ← CET shadow stacks
└── riscv/
    ├── boot.asm
    └── cheri.asm           ← CHERI-RISC-V support
```

---

## tests/ — Global Test Suite

```
tests/
├── unit/                   ← unit tests per module
├── integration/            ← cross-module integration tests
├── e2e/                    ← end-to-end system tests
├── fuzz/                   ← fuzzing harnesses
├── bench/                  ← benchmark comparisons
│   ├── vs_pytorch/         ← assembly vs PyTorch numbers
│   ├── vs_vllm/            ← assembly vs vLLM
│   └── vs_linux/           ← Tattva OS vs Linux baseline
└── qemu/                   ← QEMU automated boot tests
```

---

## bench/ — Benchmarks

```
bench/
├── gemm/                   ← GEMM vs cuBLAS, MKL
├── inference/              ← tokens/sec, TTFT, latency
├── database/               ← udb vs SurrealDB, Postgres, Redis
├── network/                ← userve vs nginx, caddy
└── os/                     ← Tattva OS vs Linux baseline
```

---

## docs/ — Documentation

```
docs/
├── PROJECTSTRUCTURE.md     ← this file (symlink)
├── STACK.html              ← full stack reference (symlink)
├── architecture/
│   ├── overview.md
│   ├── uboot.md
│   ├── kernel.md
│   ├── inference.md
│   └── distributed.md
├── modules/                ← per-module docs (generated by udoc)
├── api/                    ← API reference
└── guides/
    ├── getting_started.md
    ├── build.md
    └── contribute.md
```

---

## third_party/ — Temporary NASM Bridge

```
third_party/
└── nasm/                   ← NASM bridge (replaced by utasm when ready)
    ├── README.md           ← explains this is temporary
    ├── gemm/               ← GEMM kernels in NASM
    ├── uhash/              ← uhash in NASM
    └── ulib/               ← ulib foundations in NASM
```

---

## Build Order

```
1.  platform/               ← arch detection
2.  boot/                   ← uboot (independent)
3.  asm/                    ← utasm (independent)
4.  lib/mem/                ← absolute first
5.  lib/io/
6.  lib/str/
7.  lib/utf8/
8.  lib/urand/
9.  lib/time/ + lib/cal/
10. lib/umath/
11. lib/ulib/
12. lib/regex/ + lib/uparser/ + lib/ucmp/ + lib/ulog/ + lib/ufile/
13. crypto/uhash/
14. crypto/ucrypt/
15. kernel/                 ← kernel (needs lib/ + crypto/)
16. storage/uxfs/ + storage/uwal/ + storage/ubxp/
17. storage/udb/
18. net/unet/ + net/udns/ + net/uhttp/
19. crypto/uSSL/ + net/uSSH/
20. serve/                  ← serving layer
21. ai/kernels/             ← AI kernels
22. ai/memory/
23. ai/tokenize/
24. ai/decode/
25. ai/models/
26. ai/formats/
27. ai/uinfer/ + ai/ubatch/ + ai/utrain/
28. ai/distributed/
29. dist/                   ← distributed runtime
30. obs/                    ← observability
31. tools/                  ← all tools
32. utils/                  ← coreutils
33. apps/                   ← applications
34. pkg/                    ← package system
```

---

## Key Design Rules

```
1. Nothing in layer N imports from layer N+1
2. Every module has a tests/ subdirectory
3. All assembly uses Tattva calling conventions — not NASM idioms
4. third_party/ is the only exception to pure assembly rule
5. platform/ contains only arch-specific code, nothing else
6. apps/ depend on everything but nothing depends on apps/
7. tools/ depend on lib/ + binary output, not on serve/ or ai/
8. udb rename propagates everywhere when decided
```

---

*Utkarsha Labs © 2026 — Building the last software stack.*
