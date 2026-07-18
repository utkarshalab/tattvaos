# Tattva OS — `lib/io` Subsystem Design Specification

This document defines the architecture, directory layout, calling conventions, shared
structures, error codes, build order, init sequence, and per-module implementation
specifications for the Tattva OS I/O subsystem (`lib/io`).

It is the authoritative hand-off document for implementation. When two implementers
touch the same seam (struct offset, vector number, error code, calling convention),
this document is the tie-breaker — not the code.

Conventions inherited from the rest of the stack: `.asm` extensions, `IO_FUNC` /
`IO_ENDFUNC` macros on every routine, `guard_null` on every pointer at entry, RSO
(Register Semantic Ownership) annotations, semantic error-code ranges, zero external
dependencies, caller-provided arena memory (no hidden allocation, no `malloc`).

---

## 0. External Dependencies & mem Contract

### 0.1 `lib/mem` Arena Interface Contract

`lib/io` has zero external library dependencies, with the sole exception of the kernel's memory allocator library `lib/mem`. To prevent hidden or unpredictable allocations, `lib/io` adheres to the following contract with `lib/mem`:
* `lib/io` consumes `arena_alloc`, `pool_alloc`, and `pool_free` from `lib/mem`.
* These allocation functions return a zeroed, valid pointer on success, or `NULL` (0) on failure.
* `lib/io` MUST NOT call any `mem` allocation functions from within Interrupt Service Routine (ISR) context to prevent deadlock and re-entrancy issues.
* All memory used by `lib/io` for descriptors, buffers, queues, and metadata is backed by explicit arenas or pools established during early initialization.

---

### 0.2 Priority Tags

| Tag | Meaning |
| :-- | :-- |
| `[bring-up]` | Required to boot in single-core QEMU/x86-64 and read early blocks. |
| `[AI-critical]` | Differentiating features for high-throughput GPU weight/dataset streaming. |
| `[SMP]` | Multi-core correctness and scaling. Phase 2. |
| `[P2P]` | PCIe peer-to-peer / GPUDirect data path. Phase 2. |
| `[hardening]` | Robust error recovery, hotplug, power, telemetry. |
| `[optional]` | Valuable but deferrable; not on the critical path to a working AI data path. |

The critical path to first light is the `[bring-up]` set only. Everything else slots
in against a working skeleton.

---

## 1. Feature Surface

### A. Foundation & Arch Abstraction
* `[bring-up]` **Subsystem Error Bands** — non-overlapping error codes in the reserved
  top-page band (see §3). Every code carries its originating subsystem.
* `[bring-up]` **ABI Macros** — `IO_FUNC` / `IO_ENDFUNC`, `guard_null` / `guard_bar` /
  `guard_handle`, RSO annotations.
* `[bring-up]` **Boot Handoff Ingest** — consume the `boot_params` handoff struct from
  `boot` (memory map, ACPI RSDP pointer, framebuffer info, boot device handle, initial
  page-table root). io does not re-discover what the bootloader already resolved.
* `[bring-up]` **ACPI Table Parsing** — RSDP → XSDT → **MADT** (LAPIC/IO-APIC topology),
  **MCFG** (PCIe ECAM base — required for MMIO config access), **FADT** (reset register,
  power). RSDP pointer arrives via boot handoff; io walks the rest.
* `[bring-up]` **Per-CPU Storage Primitive** — `IA32_GS_BASE` + `swapgs` (x86-64),
  `TPIDR_EL1` (AArch64). Foundation for per-core rings, per-core NVMe queues, affinity.
* `[bring-up]` **x86-64 Ports & MMIO** — `in`/`out` macros, barrier-safe MMIO accessors.
* `[SMP]` **PAT / MTRR Memory-Type Control** — WC on GPU BAR apertures, UC on control
  registers, WB on normal DMA buffers. Prerequisite for correct P2P and MMIO.
* `[hardening]` **C ABI Headers & Rust Bindings** — `include/` + `include/rust/`.
* `[hardening]` **AArch64 & RISC-V MMIO** — GIC / PLIC register abstractions.

### B. Descriptor & Handle Layer
* `[bring-up]` **Typed Descriptor Table** — files, block devices, char devices, event
  objects, pipes. Sockets reserved for `unet`.
* `[bring-up]` **Refcounted Handle Lifecycle** — generation counters defeat use-after-free;
  O(1) lookup with `guard_handle`.
* `[bring-up]` **Stale Handle Invalidation** — `FD_OPEN → FD_STALE`; stale use returns
  `IO_ERR_STALE`. Cheap bit in `core/fd.asm`; full hotplug event path is `[hardening]`.

### C. Buffer, Scatter-Gather & DMA Memory
* `[bring-up]` **Arena-Backed Buffers** — `mem` arenas/pools, never `malloc`.
* `[bring-up]` **Cache-Line Alignment** — all DMA buffers aligned to 64 B (x86-64/AArch64
  L1 line); alignment queried, not assumed.
* `[bring-up]` **Iovec Scatter-Gather** — sector-aligned `iovec` chains over
  non-contiguous physical pages.
* `[bring-up]` **Page-Crossing Split** — a virtual buffer crossing a physical page
  boundary is automatically split into multiple SGL/PRP entries.
* `[bring-up]` **DMA Bounce Buffers** — intermediate buffers below the 4 GB line for
  32-bit-addressing controllers.
* `[bring-up]` **DMA Pin Lifecycle** — pin refcount tied to request completion; a buffer
  with in-flight DMA cannot be freed or reused. Enforced silent-corruption guard.
* `[bring-up]` **DMA Sync Primitives** — `dma_sync_for_device` (flush CPU caches to RAM
  before device reads) and `dma_sync_for_cpu` (invalidate before CPU reads device output).
  No-op fast path on coherent x86-64; real cache ops on AArch64/RISC-V.
* `[AI-critical]` **Fixed / Pre-Registered Buffers** — pin + map + translate SGL once,
  reuse across thousands of I/Os. Kills per-request translation cost on weight-load loops.
* `[AI-critical]` **Direct I/O Cache Bypass** — `IO_DIRECT` flag; DMA straight into the
  destination buffer, bypass any block cache. Never pollute cache with 100 GB of weights.
* `[AI-critical]` **Huge-Page DMA** — back large buffers with 2 MB / 1 GB pages; collapses
  PRP list length and TLB pressure.

### D. Character Devices
* `[bring-up]` **16550 UART (Polling)** — baud/parity/line-control setup with loopback
  presence test; synchronous read/write. First debug output; comes up before disk.
* `[bring-up]` **Console Abstraction** — stdout-over-serial and console-over-VGA with milestone logging
  (continues the `boot` survive/milestone pattern).
* `[bring-up]` **VGA Text Mode** — maps character/attribute cells starting at physical address `0xB8000`. Direct write support, page scrolling, and hardware cursor control (utilizing VGA index register `0x3D4` and data register `0x3D5` to write high/low cursor location bytes).
* `[bring-up]` **PS/2 Keyboard (Polling)** — scancode-to-ASCII translation. Synchronous polling reads from PS/2 data port `0x60` and status port `0x64`.
* `[hardening]` **16550 UART (IRQ)** — RX/TX ring buffers, hardware flow control.

### E. Interrupt Infrastructure
* `[bring-up]` **IDT Configuration** — gates (interrupt/trap/exception), TSS hook.
* `[bring-up]` **IST Stacks (double-fault / NMI)** — dedicated Interrupt Stack Table
  entries so a fault-during-fault lands on a known-good stack instead of triple-faulting
  and resetting the machine. Non-negotiable for a debuggable ring-0.
* `[bring-up]` **ISR Stubs** — full register-frame save/restore on entry.
* `[bring-up]` **8259 PIC Remap** — offsets to vectors 32–47, then mask off once APIC is up.
* `[bring-up]` Local APIC & IO-APIC — LAPIC registers + LAPIC timer; IO-APIC
  redirection entries.
* `[bring-up]` **IO-APIC & Vector Mapping Policy** — When a driver requests interrupt routing for an IRQ pin (e.g., legacy ISA IRQs or PCIe INTx):
  1. The system allocates an available vector within the dynamic range (`0x40`–`0xEF`) using the allocator in `intr/vector.asm`.
  2. The IO-APIC redirection table entry (24-bit/64-bit register pair) for that interrupt input pin is programmed with the allocated vector, target APIC ID, trigger mode (edge vs. level), and polarity.
  3. The local LAPIC on the target CPU core is configured to dispatch the incoming vector to the driver's registered handler.
* `[bring-up]` Spurious / Unhandled Vector Catch-All — spurious at 0xFF; a default
  handler for every unassigned vector so a stray IRQ logs instead of faulting blindly.
* `[bring-up]` **ISR Allocation Constraint** — completion rings use pre-allocated slots
  only. No allocator call inside any ISR (deadlock / re-entrancy). The ISR *writes into*
  a reserved slot; it never allocates.
* `[bring-up]` **Timeout Tick Source** — bind `async/timeout.asm` to the LAPIC timer.
  io keeps its own tick; no dependency on the `time` module (preserves zero-dep).
* `[hardening]` **NMI Handling** — watchdog / hardware-error NMI path on its IST stack.
* `[hardening]` **MSI / MSI-X** — message-signaled interrupts (mandatory for modern
  NVMe/AHCI multi-queue). virtio-blk bring-up uses legacy INTx first.
* `[SMP]` **IPI (Inter-Processor Interrupts)** — cross-core wakeup (completion on core N,
  waiter parked on core M) and reschedule.
* `[SMP]` **TLB Shootdown** — broadcast page-invalidation over IPI for mappings mutated
  in `dma/map.asm` and huge-page paths.
* `[SMP]` **Interrupt Balancing & Affinity** — distribute completion IRQs across cores;
  pin a given NVMe CQ to a specific core. Prevents Core-0 interrupt storms.

### F. PCI / PCIe Enumeration
* `[bring-up]` **Config Access** — legacy `0xCF8`/`0xCFC` and MMIO ECAM (base from MCFG).
* `[bring-up]` **Bus Walk & BAR Mapping** — enumerate buses 0–255; size and map BARs,
  including 64-bit BARs (consecutive register pair).
* `[bring-up]` **Capability List Parse** — MSI, MSI-X, PCIe caps in standard config space.
* `[P2P]` **Extended Config + ACS/AER** — capabilities at offset > 0x100 via ECAM.
  ACS routing enables direct peer-to-peer (bypassing the root complex bounce); AER for
  error reporting. GPUDirect silently depends on ACS being enumerated and set.
* `[hardening]` **PCIe Hotplug** — add/remove events; mark dependent FDs stale, reclaim.
* `[optional]` **SR-IOV** — virtual functions for passthrough NVMe/GPU.

### G. Block Device Layer
* `[bring-up]` **Uniform Block Abstraction** — read / write / flush / trim.
* `[bring-up]` **LBA Format Query** — detect 512 B vs 4 Kn logical sector at probe;
  abstract sector size. Hardcoding 512 corrupts a 4 Kn drive.
* `[bring-up]` **GPT Partitions** — parse GUID partition table in `block/gpt.asm`;
  expose partitions as sub-block-devices. This is the io↔ufs boundary: io hands ufs
  block devices, ufs does not do raw LBA math.
* `[bring-up]` **ATA-PIO Driver** — simplest polling driver; first-ever sector read sanity.
* `[bring-up]` **Virtio-Blk Driver** — legacy INTx for bring-up; feature negotiation
  (`VIRTIO_F_VERSION_1`, …); formal status handshake
  `ACKNOWLEDGE → DRIVER → FEATURES_OK → DRIVER_OK`. First *real* async device.
* `[bring-up]` **Virtqueue Ordering Barriers** — store fences on the MMIO doorbell path:
  `write descriptors → sfence → bump avail idx → sfence → notify`. These are real CPU
  store fences on the WC/MMIO notify path, **not** compiler barriers. Missing/reversed
  fences work under QEMU-TCG and corrupt under KVM/real hardware.
* `[bring-up]` **Barrier / Flush / FUA** — durability primitives; write-cache control.
* `[AI-critical]` **Multi-Queue NVMe** — one SQ/CQ pair per core, deep queues (thousands
  of entries), per-core doorbells; saturates Gen4/Gen5.
* `[AI-critical]` **NVMe Namespace Enumeration** — each namespace = one block device.
* `[AI-critical]` **Doorbell Stride Handling** — honor `CAP.DSTRD`; per-queue doorbell
  addressing. Getting this wrong silently rings the wrong queue's doorbell.
* `[AI-relevant]` **PRP & SGL Modes** — translate `iovec` into NVMe PRP lists (Page 1 /
  Page 2 / PRP-list-pointer) with automatic page-crossing entries; select SGL mode where
  the controller supports it for large fragmented transfers.
* `[AI-relevant]` **Request Merging + Readahead** — coalesce contiguous requests into
  fewer larger commands; prefetch ahead of a detected sequential stream (the weight /
  dataset access pattern).
* `[AI-relevant]` **Queue Arbitration (WRR)** — Weighted Round Robin so a weight-streaming
  queue can outrank background I/O.
* `[hardening]` **AHCI / SATA Driver** — full SATA path after virtio is proven.
* `[hardening]` **SMART / Health Readout** — device health, media wear.
* `[hardening]` **NVMe Dataset Management (Trim) + Write Zeroes** — SSD longevity, fast
  buffer clearing.
* `[hardening]` **NVMe AER + Abort + Per-Queue Reset** — async event requests; abort a
  hung command; reset a single queue without nuking the controller. Long training runs
  must survive a single stuck command.
* `[hardening]` **Controller Fatal Status (CSTS.CFS) Detection** — detect and recover a
  wedged controller.
* `[optional]` **Zoned Namespaces (ZNS)** — sequential-write zones for large append-only
  dataset stores.
* `[optional]` **NVMe CMB / PMR** — Controller Memory Buffer: place SQ/CQ or data buffers
  in device BAR space. Key enabler for P2P (a GPU can reach an SQ living in CMB).
* `[optional]` **Data Integrity (T10 PI)** — end-to-end protection information on the
  checkpoint durability path; guards against silent checkpoint corruption.

### H. Async Completion Model & Scheduler Hooks
* `[bring-up]` **SPSC Rings** — lockless Single-Producer/Single-Consumer submission and
  completion rings, per core. Design lockless from day one even on single core; retrofit
  is a rewrite.
* `[bring-up]` **Request State Machine** — `INIT → SUBMITTED → IN_FLIGHT → COMPLETE /
  ERROR / CANCELLED / TIMEOUT`.
* `[bring-up]` **Completion Block** — a task blocks on a completion ID via a wait queue,
  yielding to the scheduler; falls back to polling if no scheduler yet (stubbable hook).
* `[bring-up]` **Timeout Wheel** — LAPIC-timer-driven; expires stuck requests.
* `[bring-up]` **Doorbell Batching / Plugging** — submit N commands, ring the doorbell
  once. Major win under deep-queue weight loads.
* `[hardening]` **Retry with Backoff** — transient-error retry policy.
* `[hardening]` **Cancellation** — cancel an in-flight or queued request.
* `[SMP]` **MPSC Shared Queues** — for shared submission points, `LOCK CMPXCHG` / `XADD`
  lockless MPSC; no kernel spinlocks on the hot path.
* `[AI-relevant]` **Adaptive Poll/IRQ (NAPI-style)** — interrupt-driven at idle, flip to
  polling under load, flip back on drain. Ties `poll.asm` + `coalesce.asm` together.
* `[AI-relevant]` **Credit / Backpressure Flow Control** — queue-depth credits; callers
  block or get `IO_ERR_QFULL` instead of overrunning a device queue.

### I. AI / GPU-Centric Data Path
* `[AI-critical]` **P2P GPUDirect DMA** — NVMe BAR → GPU BAR direct PCIe transfers,
  bypassing system RAM entirely. Eliminates the disk→RAM→VRAM double copy that dominates
  model-load time. Depends on: PCIe P2P routing, ACS on the intervening bridges,
  BAR-to-BAR DMA in `dma/map.asm`, and PAT WC on the GPU aperture.
* `[P2P]` **IOMMU + Interrupt Remapping** — VT-d / AMD-Vi / SMMU domains for isolation;
  interrupt remapping required when MSI is used behind an IOMMU.
* `[optional]` **Memory-Mapped Block Regions** — map a device region for direct
  weight access (boundary with ufs; io provides the mapping primitive).

### J. Reliability, Health & Observability
* `[hardening]` **Device State Machine** — `PROBE → ONLINE → DEGRADED → RESET → OFFLINE`.
* `[hardening]` **Controller / Device Reset** — graceful and forced.
* `[hardening]` **Error Recovery** — distinguishes queue-level from controller-level.
* `[hardening]` **Watchdog** — hang detection on outstanding requests.
* `[hardening]` **Fault Injection** — test-build-only error simulation.
* `[hardening]` **Per-Device Counters** — IOPS, bytes, error rates → `umetric` hooks.
* `[hardening]` **Latency Histograms** — `rdtscp` / `lfence;rdtsc`, invariant-TSC checked
  via CPUID. io uses the cycle counter directly, keeping zero-dep on `time`.
* `[hardening]` **Trace Spans** — submit/complete hooks → `utrace`; per-request correlation ID.
* `[optional]` **Power Management** — NVMe APST power states, PCIe ASPM link power.

### K. Platform Shims (Hosted Builds)
* `[hardening]` **Polymorphic `fd_t` vtable** — wrap POSIX fds and Win32 `HANDLE`s behind
  the same `fd_read` / `fd_write` function-pointer table so the C/Rust bindings are
  identical across native and hosted.
* `[hardening]` **POSIX shim** — Linux/macOS `pread`/`pwrite`/`open`/`close`.
* `[hardening]` **Win32 shim** — overlapped `ReadFile`/`WriteFile`.
* `[bring-up]` **Dispatch Selector** — native-vs-hosted routing chosen at build/init.

---

## 2. Directory Structure

```
lib/io/
├── Makefile
├── io.asm                          # Top-level include entry
├── io.inc                          # Shared struct offsets, constants, vector map (see §5)
│
├── include/
│   ├── io.h                        # Public C ABI
│   ├── io_block.h
│   ├── io_char.h
│   ├── io_async.h
│   ├── io_pci.h
│   ├── io_error.h
│   └── rust/
│       ├── lib.rs
│       └── ffi.rs
│
├── const/
│   ├── uart.asm                    # 16550 registers, line-control bits
│   ├── pci.asm                     # config offsets, class codes, cap IDs
│   ├── apic.asm                    # LAPIC / IO-APIC register map
│   ├── pic.asm                     # 8259 ports, ICW/OCW
│   ├── msi.asm                     # MSI / MSI-X cap + table layout
│   ├── ahci.asm                    # HBA/port offsets, FIS types
│   ├── nvme.asm                    # controller/queue regs, opcodes, CAP fields
│   ├── virtio.asm                  # virtqueue layout, feature bits, status bits
│   ├── ata.asm                     # ATA command set, status bits
│   ├── idt.asm                     # gate types, IST layout, vector map
│   ├── acpi.asm                    # ACPI table signatures, header layouts
│   └── dma.asm                     # alignment / addressing constraints
│
├── error/
│   ├── codes.asm                   # error bands per subsystem (§3)
│   └── strerror.asm                # code → message
│
├── macro/
│   ├── func.asm                    # IO_FUNC / IO_ENDFUNC
│   ├── guard.asm                   # guard_null / guard_bar / guard_handle
│   ├── mmio.asm                    # barrier-safe mmio_read/write 8/16/32/64
│   └── rso.asm                     # register-ownership annotations
│
├── boot/
│   └── handoff.asm                 # ingest boot boot_params (mem map, RSDP, fb, boot dev)
│
├── acpi/
│   ├── acpi.asm                    # scanner entry
│   ├── madt.asm                    # APIC / IO-APIC topology
│   ├── mcfg.asm                    # PCIe ECAM base
│   └── fadt.asm                    # reset register, power
│
├── core/
│   ├── fd.asm                      # descriptor table, FD_OPEN/FD_STALE
│   ├── handle.asm                  # refcount, generation counters, lookup
│   ├── percpu.asm                  # per-CPU base register (GS_BASE / TPIDR_EL1)
│   ├── buffer.asm                  # arena buffers, pin/unpin lifecycle
│   ├── fixed_buf.asm               # pre-registered DMA buffers
│   ├── iovec.asm                   # scatter-gather build/walk, page-crossing split
│   ├── align.asm                   # sector / page / cache-line alignment
│   └── bounce.asm                  # sub-4GB bounce buffers
│
├── char/
│   ├── serial.asm                  # 16550 polling + loopback presence test
│   ├── serial_irq.asm              # IRQ-driven RX/TX rings, flow control
│   ├── console.asm                 # console-over-serial, milestone logging
│   └── ps2kbd.asm                  # PS/2 keyboard
│
├── intr/
│   ├── idt.asm                     # IDT build, gate install, IST setup
│   ├── isr.asm                     # ISR stubs, register frame save/restore
│   ├── exception.asm               # fault/trap handlers (incl. double-fault, NMI on IST)
│   ├── spurious.asm                # spurious + unhandled-vector catch-all
│   ├── pic.asm                     # 8259 remap + mask
│   ├── lapic.asm                   # LAPIC + LAPIC timer (tick source)
│   ├── ioapic.asm                  # IO-APIC redirection
│   ├── msi.asm                     # MSI / MSI-X setup
│   ├── vector.asm                  # vector allocator
│   ├── ipi.asm                     # inter-processor interrupts
│   ├── affinity.asm                # IRQ affinity / balancing
│   └── coalesce.asm                # coalescing thresholds, throttling
│
├── pci/
│   ├── config.asm                  # legacy port + ECAM config access
│   ├── enum.asm                    # bus/dev/func walk
│   ├── bar.asm                     # BAR size + map, 64-bit BAR pair
│   ├── caps.asm                    # std + extended (ACS/AER) capability walk
│   └── match.asm                   # vendor/device match table
│
├── dma/
│   ├── alloc.asm                   # contiguous / huge-page DMA alloc
│   ├── map.asm                     # virt↔phys, BAR-to-BAR mapping
│   ├── sg.asm                      # scatter-gather DMA, PRP/SGL build
│   ├── sync.asm                    # dma_sync_for_cpu / dma_sync_for_device
│   ├── barrier.asm                 # coherency fences
│   ├── p2p.asm                     # peer-to-peer BAR transfers
│   ├── gpudirect.asm               # NVMe→GPU direct path
│   └── iommu.asm                   # VT-d / AMD-Vi / SMMU + interrupt remap
│
├── block/
│   ├── bdev.asm                    # uniform block interface, IO_DIRECT
│   ├── gpt.asm                     # GPT partition parse → sub-devices
│   ├── queue.asm                   # request queue, depth, backpressure/credits
│   ├── merge.asm                   # request merging
│   ├── readahead.asm               # sequential prefetch
│   ├── flush.asm                   # barrier / flush / FUA
│   ├── smart.asm                   # SMART / health
│   ├── ata_pio.asm                 # bring-up driver
│   ├── virtio_blk.asm              # virtio-blk (INTx bring-up → MSI-X)
│   ├── ahci.asm                    # SATA
│   └── nvme.asm                    # multi-queue NVMe, PRP/SGL, namespaces, WRR, CMB
│
├── async/
│   ├── submit.asm                  # SPSC submission ring
│   ├── complete.asm                # SPSC completion ring (ISR writes pre-alloc slots)
│   ├── mpsc.asm                    # MPSC shared-queue path
│   ├── request.asm                 # request struct + state machine
│   ├── timeout.asm                 # LAPIC-driven timeout wheel
│   ├── retry.asm                   # retry + backoff
│   ├── cancel.asm                  # cancellation
│   ├── batch.asm                   # doorbell batching / plugging
│   └── napi.asm                    # adaptive poll/IRQ switch
│
├── sched/
│   ├── wait.asm                    # block-on-completion-ID
│   ├── wake.asm                    # wakeup (cross-core via IPI)
│   ├── waitq.asm                   # wait queues
│   └── poll.asm                    # busy-poll fast path
│
├── health/
│   ├── state.asm                   # device state machine
│   ├── reset.asm                   # controller / queue reset
│   ├── recover.asm                 # queue-level vs controller-level recovery
│   ├── hotplug.asm                 # PCIe add/remove → stale FDs
│   ├── watchdog.asm                # hang detection
│   └── inject.asm                  # fault injection (test builds)
│
├── stat/
│   ├── counters.asm                # IOPS / bytes / errors → umetric
│   ├── latency.asm                 # rdtscp histograms, invariant-TSC check
│   └── trace.asm                   # utrace spans, correlation IDs
│
├── arch/
│   ├── x86_64/
│   │   ├── portio.asm              # in / out
│   │   ├── mmio.asm                # MMIO accessors
│   │   ├── pat.asm                 # PAT / MTRR memory-type control
│   │   ├── barrier.asm             # mfence / lfence / sfence
│   │   └── cache.asm               # clflush / clflushopt / wbinvd
│   ├── aarch64/
│   │   ├── mmio.asm
│   │   ├── barrier.asm             # dmb / dsb / isb
│   │   ├── cache.asm               # dc / ic ops
│   │   └── gic.asm                 # GIC (replaces APIC)
│   └── riscv/
│       ├── mmio.asm
│       ├── barrier.asm             # fence
│       └── plic.asm                # PLIC (replaces APIC)
│
├── plat/
│   ├── dispatch.asm                # native vs hosted selector
│   ├── native.asm                  # Tattva ring-0 (primary)
│   ├── posix.asm                   # Linux/macOS shim
│   └── win32.asm                   # Windows overlapped shim
│
├── test/
│   ├── unit/                       # per-file unit tests
│   ├── qemu/                       # QEMU integration harness
│   └── fault/                      # fault-injection scenarios
│
└── docs/
    ├── io_spec.md                  # this document
    ├── build_order.md              # §6
    └── error_ranges.md             # §3
```

---

## 3. Error Convention & Bands

### 3.1 The pointer/error collision problem

The previous draft placed error codes at `0xFFFF_FFFF_F000_0000`. That is a **canonical
higher-half address** and overlaps the region where the kernel maps code, MMIO windows,
and heap. Any function that can return *either a pointer or an error* (`buffer_alloc`,
`fixed_buf_register`, `io_handle_alloc`) becomes ambiguous — a valid pointer is
indistinguishable from an error code. This must not ship.

### 3.2 Reserved error band (top-page rule)

io reserves the **top page of the virtual address space** — `[-4095, -1]`, i.e.
`0xFFFF_FFFF_FFFF_F001 … 0xFFFF_FFFF_FFFF_FFFF` — as the error band. This page is never
mapped by Tattva. Any return value in this band is an error, never a pointer.

```
IS_ERR(x)   ≡  (uint64)(x) >= (uint64)-4095
PTR_ERR(x)  ≡  (int64)(x)                     ; the negative errno
ERR_PTR(e)  ≡  (uint64)(int64)(e)             ; e in [-4095, -1]
```

* **Status-returning functions**: `RAX = 0` on success (or a small positive value such as
  bytes-transferred / handle-id), or a negative code in the band on error.
* **Pointer-returning functions**: `RAX` = valid pointer, or an `ERR_PTR` value in the
  band. Callers gate with `IS_ERR` before dereferencing.

### 3.3 Subsystem sub-bands

The 4095-code band is partitioned so every code names its subsystem. Code =
`-(subsystem_base + local)`.

| Subsystem | Base | Range (negative) | Examples |
| :-- | :-- | :-- | :-- |
| Foundation / Core | `0x000` | `-0x001 … -0x0FF` | null ptr, bad descriptor, bad arg |
| Descriptor / Handle | `0x100` | `-0x101 … -0x1FF` | `IO_ERR_STALE`, refcount underflow, bad generation |
| DMA & Buffers | `0x200` | `-0x201 … -0x2FF` | out-of-DMA-mem, misalignment, page-cross, pinned |
| Interrupts | `0x300` | `-0x301 … -0x3FF` | vector exhausted, bad affinity, IST fault |
| PCI / PCIe | `0x400` | `-0x401 … -0x4FF` | bus fault, BAR conflict, ECAM fault, no ACS |
| Block Device | `0x500` | `-0x501 … -0x5FF` | media error, bad LBA, `IO_ERR_QFULL`, reset timeout |
| Async | `0x600` | `-0x601 … -0x6FF` | ring full, cancelled, timeout expired |
| Platform / Shims | `0x700` | `-0x701 … -0x7FF` | POSIX mapping, Win32 overlapped failure |
| *(reserved)* | `0x800`–`0xFFF` | | future subsystems |

`error/codes.asm` defines the named constants; `error/strerror.asm` maps each to a string.

### 3.4 Phase 1 Core Error Codes

To ensure consistent error reporting across all drivers and subsystems, the following core negative error codes are defined for Phase 1:

| Named Constant | Numeric Value | Subsystem Base | Meaning |
| :--- | :--- | :--- | :--- |
| `IO_ERR_NULL` | `-0x001` | Foundation (`0x000`) | Null pointer encountered where non-null expected |
| `IO_ERR_BADARG` | `-0x002` | Foundation (`0x000`) | Invalid function argument (e.g. out of range alignment) |
| `IO_ERR_NO_DEVICE` | `-0x003` | Foundation (`0x000`) | Device not detected or present |
| `IO_ERR_NOMEM` | `-0x004` | Foundation (`0x000`) | General out of memory |
| `IO_ERR_BADFD` | `-0x101` | Descriptor (`0x100`) | Invalid or closed file descriptor |
| `IO_ERR_STALE` | `-0x102` | Descriptor (`0x100`) | Use-after-free detected via stale handle/generation |
| `IO_ERR_DMA_NOMEM` | `-0x201` | DMA (`0x200`) | Contiguous DMA memory exhausted |
| `IO_ERR_PAGE_CROSS` | `-0x202` | DMA (`0x200`) | Scatter-gather split limit exceeded |
| `IO_ERR_VEC_LIMIT` | `-0x301` | Interrupts (`0x300`) | Dynamic interrupt vector allocation limit reached |
| `IO_ERR_PCI_BAR` | `-0x401` | PCI (`0x400`) | PCI BAR configuration or mapping conflict |
| `IO_ERR_QFULL` | `-0x501` | Block (`0x500`) | Submission queue or request block ring full |
| `IO_ERR_TIMEOUT` | `-0x601` | Async (`0x600`) | Controller command timeout expired |
| `IO_ERR_CANCEL` | `-0x602` | Async (`0x600`) | I/O operation cancelled |

---

## 4. Calling & Register Convention

* **ABI**: System V AMD64. Args in `RDI, RSI, RDX, RCX, R8, R9`; return in `RAX`
  (`RAX:RDX` for 128-bit). Native ring-0 code follows the same ABI for C/Rust interop.
* **Callee-saved**: `RBX, RBP, R12–R15` preserved across every `IO_FUNC`.
* **Every `IO_FUNC`**: `guard_null` on every pointer argument at entry before use.
  * `guard_null ptr` — assert `ptr != NULL`, else return `IO_ERR_NULL` (Core band).
  * `guard_bar ptr, min, max` — assert `min <= ptr <= max` (e.g., MMIO window bounds), else return `IO_ERR_BADARG` (Core band).
  * `guard_handle handle` — decode the handle, check its generation number, verify its state is `FD_OPEN`, else return `IO_ERR_STALE` or `IO_ERR_BADFD`.
* **Error return**: per §3 — status functions return 0/positive or a band code; pointer
  functions return a pointer or `ERR_PTR`.
* **ISR context**: ISRs save the full frame (`isr.asm`), touch only pre-allocated slots,
  never call an allocator, never take a lock that non-ISR code holds with interrupts
  enabled. Completion is a slot write + ring index bump, nothing more.
* **RSO annotations**: each routine documents register ownership/lifetime in the header
  comment, consistent with the utasm RSO model.

---

## 5. Shared Structures (`io.inc`)

These offsets are authoritative. Any file touching these structs includes `io.inc`;
no file hardcodes an offset. Sizes are the initial contract — extend at the tail only,
never reorder.

```asm
; ---- fd_t : descriptor table entry -----------------------------------------
struc fd_t
    .type        resq 1      ; FD_TYPE_{FILE,BLOCK,CHAR,EVENT,PIPE}
    .state       resq 1      ; FD_OPEN | FD_STALE
    .refcount    resq 1      ; active references
    .generation  resq 1      ; bumped on free; detects use-after-free
    .device      resq 1      ; -> device_t (fops live there; native path)
    .vtable      resq 1      ; -> posix/win32 fops (hosted shims only; 0 on native)
    .priv        resq 1      ; driver-private pointer
endstruc

; ---- iovec_t : one scatter-gather element ----------------------------------
struc iovec_t
    .base        resq 1      ; virtual base address
    .phys        resq 1      ; physical base (filled by dma/map)
    .len         resq 1      ; byte length
    .flags       resq 1      ; page-crossing split marker, etc.
endstruc

; ---- io_request_t : one async I/O request ----------------------------------
struc io_request_t
    .opcode      resq 1      ; IO_OP_{READ,WRITE,FLUSH,TRIM,WRITE_ZEROES}
    .flags       resq 1      ; IO_DIRECT | IO_FUA | IO_FIXEDBUF | ...
    .device      resq 1      ; -> block device
    .lba         resq 1      ; starting logical block
    .nblocks     resq 1      ; block count
    .iov         resq 1      ; -> iovec_t array
    .iov_cnt     resq 1      ; iovec count
    .id          resq 1      ; completion / correlation ID
    .state       resq 1      ; INIT..COMPLETE/ERROR/CANCELLED/TIMEOUT
    .status      resq 1      ; final result code (§3 band on error)
    .pin_token   resq 1      ; DMA pin handle; released on completion
    .submit_tsc  resq 1      ; rdtsc at submit (latency histogram)
    .complete_tsc resq 1     ; rdtsc at completion (added for latency mapping)
    .result      resq 1      ; transferred count / result value
    .waiter      resq 1      ; -> waitq entry, or 0
endstruc

; ---- io_completion_t : one completion-ring slot (pre-allocated) ------------
struc io_completion_t
    .id          resq 1      ; matches io_request_t.id
    .status      resq 1      ; result code
    .result      resq 1      ; bytes transferred / device-specific
    .complete_tsc resq 1     ; rdtsc at completion
endstruc

; ---- virtq_desc : virtio split-virtqueue descriptor (16 bytes) -------------
struc virtq_desc
    .addr        resq 1      ; guest-physical buffer address
    .len         resd 1      ; length
    .flags       resw 1      ; NEXT | WRITE | INDIRECT
    .next        resw 1      ; index of next descriptor when NEXT set
endstruc
; avail ring and used ring are page-aligned; layouts in const/virtio.asm.

; ---- boot_handoff_t : consumed from boot (mirrors boot_params) ------------
struc boot_handoff_t
    .magic       resq 1
    .mem_map     resq 1      ; -> memory map array
    .mem_map_cnt resq 1
    .rsdp        resq 1      ; ACPI RSDP physical address
    .framebuffer resq 1      ; -> framebuffer info
    .boot_device resq 1      ; boot block device handle
    .pml4        resq 1      ; initial page-table root
endstruc
; Note: boot_handoff_t is exactly 56 bytes.
;
; Lifetime & Ownership Contract: io_init receives bh (a pointer to boot_handoff_t)
; residing in temporary bootloader memory. During handoff_ingest, lib/io must deep-copy
; the mem_map array and ACPI rsdp structure into lib/mem permanent kernel arenas.
; After io_init returns, the bootloader's memory pages may be reclaimed; lib/io MUST NOT
; retain any references to the original bh or its initial memory buffer pointers.

; ---- mem_map_entry_t : memory map region entry (24 bytes) ------------------
struc mem_map_entry_t
    .base        resq 1      ; physical base address
    .len         resq 1      ; byte length of the region
    .type        resd 1      ; region type: 1=available RAM, 2=reserved, 3=ACPI reclaim, 4=MMIO
    .pad         resd 1      ; 64-bit alignment pad
endstruc

; ---- spsc_ring_t : single-producer single-consumer ring buffer -------------
; CANONICAL DEFINITION — the ONLY definition of this struct (§13.1.2 references it).
; Producer and consumer indices sit on SEPARATE 64-byte cache lines so the two roles
; never false-share. A single 64-byte line CANNOT hold both indices false-sharing-free;
; that earlier "64-byte" layout is intentionally replaced by this 192-byte / 3-line form.
struc spsc_ring_t
    ; --- line 0 (offset 0): read-only shared header ---
    .mask        resq 1      ; capacity-1 (capacity must be a power of 2)
    .buffer      resq 1      ; -> array of entries (io_request_t * or io_completion_t *)
    .entry_size  resq 1      ; bytes per entry (index scaling)
    .capacity    resq 1      ; total slots (= mask + 1)
    .resv0       resq 4      ; pad line 0 to 64 bytes
    ; --- line 1 (offset 64): producer-owned ---
    .prod_idx    resq 1      ; producer index (owned/written by submitter)
    .resv1       resq 7      ; pad to 64 bytes (no false sharing with consumer)
    ; --- line 2 (offset 128): consumer/ISR-owned ---
    .cons_idx    resq 1      ; consumer index (owned/written by ISR/completion)
    .resv2       resq 7      ; pad to 64 bytes
endstruc                     ; total = 192 (three cache lines)
; Ring Capacity Policy: Ring capacity is configured at initialization and must be a
; power of two to allow fast bitwise masking (idx & mask) instead of expensive modulo
; division. For device rings (such as NVMe submission/completion queues), the SPSC ring
; buffer depth must match or exceed the hardware queue depth (which ranges up to
; thousands of entries).

; ---- percpu_t : per-CPU storage block ---------------------------------------
struc percpu_t
    .self        resq 1      ; self pointer for verification/validation
    .cpu_id      resd 1      ; logical CPU ID / APIC ID
    .lapic_id    resd 1      ; hardware Local APIC ID
    .current_req resq 1      ; pointer to io_request_t currently being processed (debug)
    .submit_ring resq 1      ; pointer to SPSC submission ring for this core
    .complete_ring resq 1    ; pointer to SPSC completion ring for this core
    .nvme_sq     resq 1      ; pointer to NVMe submission queue (AI path)
    .nvme_cq     resq 1      ; pointer to NVMe completion queue
    .irq_stack   resq 1      ; bottom of dedicated IST/IRQ stack for this core
endstruc

; ---- driver_binding_t : driver registration entry --------------------------
struc driver_binding_t
    .vendor_id   resw 1      ; PCI vendor ID
    .device_id   resw 1      ; PCI device ID
    .class_mask  resd 1      ; PCI class mask
    .class_match resd 1      ; PCI class code to match
    .probe_fn    resq 1      ; function pointer: probe(device_t *dev, pci_dev_t *pci) -> rax (status)
endstruc

; ---- device_t : a probed device + its operation table ----------------------
; fd_t.device points here. Async requests route via  call [device_t.submit].
struc device_t
    .name        resb 32     ; human-readable id
    .type        resq 1      ; DEV_TYPE_{BLOCK,CHAR,EVENT}  (NET reserved for unet)
    .state       resq 1      ; PROBE|ONLINE|DEGRADED|RESET|OFFLINE (health/state.asm)
    ; --- operation table ---
    .open        resq 1
    .close       resq 1
    .read        resq 1      ; synchronous fallback / char-device read
    .write       resq 1      ; synchronous fallback / char-device write
    .submit      resq 1      ; ASYNC: submit(device_t *dev, io_request_t *req)
    .flush       resq 1      ; barrier / flush / FUA entry
    .ioctl       resq 1      ; device-specific control (absorbs seek etc.)
    ; --- block geometry (queried at probe; invariant #3) ---
    .sector_size resq 1      ; 512 or 4096, from LBA-format query
    .capacity    resq 1      ; total addressable blocks
    .parent      resq 1      ; -> parent device_t (0 for physical/root devices)
    .lba_offset  resq 1      ; partition start sector (0 for physical devices)
    .lba_count   resq 1      ; partition size in sectors (equal to capacity for physical devices)
    ; --- async plumbing ---
    .queue       resq 1      ; -> per-device request queue / NVMe SQ-CQ array
    .private     resq 1      ; driver-private state
endstruc
; GPT partition device_t extension: A GPT partition is exposed as a separate device_t
; instance. The block layer translates partition-relative offsets to disk-absolute offsets
; before forwarding requests (applying .lba_offset and checking bounds against .lba_count).

; ---- idt_gate_t : x86-64 IDT Gate Descriptor (16 bytes) --------------------
struc idt_gate_t
    .offset_low  resw 1      ; offset bits 0-15
    .selector    resw 1      ; code segment selector in GDT (e.g. SEL_CODE64)
    .ist         resb 1      ; bits 0-2: IST stack index, bits 3-7: zero
    .type_attr   resb 1      ; type and attributes (e.g. gate type, privilege level, present)
    .offset_mid  resw 1      ; offset bits 16-31
    .offset_high resd 1      ; offset bits 32-63
    .reserved    resd 1      ; reserved, must be zero
endstruc

; ---- tss_descriptor_t : GDT TSS System Segment Descriptor (16 bytes) -------
struc tss_descriptor_t
    .limit_low   resw 1      ; limit bits 0-15
    .base_low    resw 1      ; base bits 0-15
    .base_mid1   resb 1      ; base bits 16-23
    .type_attr   resb 1      ; type and flags (present, type=0x9/0xB for TSS)
    .limit_high  resb 1      ; limit bits 16-19 and flags
    .base_mid2   resb 1      ; base bits 24-31
    .base_high   resd 1      ; base bits 32-63
    .reserved    resd 1      ; reserved, must be zero
endstruc

; ---- acpi_header_t : ACPI Table Common Header (36 bytes) -------------------
struc acpi_header_t
    .signature   resb 4      ; table identifier (e.g., "APIC", "MCFG")
    .length      resd 1      ; table length in bytes
    .revision    resb 1      ; revision of structure
    .checksum    resb 1      ; checksum over entire table
    .oem_id      resb 6      ; OEM ID string
    .oem_table_id resb 8     ; OEM Table ID string
    .oem_revision resd 1     ; OEM revision number
    .creator_id  resd 1      ; ASL compiler creator ID
    .creator_rev resd 1      ; ASL compiler creator revision
endstruc

; ---- virtq_avail_t : virtio available ring ---------------------------------
struc virtq_avail_t
    .flags       resw 1      ; available ring flags (e.g. NO_INTERRUPT)
    .idx         resw 1      ; index where driver will write next descriptor index
    ; .ring field starts here (array of 16-bit descriptor indices)
    ; .used_event is at the end: used_event = .ring[queue_size]
endstruc

; ---- virtq_used_elem_t : virtio used ring element (8 bytes) ----------------
struc virtq_used_elem_t
    .id          resd 1      ; index of start of used descriptor chain
    .len         resd 1      ; total length of the written descriptor chain
endstruc

; ---- virtq_used_t : virtio used ring ---------------------------------------
struc virtq_used_t
    .flags       resw 1      ; used ring flags (e.g. NO_PUBLISH)
    .idx         resw 1      ; index where device will write next used element
    ; .ring field starts here (array of virtq_used_elem_t elements)
    ; .avail_event is at the end: avail_event = .ring[queue_size]
endstruc

; ---- interrupt_frame_t : ISR Stack Save Frame (120 bytes) ------------------
struc interrupt_frame_t
    ; Pushed manually by isr_common_stub (GP registers in reverse push order)
    .r11         resq 1      ; general purpose register 11
    .r10         resq 1      ; general purpose register 10
    .r9          resq 1      ; general purpose register 9
    .r8          resq 1      ; general purpose register 8
    .rdi         resq 1      ; general purpose register DI
    .rsi         resq 1      ; general purpose register SI
    .rdx         resq 1      ; general purpose register DX
    .rcx         resq 1      ; general purpose register CX
    .rax         resq 1      ; general purpose register AX
    ; Pushed by hardware exception, or manually by stub if no error code
    .error_code  resq 1      ; error code pushed by CPU or 0 dummy
    .rip         resq 1      ; return instruction pointer
    .cs          resq 1      ; return code segment selector
    .rflags      resq 1      ; return flags register
    .rsp         resq 1      ; return stack pointer
    .ss          resq 1      ; return stack segment selector
endstruc

; ---- vga_cell_t : VGA Text Mode Buffer Cell (2 bytes) ----------------------
struc vga_cell_t
    .char        resb 1      ; ASCII character code
    .attr        resb 1      ; attribute byte (foreground, background, blink)
endstruc

; ---- pci_header_t : standard PCI Configuration Header Type 0 (64 bytes) -----
struc pci_header_t
    .vendor_id      resw 1      ; 0x00
    .device_id      resw 1      ; 0x02
    .command        resw 1      ; 0x04
    .status         resw 1      ; 0x06
    .revision_id    resb 1      ; 0x08
    .class_code     resb 3      ; 0x09 (prog_if, subclass, class)
    .cache_line_sz  resb 1      ; 0x0C
    .latency_timer  resb 1      ; 0x0D
    .header_type    resb 1      ; 0x0E
    .bist           resb 1      ; 0x0F
    .bar            resd 6      ; 0x10 Base Address Registers (BAR0-5)
    .cardbus_cis    resd 1      ; 0x28
    .sub_vendor_id  resw 1      ; 0x2C
    .sub_system_id  resw 1      ; 0x2E
    .rom_base       resd 1      ; 0x30
    .cap_pointer    resb 1      ; 0x34 Capabilities Pointer
    .reserved       resb 7      ; 0x35
    .interrupt_line resb 1      ; 0x3C
    .interrupt_pin  resb 1      ; 0x3D
    .min_gnt        resb 1      ; 0x3E
    .max_lat        resb 1      ; 0x3F
endstruc

; ---- msix_table_entry_t : MSI-X Table Entry Layout (16 bytes) ---------------
struc msix_table_entry_t
    .msg_addr_low   resd 1      ; 0x00 Lower 32-bits of destination APIC address
    .msg_addr_high  resd 1      ; 0x04 Upper 32-bits
    .msg_data       resd 1      ; 0x08 Interrupt vector data payload
    .vector_control resd 1      ; 0x0C Mask bit (bit 0)
endstruc

; ---- nvme_regs_t : NVMe Controller Configuration Registers (64 bytes) -------
struc nvme_regs_t
    .cap            resq 1      ; 0x00 Controller Capabilities
    .vs             resd 1      ; 0x08 Version
    .intms          resd 1      ; 0x0C Interrupt Mask Set
    .intmc          resd 1      ; 0x10 Interrupt Mask Clear
    .cc             resd 1      ; 0x14 Controller Configuration
    .reserved0      resd 1      ; 0x18
    .csts           resd 1      ; 0x1C Controller Status
    .nssr           resd 1      ; 0x20 NVM Subsystem Reset (optional)
    .aqa            resd 1      ; 0x24 Admin Queue Attributes
    .asq            resq 1      ; 0x28 Admin Submission Queue Base Address
    .acq            resq 1      ; 0x30 Admin Completion Queue Base Address
    .cmbloc         resd 1      ; 0x38 Controller Memory Buffer Location
    .cmbsz          resd 1      ; 0x3C Controller Memory Buffer Size
endstruc

; ---- msi_cap_t : Message Signaled Interrupts Capability (8 bytes) -----------
struc msi_cap_t
    .cap_id         resb 1      ; 0x05 for MSI
    .next_ptr       resb 1      ; Offset to next capability
    .msg_control    resw 1      ; Message control register
    .msg_addr_low   resd 1      ; Lower 32-bits of target message address
endstruc

; ---- msix_cap_t : Message Signaled Interrupts Extended Capability (12 bytes) -
struc msix_cap_t
    .cap_id         resb 1      ; 0x11 for MSI-X
    .next_ptr       resb 1      ; Offset to next capability
    .msg_control    resw 1      ; Message control register
    .table_offset   resd 1      ; Table BIR (bits 0-2) + offset (bits 3-31)
    .pba_offset     resd 1      ; Pending Bit Array BIR (bits 0-2) + offset
endstruc

; ---- virtio_blk_req_t : Virtio-Blk Request Header (16 bytes) ----------------
struc virtio_blk_req_t
    .type           resd 1      ; 0=read (IN), 1=write (OUT), 4=flush
    .reserved       resd 1      ; Must be 0
    .sector         resq 1      ; Target LBA (logical sector number)
endstruc

; ---- tss_t : x86-64 Task State Segment (HARDWARE-FIXED, 104 bytes) ----------
struc tss_t
    .reserved0   resd 1      ; 0x00
    .rsp0        resq 1      ; 0x04  Ring-0 stack pointer
    .rsp1        resq 1      ; 0x0C
    .rsp2        resq 1      ; 0x14
    .reserved1   resq 1      ; 0x1C
    .ist1        resq 1      ; 0x24  IST1: double-fault stack
    .ist2        resq 1      ; 0x2C  IST2: NMI stack
    .ist3        resq 1      ; 0x34
    .ist4        resq 1      ; 0x3C
    .ist5        resq 1      ; 0x44
    .ist6        resq 1      ; 0x4C
    .ist7        resq 1      ; 0x54
    .reserved2   resq 1      ; 0x5C
    .reserved3   resw 1      ; 0x64
    .iomap_base  resw 1      ; 0x66  I/O permission-map base offset
endstruc                     ; total = 0x68 (104)

; ---- rsdp_t : ACPI Root System Description Pointer (ACPI 2.0+, 36 bytes) ----
struc rsdp_t
    .signature    resb 8     ; 0x00  "RSD PTR "
    .checksum     resb 1     ; 0x08  v1 checksum (first 20 bytes)
    .oem_id       resb 6     ; 0x09
    .revision     resb 1     ; 0x0F  0 = ACPI 1.0, 2 = ACPI 2.0+
    .rsdt_addr    resd 1     ; 0x10  32-bit RSDT (legacy; ignore when revision>=2)
    .length       resd 1     ; 0x14  total table length
    .xsdt_addr    resq 1     ; 0x18  64-bit XSDT (use this on revision>=2)
    .ext_checksum resb 1     ; 0x20  checksum over the whole 36-byte structure
    .reserved     resb 3     ; 0x21
endstruc                     ; total = 0x24 (36)
> XSDT path is the bring-up path.

; =============================================================================
; CONSTANTS
; =============================================================================

; ---- io_request_t State Constants (io_request_t.state) ----------------------
IO_REQ_INIT       equ 0      ; Request initialized but not yet submitted
IO_REQ_SUBMITTED  equ 1      ; Request placed in SPSC submission ring
IO_REQ_IN_FLIGHT  equ 2      ; Driver has picked up request and is executing DMA
IO_REQ_COMPLETE   equ 3      ; Request completed successfully
IO_REQ_ERROR      equ 4      ; Request failed with an error
IO_REQ_CANCELLED  equ 5      ; Request cancelled before or during execution
IO_REQ_TIMEOUT    equ 6      ; Request timed out on the timeout wheel

; State Machine Transitions & Ownership:
; * INIT → SUBMITTED → IN_FLIGHT: Mutated only by the submission path/producer.
; * IN_FLIGHT → COMPLETE / ERROR: Mutated only by the ISR handling device completion.
; * IN_FLIGHT → TIMEOUT: Mutated only by the timeout wheel when request exceeds deadline.
; * SUBMITTED / IN_FLIGHT → CANCELLED: Mutated only by the cancellation handler path.

; ---- Completion ID Namespace & Allocation Strategy -------------------------
; To guarantee lockless, race-free execution and prevent collision upon ID wrap-around,
; io_request_t.id is formatted as a 64-bit value packed as follows:
; ID = (core_id << 48) | (sequence_number & 0x0000_FFFF_FFFF_FFFF)
; where:
; * core_id (16-bit): The ID of the logical CPU core that submitted the request.
; * sequence_number (48-bit): A per-core monotonic counter bumped on every submission.
; A 48-bit sequence counter will not wrap in any practical system lifespan, preventing
; stale completions from matching new requests.
IO_COMP_ID_MASK   equ 0x0000FFFFFFFFFFFF

; ---- File Descriptor Type Constants (fd_t.type) ---------------------------
FD_TYPE_FILE      equ 0      ; Regular file (reserved for ufs subsystem)
FD_TYPE_BLOCK     equ 1      ; Block device (disk, NVMe, partition)
FD_TYPE_CHAR      equ 2      ; Character device (serial console, keyboard)
FD_TYPE_EVENT     equ 3      ; Event synchronization primitive
FD_TYPE_PIPE      equ 4      ; In-kernel pipe

; ---- Device State Constants (device_t.state) ------------------------------
DEV_STATE_PROBE    equ 0      ; Device is being probed / detected
DEV_STATE_ONLINE   equ 1      ; Device is active and accepting I/O requests
DEV_STATE_DEGRADED equ 2      ; Device is active but running in degraded/recovery mode
DEV_STATE_RESET    equ 3      ; Device is undergoing controller/queue reset
DEV_STATE_OFFLINE  equ 4      ; Device is disabled (failed or hot-removed)

; ---- I/O Opcode Constants (io_request_t.opcode) ---------------------------
IO_OP_READ         equ 0      ; Read sectors/bytes
IO_OP_WRITE        equ 1      ; Write sectors/bytes
IO_OP_FLUSH        equ 2      ; Flush write caches / barrier
IO_OP_TRIM         equ 3      ; Trim / discard blocks
IO_OP_WRITE_ZEROES equ 4      ; Fast-zero blocks

; ---- I/O Flag Bits (io_request_t.flags) ------------------------------------
IO_DIRECT          equ (1 << 0) ; Direct I/O (bypass host page/block caches)
IO_FUA             equ (1 << 1) ; Force Unit Access (write directly to media)
IO_FIXEDBUF        equ (1 << 2) ; Pre-registered / pinned DMA buffer

; ---- Page Table Entry (PTE) Hardware Bits ----------------------------------
PTE_PRESENT        equ (1 << 0) ; Page is mapped in translation tables
PTE_WRITE          equ (1 << 1) ; Write access allowed
PTE_USER           equ (1 << 2) ; User-mode access allowed
PTE_PWT            equ (1 << 3) ; Write-Through caching (PWT)
PTE_PCD            equ (1 << 4) ; Cache-Disabled (PCD)
PTE_PAT            equ (1 << 7) ; Page Attribute Table index bit (for PTEs)
PTE_NX             equ (1 << 63); No-Execute (requires LME.NXE enabled)

; ---- Virtio-Blk Status Codes -----------------------------------------------
VIRTIO_BLK_S_OK     equ 0       ; Success
VIRTIO_BLK_S_IOERR  equ 1       ; Device I/O error
VIRTIO_BLK_S_UNSUPP equ 2       ; Unsupported command

; ---- Local APIC Register MMIO Offsets ---------------------------------------
LAPIC_ID           equ 0x0020   ; Local APIC ID
LAPIC_VER          equ 0x0030   ; Version
LAPIC_TPR          equ 0x0080   ; Task Priority Register
LAPIC_EOI          equ 0x00B0   ; End Of Interrupt
LAPIC_SVR          equ 0x00F0   ; Spurious Interrupt Vector Register
LAPIC_ICR0         equ 0x0300   ; Interrupt Command Register [0:31]
LAPIC_ICR1         equ 0x0310   ; Interrupt Command Register [32:63]
LAPIC_LVT_TIMER    equ 0x0320   ; Timer LVT Register
LAPIC_TIMER_INIT   equ 0x0380   ; Timer Initial Count Register
LAPIC_TIMER_CUR    equ 0x0390   ; Timer Current Count Register
LAPIC_TIMER_DIV    equ 0x03E0   ; Timer Divide Configuration Register

; ---- IO-APIC Register Offsets ----------------------------------------------
IOAPIC_REGSEL      equ 0x00     ; Index Select Register
IOAPIC_IOWIN       equ 0x10     ; Data Window Register
IOAPIC_REDTBL_BASE equ 0x10     ; Base offset for Redirection Table entries (0-23)

---

## 6. Interrupt Vector Map

Single source of truth; every file in `intr/` and every driver installing a handler
agrees with this table.

| Vectors | Assignment |
| :-- | :-- |
| `0x00`–`0x1F` | CPU exceptions (double-fault `0x08` and NMI `0x02` use IST stacks) |
| `0x20`–`0x2F` | 8259 PIC remap window (masked off after APIC init) |
| `0x30` | LAPIC timer (timeout-wheel tick) |
| `0x31` | IPI: reschedule |
| `0x32` | IPI: TLB shootdown |
| `0x33` | IPI: wakeup |
| `0x40`–`0xEF` | Dynamically allocated MSI/MSI-X device vectors (`intr/vector.asm`) |
| `0xF0`–`0xFE` | Reserved (future: per-core scheduling) |
| `0xFF` | Spurious interrupt (`intr/spurious.asm`) |

Any vector without an installed handler routes to the unhandled-vector catch-all, which
logs over serial and continues rather than faulting blind.

---

## 7. Intra-`io` Build Order (Dependency DAG)

Build and unit-test in this order. Each stage links only against earlier stages.

```
1.  macro/  +  const/  +  error/            ; no code, pure definitions
2.  arch/x86_64/                            ; portio, mmio, barrier, cache
3.  boot/handoff  +  acpi/                  ; ingest handoff, walk MADT/MCFG/FADT
4.  core/percpu                             ; per-CPU base before any per-core state
5.  core/ (fd, handle, buffer, iovec,       ; descriptors, buffers, SG
        align, bounce, fixed_buf)
6.  char/serial  +  char/console            ; DEBUG OUTPUT ONLINE — printf for all below
7.  intr/ (idt+IST, isr, exception,         ; interrupts, incl. double-fault safety
        spurious, pic, lapic, ioapic, vector)
8.  pci/ (config, enum, bar, caps, match)   ; devices become discoverable
9.  dma/ (alloc, map, sg, sync, barrier)    ; DMA memory + PRP/SGL build
10. block/ (bdev, ata_pio)                  ; first raw sector read (polling)
11. block/virtio_blk                        ; first REAL async device (INTx)
12. async/ (submit, complete, request,      ; SPSC rings + completion path
        timeout, batch)
13. sched/ (wait, wake, waitq, poll)        ; block-on-completion
    ────────────────────────────────────────────────────────────────────
    ▲ PHASE 1 EXIT (see §9). Everything below is hardening / scaling / AI path.
    ────────────────────────────────────────────────────────────────────
14. intr/msi  +  block/ahci                 ; MSI-X + SATA
15. block/nvme  +  block/gpt                ; NVMe multi-queue, namespaces, partitions
16. async/napi, retry, cancel, mpsc         ; adaptive poll, robustness, SMP queues
17. intr/ipi, affinity, coalesce            ; SMP interrupt scaling
18. dma/p2p, gpudirect, iommu               ; AI data path
19. health/, stat/, char/serial_irq         ; recovery, telemetry, IRQ serial
20. arch/aarch64, arch/riscv, plat/ shims   ; portability, hosted builds
```

---

## 8. Runtime Init Sequence (`io_init`)

Distinct from build order — this is what executes at boot, in order:

```
; =============================================================================
; io_init — Initialize the I/O subsystem (BSP path)
; In : RDI = -> boot_handoff_t (from boot)
; Out: RAX = 0 on success, or a negative error band code (Core/ACPI band) on failure
; =============================================================================
io_init(boot_handoff_t *bh):
  1.  handoff_ingest(bh)              ; capture mem map, RSDP, framebuffer, boot dev
  2.  serial_init(COM1)              ; loopback-tested debug output FIRST
  3.  console_init()                 ; milestone "IO:INIT" over serial
  4.  acpi_scan(bh->rsdp)            ; MADT (APIC), MCFG (ECAM), FADT
  5.  percpu_init()                  ; GS_BASE for the boot core
  6.  idt_init()                     ; gates + IST stacks (double-fault/NMI safe)
  7.  pic_remap(); pic_mask_all()    ; move PIC out of the way
  8.  lapic_init(); lapic_timer_arm(); ioapic_init()
  9.  vector_init()                  ; vector allocator online
  10. pci_enumerate()                ; walk buses, size/map BARs, parse caps
  11. dma_init()                     ; DMA arena, bounce pool, sync primitives
  12. driver_probe()                 ; match.asm binds drivers to devices
      └─ virtio_blk / ata_pio / (later) nvme, ahci
  13. async_init()                   ; per-core SPSC rings, completion path
  14. sched_hooks_init()             ; wait/wake (stub if scheduler absent)
  15. milestone "IO:READY"
```

> **Failure Path handling**: If any initialization step fails (e.g., `handoff_ingest` returns `IO_ERR_BADARG`, or `acpi_scan` fails validation checks), the system emits `IO:FAIL:<code>` over the serial COM1 port (using `serial_putc` directly if the high-level logging is not yet active) and returns the error code to kernel init. The kernel init caller determines whether to halt or try a fallback boot path.

> **SMP Core Initialization Sequence (`io_ap_init`)**:
> When Application Processors (AP cores) are booted by the scheduler/kernel, each AP core must initialize its local I/O structures. They execute a subset of the initialization sequence:
> ```
> io_ap_init():
>   1. percpu_init()                  ; set up GS_BASE for this core
>   2. idt_init()                     ; load IDT and allocate local IST stacks
>   3. lapic_init()                   ; initialize Local APIC timer for this core
>   4. dma_ap_init()                  ; set up per-core bounce buffers/DMA tracking
>   5. async_ap_init()                ; allocate per-core SPSC submission/completion rings
>   6. milestone "IO:AP_READY"
> ```
> *Note: BSP (Boot Strap Processor) alone performs ACPI scanning, PIC remapping, PCI enumeration, and global device driver binding. AP cores join the running I/O subsystem by attaching their private queue pairs to existing registered devices (such as multi-queue NVMe).*

Each step emits a milestone char/string over serial (the `boot` survive pattern), so a
hang is pinpointed to the exact stage without a debugger.

---

## 9. Phase 1 Exit Criteria

io is "working" when this single end-to-end assertion passes in QEMU (single core):

> **virtio-blk reads sector 0 of the boot device via an `io_request_t` submitted to an
> SPSC ring; completion arrives by INTx interrupt into a pre-allocated completion slot;
> the waiting task is woken via `sched/wait`; the 512/4096 bytes are echoed over serial.**

This exercises, in one path: serial + console, ACPI+percpu+IDT, PCI enumeration, DMA
mapping + PRP/SGL, virtqueue ordering barriers, the SPSC submission and
completion rings, the pre-allocated ISR completion constraint, and the block-on-completion
scheduler hook. If all of that works, the skeleton is real and everything else is an
incremental driver or hardening pass bolted onto a proven spine.

The QEMU harness (`test/qemu/`) automates this as the gate that must stay green.

---

## 10. Key Module APIs & Assembly Stubs (Phase 1)

### A. x86-64 Hardware Port I/O — `arch/x86_64/portio.asm`

```asm
; =============================================================================
; port_in8 — Read 1 byte from an x86 I/O port
; In : RDI = port (16-bit)
; Out: RAX = byte
; RSO: RDX scratch (saved); RAX owned-out
; =============================================================================
IO_FUNC port_in8
    push rdx
    mov  rdx, rdi
    xor  rax, rax
    in   al, dx
    pop  rdx
    ret
IO_ENDFUNC port_in8

; =============================================================================
; port_out8 — Write 1 byte to an x86 I/O port
; In : RDI = port (16-bit), RSI = byte
; RSO: RDX,RAX scratch (saved)
; =============================================================================
IO_FUNC port_out8
    push rdx
    push rax
    mov  rdx, rdi
    mov  rax, rsi
    out  dx, al
    pop  rax
    pop  rdx
    ret
IO_ENDFUNC port_out8
```

### B. 16550 UART with loopback presence test — `char/serial.asm`

```asm
; =============================================================================
; serial_init — Init 16550 COM to 115200 8N1 with loopback presence test.
; In : RDI = UART base (e.g. 0x3F8)
; Out: RAX = 0 on success, IO_ERR_NO_DEVICE (band, Core) if absent
; RSO: RBX = base (callee-saved, restored); RAX owned-out
; =============================================================================
IO_FUNC serial_init
    push rbx
    mov  rbx, rdi                   ; RBX = UART base

    lea  rdi, [rbx + 1]             ; IER: disable interrupts
    xor  rsi, rsi
    call port_out8

    lea  rdi, [rbx + 4]             ; MCR: loopback + RTS/DTR/OUT2
    mov  rsi, 0x1E
    call port_out8

    mov  rdi, rbx                   ; THR: write test pattern
    mov  rsi, 0xAE
    call port_out8

    mov  rdx, 1000                  ; brief settle
.settle:
    dec  rdx
    jnz  .settle

    lea  rdi, [rbx + 5]             ; LSR: data ready?
    call port_in8
    test al, 0x01
    jz   .absent

    mov  rdi, rbx                   ; RBR: read back
    call port_in8
    cmp  al, 0xAE
    jne  .absent

    lea  rdi, [rbx + 3]             ; LCR: enable DLAB
    mov  rsi, 0x80
    call port_out8
    mov  rdi, rbx                   ; DLL = 1  (115200)
    mov  rsi, 1
    call port_out8
    lea  rdi, [rbx + 1]             ; DLM = 0
    xor  rsi, rsi
    call port_out8
    lea  rdi, [rbx + 3]             ; LCR: 8N1, DLAB off
    mov  rsi, 0x03
    call port_out8
    lea  rdi, [rbx + 2]             ; FCR: FIFO on, clear, 14-byte trigger
    mov  rsi, 0xC7
    call port_out8
    lea  rdi, [rbx + 4]             ; MCR: normal, RTS/DTR/OUT2
    mov  rsi, 0x0B
    call port_out8

    xor  rax, rax                   ; success
    jmp  .done
.absent:
    mov  rax, IO_ERR_NO_DEVICE      ; §3 Core band, negative
.done:
    pop  rbx
    ret
IO_ENDFUNC serial_init

; =============================================================================
; serial_putc — Synchronous byte transmit
; In : RDI = UART base, RSI = byte
; RSO: RBX = base, R12 = char (callee-saved, restored)
; =============================================================================
IO_FUNC serial_putc
    push rbx
    push r12
    mov  rbx, rdi
    mov  r12, rsi
.wait_tx:
    lea  rdi, [rbx + 5]             ; LSR
    call port_in8
    test al, 0x20                   ; THRE
    jz   .wait_tx
    mov  rdi, rbx                   ; THR
    mov  rsi, r12
    call port_out8
    pop  r12
    pop  rbx
    ret
IO_ENDFUNC serial_putc
```

### C. Refcounted handle allocator — `core/handle.asm`

```asm
; =============================================================================
; io_handle_alloc — Register an active descriptor; return an encoded handle.
; In : RDI = -> fd_t, RSI = -> generation tracker
; Out: RAX = handle (index<<16 | generation), or ERR_PTR/band code on failure
; RSO: RDI,RSI owned-in; RAX owned-out
; =============================================================================
IO_FUNC io_handle_alloc
    guard_null rdi                  ; -> IO_ERR_NULL (Core band) if null
    guard_null rsi
    ; 1. find a free descriptor slot (bounded scan / free-list)
    ; 2. bump generation counter, store into fd_t.generation
    ; 3. set fd_t.state = FD_OPEN, fd_t.refcount = 1
    ; 4. encode: RAX = (slot_index << 16) | (generation & 0xFFFF)
    ret
IO_ENDFUNC io_handle_alloc

; =============================================================================
; io_handle_lookup — Resolve a handle to its fd_t, validating generation.
; In : RDI = handle
; Out: RAX = -> fd_t, or ERR_PTR(IO_ERR_STALE) if generation mismatch/stale
; =============================================================================
IO_FUNC io_handle_lookup
    ; slot = RDI >> 16 ; gen = RDI & 0xFFFF
    ; if slot out of range          -> ERR_PTR(IO_ERR_BADFD)
    ; if fd.generation != gen       -> ERR_PTR(IO_ERR_STALE)
    ; if fd.state == FD_STALE       -> ERR_PTR(IO_ERR_STALE)
    ; else RAX = &fd
    ret
IO_ENDFUNC io_handle_lookup
```

### D. DMA coherent memory allocator — `dma/alloc.asm`

```asm
; =============================================================================
; dma_alloc — Allocate DMA-coherent, physically contiguous memory.
; In : RDI = size in bytes
;      RSI = alignment (must be a power of 2, minimum 64 bytes)
;      RDX = flags (DMA_32BIT | DMA_HUGEPAGE)
; Out: RAX = physical address of the allocated buffer (or ERR_PTR on failure)
;      RBX = virtual address of the allocated buffer (or 0 on failure)
; RSO: RAX and RBX owned-out
; =============================================================================
IO_FUNC dma_alloc
    guard_bar rsi, 64, 4194304      ; alignment constraint check
    ; 1. Request physical pages from mem matching size and alignment
    ; 2. If DMA_32BIT, ensure physical address is below 4 GB limit
    ; 3. If DMA_HUGEPAGE, request 2MB/1GB contiguous pages
    ; 4. Map into kernel virtual space and return phys in RAX, virt in RBX
    ret
IO_ENDFUNC dma_alloc
```

### E. Early console milestone logger — `char/console.asm`

```asm
; =============================================================================
; console_milestone — Emit a prefixed milestone string to the COM1 serial port.
; In : RDI = -> null-terminated ASCIIZ string (e.g. "IO:INIT")
; RSO: RDI owned-in (saved); RAX scratch
; =============================================================================
IO_FUNC console_milestone
    guard_null rdi
    ; 1. Output prefix "[Milestone] "
    ; 2. Iterate and output string via serial_putc (synchronous/polling)
    ; 3. Output newline (\r\n)
    ret
IO_ENDFUNC console_milestone
```

### F. Driver match registration — `pci/match.asm`

```asm
; =============================================================================
; driver_register — Register a driver binding descriptor in the global driver table.
; In : RDI = -> driver_binding_t descriptor
; Out: RAX = 0 on success, or a negative error band code (Core band) on failure
; RSO: RDI owned-in; RAX owned-out
; =============================================================================
IO_FUNC driver_register
    guard_null rdi
    ; 1. Check if global driver table has space
    ; 2. Insert driver_binding_t copy into table
    ; 3. Return 0, or IO_ERR_NOMEM if table is full
    ret
IO_ENDFUNC driver_register
```

---

## 11. Cross-Cutting Invariants (read before writing any file)

1. **No allocation in an ISR.** Completion = write a pre-allocated `io_completion_t` slot
   + bump a ring index. Nothing else.
2. **A buffer with in-flight DMA is frozen.** `io_request_t.pin_token` is released only
   on completion; `buffer.asm` refuses to free/reuse a pinned range.
3. **Never assume sector size.** Query LBA format at probe; carry it on the device object.
4. **Never assume a fixed MMIO/APIC/ECAM address.** It comes from ACPI (or the boot
   handoff), not a constant.
5. **Real store fences on every MMIO doorbell / virtqueue notify.** Not compiler barriers.
6. **Pointer-or-error returns obey the top-page rule.** Gate with `IS_ERR` before deref.
7. **Design rings SPSC-lockless from the first line**, even single-core.
8. **io owns no clock dependency.** Ticks come from the LAPIC timer; timestamps from
   `rdtscp`. Never pull in the `time` module.
9. **Every init stage emits a serial milestone**, so a hang localizes without a debugger.
10. **io hands ufs block devices, not raw LBAs.** GPT/namespace parsing lives here.

---

## 12. Security and Safety Invariants

For an enterprise-grade operating system kernel, physical memory accesses and device communications must be strictly isolated to prevent sandboxing breaks, stack corruption, or kernel memory exposure:

### 12.1 Supervisor Mode Access Prevention (SMAP) & User Pointer Validation
* **Rule**: To prevent user processes from passing malicious kernel-space pointers as buffers, every user-space I/O transfer must validate the target range:
  `[buffer, buffer + length) < USER_SPACE_LIMIT` (which is `0x0000_8000_0000_0000` on x86-64). If any portion crosses this limit, the request must fail immediately with `IO_ERR_BADARG`.
* **Execution**: During CPU-driven copies to/from user space (`lib/mem/ops/user_copy.asm`), the assembler must wrap operations with `stac` (to enable Supervisor Mode Access) and `clac` (to disable it immediately upon completion), ensuring the kernel never accesses user pages outside these validated blocks.

### 12.2 GPT Partition Sandbox Boundary Enforcement
* **Rule**: When executing reads or writes on a virtual device partition, the block layer must strictly validate ranges before dispatching to prevent "partition escape" security breaches.
* **Math**: The driver must assert:
  `if (req.lba + req.nblocks > dev.lba_count) return IO_ERR_BADARG`
  Only after validation passes is the partition offset applied:
  `req.lba += dev.lba_offset`
  and the command forwarded to the parent physical block device.

### 12.3 PCIe Access Control Services (ACS) Guard for P2P DMA
* **Rule**: PCIe Peer-to-Peer (P2P) transfers bypass system memory and the Root Complex. If intermediate PCIe switches do not enforce ACS, hardware-level DMA spoofing is possible.
* **Validation**: During PCI enumeration (**§8** step 10), `lib/io` must scan all intermediate PCIe switches between the source NVMe controller and the target GPU. If ACS is disabled on any switch in the downstream path, peer-to-peer DMA setup is rejected and the system falls back to system-memory bounce buffers.

### 12.4 Non-Present Stack Guard Pages
* **Rule**: To prevent nested interrupt handlers or deep hardware queues from silently overrunning local stacks and corrupting adjacent memory:
* **Configuration**: In the page table structure, the virtual page immediately below each per-core IRQ stack and IST stack must be mapped as "not present" (clearing `PTE_PRESENT`). Stack overflows will trigger a Page Fault (`#PF`) immediately, enabling diagnostic panic recovery rather than silent memory corruption.

### 12.5 Active DMA Pin Refcounts
* **Rule**: To prevent use-after-free or buffer recycling during in-flight device transfers, no memory page actively mapped to a device queue may be unmapped or freed.
* **Locking**: The memory subsystem tracks DMA pins via a `pin_count` inside `lib/mem`. Any call to `fixed_buf_unregister` or page reclaim against a buffer with `pin_count > 0` must return `IO_ERR_STALE` and refuse memory release until the completion ISR issues the corresponding decrement.

### 12.6 Stack Pointer Integrity & Verification
* **Rule**: To protect against stack-smashing exploitation or hardware bit-flips, every interrupt frame entry and exit must verify that the stack pointer (`RSP`) lies within the logical per-CPU stack bounds defined in `percpu_t.irq_stack` before executing a return.
* **Verification**: On ISR entry, compare the current `RSP` against the stack limits. If out of bounds, halt the core immediately to prevent code execution on corrupted frames.

---

## 13. Hardware-Level Performance Invariants

To achieve absolute line-rate data transfers saturating the PCIe bus and CPU execution units, all driver implementations and core modules in `lib/io` must strictly adhere to the following 30 low-level performance invariants:

### 13.1 Lockless Architecture & Execution Locality

#### 13.1.1 Zero-Lock Cross-Core Rescheduling (Direct IPI Wakeup)
When an I/O completion is processed on Core A for a task that is blocked on Core B, Core A must bypass the global scheduler run-queues to prevent spinlock contention. Instead, Core A pushes the task pointer (`task_t *`) to Core B's lockless SPSC queue (`percpu_t.submit_ring`) and triggers a hardware Local APIC interrupt on Core B.
* **Implementation**: Core A writes the Wakeup Vector (`0x33`) and target Core B's APIC ID directly to the LAPIC Interrupt Command Registers (ICR):
  ```asm
  ; 1. Push task_t pointer in RAX to Core B's SPSC queue
  mov rdi, [core_b_spsc_ring]
  call spsc_push                  ; Returns success or error in RAX
  test rax, rax
  jnz .fallback_slow_path

  ; 2. Signal Core B via LAPIC IPI using the Wakeup Vector (0x33)
  mov rdx, [LAPIC_BASE_VIRT]
  mov eax, [core_b_apic_id]
  shl eax, 24                     ; APIC ID in bits [24:31] of ICR1
  mov [rdx + 0x310], eax          ; Write to LAPIC ICR1 (High dword)
  mov eax, 0x00000033             ; Delivery Mode: Fixed | Vector: 0x33
  mov [rdx + 0x300], eax          ; Write to LAPIC ICR0 (Low dword) - fires IPI
  ```

#### 13.1.2 Cache-Line Partitioned SPSC Rings
Submission and completion indexes must reside on separate 64-byte cache lines to prevent cache line bouncing (false sharing).
* **Canonical layout**: This is realized by the single `spsc_ring_t` definition in **§5** — a
  192-byte / three-cache-line structure with `mask`/`buffer`/`entry_size`/`capacity` on
  the read-only header line (offset 0), `prod_idx` alone on line 1 (offset 64), and
  `cons_idx` alone on line 2 (offset 128). Do **not** redefine `spsc_ring_t` here; §5 is
  the sole definition and §15.1 asserts `prod_idx == 64` and `cons_idx == 128`.

#### 13.1.3 Monotonic Wrapping Ring Indexes
Pointers wrap naturally without using modulo divisions.
* **Implementation**: Array offsets are calculated using bitwise masks:
  ```asm
  ; RAX = prod_idx (monotonic 64-bit), RBX = mask (capacity - 1)
  and rax, rbx                    ; Single instruction index resolution
  shl rax, 6                      ; Scale by descriptor size (e.g. 64 bytes)
  add rax, [ring_buffer_base]     ; Target slot address resolved
  ```

#### 13.1.4 O(1) Bitmask Event Multiplexing
Replaces linear descriptor checks with O(1) bit-scan instructions.
* **Implementation**: Active file descriptors write their ready state directly to a shared 64-bit bitmap:
  ```asm
  mov rax, [event_bitmap]
  test rax, rax                   ; Check if any bits are set
  jz .no_events
  bsf rcx, rax                    ; Locate first active file descriptor index
  btr [event_bitmap], rcx         ; Reset the checked bit atomically
  ```

#### 13.1.5 Vector Interrupt Steering (Core-Affined MSI-X)
MSI-X registers are programmed to deliver completion interrupts directly to the specific CPU core that issued the request.
* **Implementation**:
  ```asm
  ; --- Program MSI-X Table entry ---
  mov rdi, [msix_table_base]
  shl rbx, 4                      ; Index into 16-byte MSI-X table entries
  mov eax, [target_core_apic_id]
  shl eax, 12                     ; Destination APIC ID in bits [12:19]
  or eax, 0xFEE00000              ; APIC Base Address for Interrupts
  mov [rdi + rbx + 0], eax        ; Program msg_addr_low
  mov dword [rdi + rbx + 4], 0    ; Program msg_addr_high
  mov eax, [queue_assigned_vector]
  mov [rdi + rbx + 8], eax        ; Program msg_data (vector mapping)
  ```

#### 13.1.6 Interrupt Vector Prioritization
Storage completions are mapped to LAPIC priority classes 14 or 15.
* **Implementation**: Storage completions are assigned high vector numbers (range `0xE0`–`0xEF`):
  ```asm
  ; Program LAPIC Task Priority Register (TPR) to block low-priority vectors
  mov rdi, [LAPIC_BASE_VIRT]
  mov dword [rdi + 0x080], 0x000000C0 ; Blocks all interrupts below priority 12 (vectors < 0xC0)
  ; Storage interrupts (vector 0xE0) bypass TPR filter and execute immediately
  ```

#### 13.1.7 Command ID (CID) Direct Index Mapping
Matches the 16-bit NVMe CID to the pre-allocated request pool index.
* **Implementation**: The 16-bit NVMe CID in the SQE matches the request pool index:
  ```asm
  ; --- On NVMe Completion ---
  ; RDX = -> NVMe CQE (Completion Queue Entry)
  movzx rax, word [rdx + 12]      ; Extract cqe.command_id (CID)
  shl rax, 6                      ; Scale by request size (64 bytes)
  add rax, [request_pool_base]    ; RAX = -> io_request_t
  ; Original request resolved in 3 instructions; no hash lookup or linear search
  ```

---

### 13.2 MMIO Control & Coalescing

#### 13.2.1 Doorbell Plugging / MMIO Coalescing
Device MMIO writes are uncached and force CPU serialization. Submission paths must accumulate commands in the SPSC ring in memory, incrementing only local registry tracking registers. The physical device doorbell is "plugged" and only rung once at the end of the batch.
* **Implementation**: The loop increments the local head/tail indexes in CPU registers. Only after the loop terminates does the code issue a single `sfence` memory barrier followed by a single write-only memory store to the device's MMIO doorbell register:
  ```asm
  ; --- Submission Loop ---
  .submit_loop:
      ; ... build descriptors and place in memory SPSC queue ring ...
      dec rcx
      jnz .submit_loop

  ; --- Unplug (Ring Doorbell) ---
  sfence                          ; Ensure all descriptors are visible in RAM
  mov rax, [queue_doorbell_mmio]
  mov edx, [local_tail_index]
  mov [rax], edx                  ; Single MMIO write triggers device execution
  ```

#### 13.2.2 Doorbell Shadow Register Caching
Avoids slow MMIO reads over the PCIe bus by maintaining cached tail offsets in local memory.
* **Implementation**:
  ```asm
  ; --- Read current tail pointer ---
  mov rax, [local_shadow_tail_ptr] ; Read cache-aligned variable in RAM
  ; Avoids calling: mov rax, [queue_doorbell_mmio] (which forces PCIe bus roundtrip)
  ```

#### 13.2.3 Write-Combining (WC) MMIO Doorbell Mapping
Uses PAT indices to map doorbell registers as Write-Combining (WC) for 64-byte burst writes.
* **Implementation**: The driver configures the Page Attribute Table (PAT) register (MSR `0x277`) to define a WC slot:
  ```asm
  ; Configure Page Attribute Table (PAT) MSR 0x277: Write-Combining in index slot 2 (PA2)
  mov ecx, 0x277                  ; PAT MSR register
  rdmsr
  ; Modify bits [16:23] of RAX to 0x01 (Write-Combining) — this is PA2
  and eax, 0xFF00FFFF
  or eax, 0x00010000
  wrmsr
  ; Doorbell page PTE then selects PA2 with: PCD=1, PWT=0, PAT=0  (index bits = 010b = 2).
  ; (An earlier note said PAT=1/PWT=1 → that selects PA5, not the programmed PA2; corrected.)
  ```

#### 13.2.4 Target-Flushing `sfence` Doorbell Ordering
Uses target-specific `sfence` to flush WC buffers without stalling execution pipelines.
* **Implementation**: The driver places an `sfence` instruction immediately before the write-combining doorbell write:
  ```asm
  ; --- Execute write-combining flush ---
  sfence                          ; Flush Write-Combining buffer
  mov rax, [nvme_doorbell_mmio]
  mov [rax], edx                  ; Ring doorbell; CPU cache remains intact
  ```

#### 13.2.5 MSI-X Table Vector Masking
Masks device interrupts dynamically during busy-polling to bypass APIC delivery overhead.
* **Implementation**:
  ```asm
  ; --- Mask MSI-X Vector ---
  mov rsi, [msix_vector_control_addr]
  mov eax, [rsi]
  or eax, 1                       ; Set Mask Bit (Bit 0)
  mov [rsi], eax                  ; Write back (Interrupts masked at hardware level)
  ```

---

### 13.3 Memory Layout & Page Translation

#### 13.3.1 Huge-Page DMA Mapping (2MB/1GB)
DMA buffers must leverage 2MB or 1GB huge pages to shrink page-table walks and decrease PRP/SGL descriptor counts.
* **Implementation**: 
  ```asm
  ; --- Map 2MB Huge Page in Page Tables ---
  ; Page Directory Entry (PDE) must have Page Size (PS) bit 7 set to 1
  mov rax, [physical_page_2mb_aligned]
  or rax, (PTE_PRESENT | PTE_WRITE | (1 << 7)) ; Set PS bit
  mov [page_directory_entry_addr], rax
  ```

#### 13.3.2 Pre-Registered and Pinned Buffers (`IO_FIXEDBUF`)
Buffers are registered and pinned at startup, compiling physical addresses to a static table.
* **Implementation**: `fixed_buf_register` walks the buffer's virtual address range, locks the physical pages, and pins them. The resulting Physical Frame Numbers (PFNs) are compiled into a static lookup descriptor table:
  ```asm
  ; --- Hot-Path Buffer Resolution ---
  ; RAX = buffer_id, RCX = offset inside buffer
  mov rsi, [fixed_buffer_table]
  shl rax, 4                      ; 16-byte table entries (phys_addr, length)
  mov rdx, [rsi + rax]            ; RDX = physical base address
  add rdx, rcx                    ; RDX = target physical memory address
  ```

#### 13.3.3 PRP List Offset Alignment Handling
Calculates buffer start offsets to allow unaligned DMA transfers without copy operations.
* **Implementation**: The driver calculates the page offset and programs PRP1 and PRP2 accordingly:
  ```asm
  ; RDI = buffer address
  mov rax, rdi
  and rax, 0x0FFF                 ; Extract offset within 4KB page
  mov [nvme_sqe.prp1], rdi        ; Program PRP1 (starts at offset)
  ; PRP2 must point to page-aligned list containing subsequent pages
  ```

#### 13.3.4 Pre-Allocated PRP List Page Pools
Assembles PRP lists on physical pages pulled from a lockless LIFO stack in O(1) time.
* **Implementation**:
  ```asm
  ; --- Pop PRP list page from LIFO ---
  .retry_pop:
      mov rax, [prp_pool_top]
      test rax, rax               ; Check if stack empty
      jz .fallback_allocate
      mov rbx, [rax]              ; Get next pointer (stored at start of page)
      lock cmpxchg [prp_pool_top], rbx
      jnz .retry_pop              ; If cmpxchg failed, try again
  ; Selected page is in RAX
  ```

#### 13.3.5 NVMe SQE PRP Inlining
For transfers <= 8KB (2 pages), both physical pointers are inline in the SQE.
* **Implementation**:
  ```asm
  ; RAX = page 0 physical address, RBX = page 1 physical address
  mov [nvme_sqe.prp1], rax        ; Inline PRP1
  mov [nvme_sqe.prp2], rbx        ; Inline PRP2 (Direct page address, not list page pointer)
  ```

#### 13.3.6 SGL (Scatter-Gather List) Bit-Packed Compression
Compresses physically contiguous descriptor segments into single entries.
* **Implementation**:
  ```asm
  ; Walk SGL
  mov rax, [sgl_entry1.phys]
  add rax, [sgl_entry1.length]
  cmp rax, [sgl_entry2.phys]      ; Check contiguity
  jne .dont_compress
  add [sgl_entry1.length], [sgl_entry2.length] ; Merge length
  ; Mark sgl_entry2 as inactive
  ```

#### 13.3.7 Page-Crossing Descriptor Fusion
Contiguous physical pages are automatically merged into a single descriptor during compilation to minimize descriptor traffic.
* **Implementation**: During scatter-gather list parsing, the compiler compares adjacent page frames:
  ```asm
  ; RAX = current physical frame, RBX = next physical frame
  mov rcx, rax
  add rcx, 4096                   ; Expected contiguous address
  cmp rcx, rbx
  jne .generate_new_descriptor
  add [current_desc.length], 4096 ; Merge contig page; do not write new entry
  ```

#### 13.3.8 Interrupt-Safe Static Ring Allocators (Zero Heap)
All request descriptors are allocated from boot-time static memory pools using atomic bitmask operations.
* **Implementation**: `lib/io` allocates a static pool of `io_request_t` and tracks allocation states using a 64-bit bitmap:
  ```asm
  ; --- Allocate request slot index ---
  .retry:
      mov rax, [alloc_bitmap]
      not rax                     ; Invert to find 0s (free slots)
      bsf rcx, rax                ; Scan for first free bit
      jz .pool_exhausted          ; If 0, no free slots
      lock bts [alloc_bitmap], rcx; Atomically set bit
      jc .retry                   ; If bit was already set by another core, retry
  ; Slot index is in RCX
  ```

---

### 13.4 PCIe Link & Bus Performance

#### 13.4.1 GPUDirect PCIe Peer-to-Peer Bypass
Bypasses host RAM by routing DMA transfers directly between NVMe storage BARs and GPU VRAM BARs.
* **Implementation**: The GPU's VRAM BAR addresses are programmed directly into the NVMe command block's PRP pointers.
  ```asm
  ; --- Program NVMe PRP to target GPU VRAM ---
  mov rdi, [gpu_bar_p2p_phys_addr] ; GPU physical BAR address mapping
  add rdi, [gpu_buffer_offset]
  mov [nvme_sqe.prp1], rdi        ; Write GPU physical address as DMA target
  ```

#### 13.4.2 Max Payload Size (MPS) & MRRS Tuning
PCIe endpoints are configured during boot to utilize maximum packet payloads.
* **Implementation**: Locate the PCI Express Capability structure and modify the Device Control Register:
  ```asm
  ; Locating PCIe Device Control Register (usually offset 0x08 in PCIe Cap block)
  mov rdi, [pci_express_cap_base]
  mov ax, [rdi + 0x08]            ; Read Device Control Register
  and ax, 0x8F1F                  ; Mask out MPS (bits 5-7) and MRRS (bits 12-14)
  or ax, 0x5040                   ; Set MPS to 512B (010b) and MRRS to 4096B (101b)
  mov [rdi + 0x08], ax            ; Write back updated values
  ; NOTE: MRRS encoding is 000b=128,001b=256,010b=512,011b=1024,100b=2048,101b=4096.
  ; An earlier note used 0x4040 (100b) and labeled it 4096B — that is 2048B; corrected.
  ```

#### 13.4.3 PCIe Max Read Request Size (MRRS) Splitting
Partitions requests to align with MRRS boundaries, avoiding Root Complex packet fragmentation.
* **Implementation**:
  ```asm
  ; RAX = request size, RBX = MRRS (e.g. 4096)
  cmp rax, rbx
  jbe .submit_single
  ; Request exceeds MRRS; split block into multiple MRRS-aligned submission entries
  ```

#### 13.4.4 PCIe Advanced Error Reporting (AER) Ingestion
Aer registers are parsed dynamically in Ring 0 to handle bus glitches without panic.
* **Implementation**: The driver binds to the PCIe AER Capability structure and intercepts error interrupts:
  ```asm
  ; --- AER Exception Handler ---
  mov rsi, [pci_aer_cap_base]
  mov eax, [rsi + 0x04]           ; Read Uncorrectable Error Status Register
  test eax, eax                   ; Check for fatal bus errors
  jz .check_correctable
  ; Reset PCIe link via bridge secondary status register to attempt recovery
  mov rdi, [pci_bridge_config_base]
  or word [rdi + 0x3E], 0x0040    ; Trigger Bridge Secondary Reset (Bit 6)
  ```

#### 13.4.5 CMB (Controller Memory Buffer) Queue Placement
To save main system memory bus bandwidth, submission and completion descriptors are written directly to NVMe internal BAR memory (CMB) if the device indicates support.
* **Implementation**:
  ```asm
  ; --- Setup CMB Queue Base ---
  mov rax, [nvme_cmb_bar_virt]     ; Virtual mapped address of NVMe CMB
  add rax, [cmb_sq_offset]         ; Queue offset inside CMB BAR
  mov [nvme_sq_base_address], rax  ; Program virtual base

  ; --- Program Controller Address ---
  mov rbx, [nvme_cmb_bar_phys]     ; Physical address of NVMe CMB
  add rbx, [cmb_sq_offset]
  mov rdx, [nvme_regs_base]
  mov [rdx + 0x28], rbx            ; Write physical SQ base to ASQ/SQ register
  ```

---

### 13.5 Interrupt Minimization & Hardware Offloads

#### 13.5.1 Adaptive IRQ Coalescing (Hybrid Interrupt/Polling)
Completion threads dynamically toggle between busy-polling and interrupt-driven modes to minimize CPU overhead while retaining sub-microsecond latency.
* **Implementation**: The completion thread tracks idle loops. If the completion SPSC ring has pending entries, the thread polls in a tight `lfence; pause` loop. If no completions arrive for `T_poll` microseconds (e.g. 50us):
  ```asm
  ; --- Active Busy Polling Loop ---
  .poll_loop:
      call check_completion_ring  ; Check if index changed
      test rax, rax
      jnz .process_completion     ; If entries exist, process immediately
      pause                       ; Yield pipeline to save power/cycles
      lfence                      ; Load barrier
      dec rbx                     ; Decrement poll budget counter
      jnz .poll_loop

  ; --- Fallback to Interrupts ---
  ; Budget exhausted; re-enable device interrupts before yielding
  mov rsi, [msix_table_addr]
  mov eax, [rsi + MSIX_VECTOR_CTRL_OFFSET]
  and eax, ~1                     ; Clear mask bit (bit 0)
  mov [rsi + MSIX_VECTOR_CTRL_OFFSET], eax
  ```

#### 13.5.2 MSI-X Completion ISR Exit — Mandatory LAPIC EOI
Every MSI/MSI-X completion ISR **must** write the LAPIC EOI register before `iretq`,
edge-triggered or not. MSI vectors are LAPIC-delivered and set the in-service bit;
skipping EOI leaves that bit set and permanently blocks all equal-or-lower-priority
vectors — the completion queue goes dead after exactly one interrupt. There is **no**
edge-triggered EOI bypass for LAPIC-delivered vectors (only NMI/SMI/INIT/SIPI skip EOI).
* **Implementation**: Write EOI, then return:
  ```asm
  ; --- Completion ISR Exit ---
  mov rdi, [LAPIC_BASE_VIRT]
  mov dword [rdi + 0x0B0], 0      ; LAPIC EOI (offset 0xB0) — REQUIRED, not optional
  iretq                           ; Return from interrupt frame
  ```
  (A previous draft described an "edge-triggered EOI bypass" here; that is incorrect and
  hangs the queue after one completion. Removed.)

#### 13.5.3 Hardware-Coherent DMA Sync Bypass
Bypasses CPU cache invalidation loops on hardware-snooped cache-coherent architectures.
* **Implementation**:
  ```asm
  ; --- Cache Coherency Check ---
  mov rax, [cpu_features]
  test rax, CPU_FEAT_COHERENT_DMA
  jz .execute_cache_flush
  ret                             ; Bypass sync; return instantly
  .execute_cache_flush:
  ; ... execute clflush loop ...
  ```

#### 13.5.4 NVMe Weighted Round Robin (WRR) Queue Arbitration
Configures NVMe queue weights at the controller level to prioritize high-throughput dataset loading.
* **Implementation**: Set NVMe configuration register `CC.AMS` (Arbitration Mechanism Selected) to `001b` (Weighted Round Robin with Urgent Priority Class):
  ```asm
  ; --- Program NVMe CC.AMS register ---
  mov rdi, [nvme_regs_base]
  mov eax, [rdi + 0x14]           ; Read CC
  and eax, 0xFFFFC7FF             ; Mask out CC.AMS (bits 11-13)
  or  eax, 0x00000800             ; Set CC.AMS = 001b (Weighted Round Robin with Urgent Class)
  mov [rdi + 0x14], eax           ; Write CC
  ```

#### 13.5.5 Hardware-Accelerated Write-Zeroes Offloading
Submit NVMe Write Zeroes commands to zero media sectors locally without writing blocks over the PCIe links.
* **Implementation**: Write-zero requests submit NVMe opcode `0x08` (Write Zeroes command) with the target LBA range:
  ```asm
  ; --- NVMe Write Zeroes Command (Opcode 0x08) ---
  mov dword [nvme_sqe.opcode], 0x08 ; Opcode: Write Zeroes
  mov rdx, [target_lba]
  mov [nvme_sqe.lba], rdx
  mov cx, [number_of_blocks]
  mov [nvme_sqe.nblocks], cx
  ; PRP pointers are not written (remains 0) since no host data is sent
  ```

#### 13.5.6 Invariant TSC Latency Profiling
Measure cycle-accurate latency profiling without HPET or OS system clock overhead.
* **Implementation**: The driver reads the Invariant TSC directly before and after operations using the `rdtscp` instruction:
  ```asm
  rdtscp                          ; RAX = low 32-bits TSC, RDX = high 32-bits TSC, RCX = core ID
  shl rdx, 32
  or rax, rdx                     ; RAX = 64-bit absolute cycle stamp
  ```

---

## 14. Failure-Mode & Recovery Policy (FMEA)

A production I/O layer is defined less by its happy path than by having a *specified,
not-panicking response to every failure class*. For each class below the behaviour is
fixed here so no driver improvises its own recovery.

Escalation ladder for device errors: **retry(N) → abort command → reset queue → reset
controller → offline device (mark FDs stale)**. Never jump straight to panic for a device
fault; panic is reserved for corruption of io's own invariants.

| Failure class | Detection | Response | Recoverable |
| :-- | :-- | :-- | :-- |
| Null / bad argument | `guard_null` at entry | return Core-band code | yes |
| Stale handle use | generation mismatch / `FD_STALE` | `IO_ERR_STALE` | yes |
| DMA out-of-memory | alloc returns band code | surface to caller → backpressure | yes |
| Reuse of pinned buffer | pin refcount > 0 | refuse + debug `assert`; caller bug | yes |
| Submission ring full | SPSC producer sees full | `IO_ERR_QFULL` / credit block | yes |
| Command timeout | timeout wheel expiry | escalation ladder (retry→abort→reset) | escalating |
| Media / ECC error | per-command NVMe/ATA status | surface status; optional retry | depends |
| Controller fatal (`CSTS.CFS`) | poll CSTS after submit | controller reset → offline on fail | degrade |
| PCIe correctable error | AER capability | log + counter; continue | yes |
| PCIe uncorrectable / link down | AER + link status | offline device, stale FDs, reclaim | degrade |
| Hot-unplug | PCIe presence event | `ONLINE→OFFLINE`, stale FDs, reclaim | yes |
| Unhandled IRQ vector | catch-all handler | log over serial, continue | yes |
| Spurious IRQ | vector `0xFF` | count, no EOI, continue | yes |
| Double fault (`#DF`) | IST1 handler | structured panic + survive snapshot | no (last resort) |
| NMI (hw error) | IST2 handler | log, attempt graceful halt | depends |
| Machine check (`#MC`) | IST3 (opt) | log MCA banks, offline affected path | depends |
| ACPI table bad checksum | parse-time validation | fall back / halt with milestone | no (boot-fatal) |

Rule: **any response that touches page tables or device state on SMP fans out via IPI**
(reschedule / TLB shootdown), and **any response inside an ISR only sets a flag** — the
heavy recovery runs in a non-ISR context that reaps the flag.

---

## 15. Verification & Invariant Enforcement

Robustness that isn't tested is a claim, not a property. Every module carries a test
obligation, and the invariants that *can* be checked mechanically are enforced at
assemble-time, not left to discipline.

### 15.1 Compile-time struct assertions

Hardware-fixed and cross-file structs assert their size at assembly time. If an offset
drifts, the build fails instead of a driver reading garbage. Place in `io.inc` after each
`struc`:

```asm
%if pci_header_t_size != 64
  %error "pci_header_t size drift — must be 64 bytes"
%endif
%if msix_table_entry_t_size != 16
  %error "msix_table_entry_t size drift — must be 16 bytes"
%endif
%if nvme_regs_t_size != 64
  %error "nvme_regs_t size drift — must be 64 bytes"
%endif
%if msi_cap_t_size != 8
  %error "msi_cap_t size drift — must be 8 bytes"
%endif
%if msix_cap_t_size != 12
  %error "msix_cap_t size drift — must be 12 bytes"
%endif
%if virtio_blk_req_t_size != 16
  %error "virtio_blk_req_t size drift — must be 16 bytes"
%endif
%if tss_t_size    != 104 
  %error "tss_t layout drift — must be 104 bytes (x86-64 hardware-fixed)"
%endif
%if rsdp_t_size   != 36
  %error "rsdp_t layout drift — must be 36 bytes (ACPI 2.0+)"
%endif
%if virtq_desc_size != 16
  %error "virtq_desc must be 16 bytes (virtio spec)"
%endif
%if io_completion_t_size > 64
  %error "io_completion_t exceeds one cache line — false-sharing risk in ISR path"
%endif
%if boot_handoff_t_size != 56
  %error "boot_handoff_t drift — must be 56 bytes"
%endif
%if mem_map_entry_t_size != 24
  %error "mem_map_entry_t size drift — must be 24 bytes"
%endif
%if spsc_ring_t_size != 192
  %error "spsc_ring_t must be 192 bytes (three cache lines; prod/cons on separate lines)"
%endif
%if spsc_ring_t.prod_idx != 64
  %error "spsc_ring_t.prod_idx must sit on cache line 1 (offset 64)"
%endif
%if spsc_ring_t.cons_idx != 128
  %error "spsc_ring_t.cons_idx must sit on cache line 2 (offset 128)"
%endif
%if percpu_t_size != 64
  %error "percpu_t layout drift — must be exactly 64 bytes"
%endif
%if driver_binding_t_size != 20
  %error "driver_binding_t layout drift — must be 20 bytes"
%endif
%if device_t_size != 160
  %error "device_t layout drift — must be 160 bytes"
%endif
%if idt_gate_t_size != 16
  %error "idt_gate_t layout drift — must be 16 bytes"
%endif
%if tss_descriptor_t_size != 16
  %error "tss_descriptor_t layout drift — must be 16 bytes"
%endif
%if acpi_header_t_size != 36
  %error "acpi_header_t layout drift — must be 36 bytes"
%endif
%if interrupt_frame_t_size != 120
  %error "interrupt_frame_t layout drift — must be 120 bytes"
%endif
%if vga_cell_t_size != 2
  %error "vga_cell_t layout drift — must be 2 bytes"
%endif
```

### 15.2 Per-module test obligation

| Layer | Unit (`test/unit/`) | Integration (`test/qemu/`) | Fault (`test/fault/`) |
| :-- | :-- | :-- | :-- |
| `core/iovec` | page-crossing splitter over crafted spans | — | misaligned / zero-len inputs |
| `dma/sg` | PRP list build incl. list-pointer spill | round-trip DMA on virtio | forced page-cross at PRP boundary |
| `async/submit`+`complete` | SPSC full/empty/wrap | end-to-end request | injected reorder before idx bump |
| `error/codes` | encode→decode round-trip, band non-overlap | — | out-of-band value rejected |
| `core/handle` | alloc/free/generation reuse | — | double-free, stale lookup |
| `block/virtio_blk` | status-handshake state machine | sector 0 read (Phase-1 gate) | drop completion IRQ → timeout path |
| `intr/idt` | gate encoding | fires + returns | fault-in-fault → IST1 lands |

### 15.3 Property / fuzz targets

* **iovec splitter**: for any (base, len), the emitted SGL covers exactly [base, base+len)
  with no gap/overlap, every entry within one physical page.
* **PRP builder**: total bytes described == request bytes; entry count matches the
  page-crossing count; list-pointer used iff > 2 entries.
* **SPSC ring**: under an adversarial reordering model, a consumer never observes a slot
  before its payload write is visible (this is what the release/acquire pairing in §16 buys).
* **error band**: every defined code satisfies `IS_ERR`; no valid small handle collides.

### 15.4 The integration gate

§9's Phase-1 assertion is the CI gate that must stay green from first light onward. No
`[hardening]`/`[AI]`/`[SMP]` work merges if it reddens the sector-0-read-echoed-over-serial
path.

---

## 16. Memory-Ordering Appendix (SMP correctness)

x86-64 is TSO (stores don't reorder past stores, loads don't reorder past loads), but two
things still require *explicit* fences: (a) writes to WC/MMIO regions (doorbells,
virtqueue notify) are **not** ordered by TSO, and (b) the compiler/assembler ordering is
irrelevant in hand-asm but the *device's* view is. Every ordering-sensitive site is
enumerated here so no driver omits one.

| Site | Required ordering | Instruction |
| :-- | :-- | :-- |
| Virtqueue submit | descriptors written → **fence** → avail.idx bump → **fence** → notify | `sfence` before idx; `sfence` before notify MMIO write |
| NVMe submit | SQE written → **fence** → SQ tail doorbell | `sfence` before doorbell store |
| Completion consume | read CQ phase tag with **acquire** before reading the entry body | `lfence` after phase-tag load (or load-acquire) |
| SPSC producer | payload store → **release** → publish index | store payload, `sfence`, store index |
| SPSC consumer | load index → **acquire** → read payload | load index, `lfence`, read payload |
| DMA → device | `dma_sync_for_device` (flush) **before** submit | `clflushopt`+`sfence` (x86 non-WB); `dsb` (ARM) |
| Device → DMA | `dma_sync_for_cpu` (invalidate) **after** completion, before CPU read | `mfence`/invalidate (x86); `dsb`+`dc ivac` (ARM) |
| Cross-core page-table edit | mutate PTE → **TLB shootdown IPI** → wait ack | `intr/ipi.asm` + `invlpg` remote |
| Cross-core wakeup | set task runnable → **fence** → reschedule IPI | `sfence` before IPI send |

On AArch64/RISC-V (weakly ordered) the `sfence` sites become `dmb ishst` / `fence w,w`
and the acquire sites become `dmb ish` / `fence r,r`; the *placement* is identical, only
the mnemonic changes. The arch layer (`arch/*/barrier.asm`) provides named macros
(`io_wmb`, `io_rmb`, `io_mb`) so drivers never hardcode a raw fence.

---

## 17. Design Phase — Closed

The mechanisms (§1–§11), the security invariants (§12), the performance invariants (§13),
the failure-response policy (§14), the verification contract (§15), and the ordering proof
(§16) together constitute a complete production-grade *design*. Production-grade *code* is
earned after this: by the Phase-1 gate going green, then by every failure row in §14 being
exercised in `test/fault/` against real drivers.

No further design expansion is warranted — additional robustness now comes from
implementation and test, not specification. Next artifact is source, starting at
`arch/x86_64/portio.asm`.