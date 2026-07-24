# ufs — Master Unikernel Encrypted File System & Universal Storage Subsystem

The **`ufs`** library is the single, authoritative, high-performance, crash-resilient 64-bit Assembly Unikernel File System Subsystem for Tattva OS, featuring the native **`uFS Format v1.0`** on-disk layout and multi-distro enterprise capabilities.

---

## 1. Subsystem Directory Layout (34 Modules)

```
ufs/
├── ufs.inc                     ← Superblock, Inode, Extents, AGs & Allocation schemas
├── vfs/
│   ├── vfs.asm                 ← Virtual File System Layer (POSIX open, read, write, close, seek, fstat)
│   ├── overlayfs.asm           ← OverlayFS Union Mount Engine (Multi-layer container snapshotting)
│   ├── ufs_clone.asm           ← APFS / ReFS Zero-Cost O(1) Instant File & Directory Cloning
│   ├── ufs_snapshot.asm        ← Frozen Root CoW B-Tree File System Snapshots & Rollback
│   ├── ufs_pseudofs.asm        ← Synthetic /proc and /sys Pseudo Filesystem Engine
│   └── compat/
│       ├── fat32.asm           ← FAT32 & exFAT External USB Flash Drive Reader/Writer
│       ├── ntfs.asm            ← NTFS External Windows Drive Reader/Writer
│       └── ext4_compat.asm     ← ext2/ext3/ext4 External Linux Partition Reader/Writer
├── cache/
│   ├── ufs_pagecache.asm       ← Zero-Copy DMA Ring Buffer Page Cache
│   ├── ufs_arc.asm             ← ZFS-grade Adaptive Replacement Cache (ARC / L2ARC) with LRU/LFU lists
│   ├── ufs_dax.asm             ← Direct Access (DAX) Memory-Mapped File I/O Engine
│   ├── ufs_dedup.asm           ← BLAKE3 Block-Level Deduplication Engine
│   └── ufs_tmpfs.asm           ← Linux tmpfs Ultra-Fast In-Memory RAMDisk Engine
├── crypto/
│   ├── ufs_crypto.asm          ← Native AES-256-XTS sector encryption (wired to aes_xts.asm)
│   ├── ufs_pqc.asm             ← Post-Quantum Hybrid Disk Key Encapsulation (ML-KEM-1024 + AES-XTS)
│   ├── ufs_fscrypt.asm         ← ext4 fscrypt per-directory transparent encryption
│   ├── ufs_verity.asm          ← Linux dm-verity Merkle Tree Tamper-Proof Integrity Engine
│   └── ufs_vault.asm           ← Per-Directory Encrypted Vault Key Manager (Argon2id + AES-KWP)
├── btree/
│   ├── ufs_cow_btree.asm       ← Btrfs CoW B-tree index with BLAKE3 bit-rot checksums
│   └── ufs_alloc_groups.asm    ← XFS Allocation Groups (AGs) & ZNS-aware block allocator
├── extents/
│   └── ufs_extents.asm         ← ext4 Extents Tree for contiguous multi-gigabyte block mapping
├── compress/
│   ├── ufs_compress.asm       ← Real-time inline LZ4 & ZSTD compression engine
│   └── erofs.asm               ← EROFS Immutable Compressed Boot Partition reader
├── cluster/
│   ├── ufs_cluster.asm         ← Ceph / GlusterFS CRUSH Distributed Cloud Storage Router
│   └── ufs_erasure.asm         ← Reed-Solomon (k+m) Erasure Coding Cloud Redundancy Engine
├── limits/
│   └── ufs_quota.asm           ← Storage Quota Engine (Hard/Soft block & inode limits)
├── drivers/
│   ├── nvme.asm                ← PCIe NVMe 1.4 Command Queue storage driver (with TRIM)
│   ├── nvme_zns.asm            ← NVMe ZNS (Zoned Namespaces) Controller driver
│   ├── usb_storage.asm         ← USB 3.0 / 2.0 Mass Storage (BOT/UASP) Pendrive driver
│   ├── ahci.asm                ← SATA Hard Disk Drive (HDD) & SATA SSD AHCI driver
│   ├── sdhci.asm               ← SD Card & eMMC 5.1 Flash Storage driver (Packed Commands)
│   ├── virtio_blk.asm          ← Paravirtualized VirtIO-Block Cloud Hypervisor driver
│   └── nvme_of.asm             ← NVMe-oF (NVMe over Fabrics) Cloud Block Storage driver
├── journal/
│   └── ufs_journal.asm         ← ext4 Fast-Commit & Write-Ahead Logging (WAL) transaction journal
├── tests/
│   └── ufs_fuzz.asm            ← Power-Fail WAL Journal Crash-Consistency Fuzzing Test Harness
├── README.md                   ← Master Subsystem Documentation
└── ufs.asm                     ← Master uFS Dispatcher API (ufs_init, ufs_mount)
```

---

## 2. On-Disk Data Structure Bit Layouts (`uFS Format v1.0`)

### 2.1 Custom 512-Byte Superblock Schema (`ufs_superblock_t`)
- `0x00 - 0x07` (8 Bytes) : Magic Number `0x5546533230323630` (`"UFS20260"`)
- `0x08 - 0x0B` (4 Bytes) : Version Number `0x0100` (v1.0)
- `0x0C - 0x0F` (4 Bytes) : Logical Block Size (4096 Bytes)
- `0x10 - 0x17` (8 Bytes) : Total Storage Blocks Count ($N_{\text{blocks}}$)
- `0x18 - 0x1F` (8 Bytes) : Free Storage Blocks Count
- `0x20 - 0x27` (8 Bytes) : Total Inodes Count
- `0x28 - 0x2F` (8 Bytes) : Free Inodes Count
- `0x30 - 0x37` (8 Bytes) : Root Directory Inode ID (Inode 1)
- `0x38 - 0x3F` (8 Bytes) : WAL Journal Block Start ID
- `0x40 - 0x43` (4 Bytes) : Allocation Groups Count ($N_{\text{AG}}$)
- `0x44 - 0x47` (4 Bytes) : Feature Flags (Encryption, Compression, CoW, Verity, PQC)
- `0x48 - 0x57` (16 Bytes): 128-bit Disk UUID
- `0x58 - 0x97` (64 Bytes): Volume Label String (`"TATTVA_ROOTFS"`)
- `0x98 - 0x1FF`(360 Bytes): Reserved Expansion Space

### 2.2 Custom 128-Byte Inode Schema (`ufs_inode_t`)
- `0x00 - 0x07` (8 Bytes) : 64-bit Inode ID
- `0x08 - 0x0B` (4 Bytes) : File Type & Permission Flags (Regular, Directory, Symlink, CoW, Encrypted)
- `0x0C - 0x0F` (4 Bytes) : Owner UID & GID
- `0x10 - 0x17` (8 Bytes) : File Size in Bytes
- `0x18 - 0x1F` (8 Bytes) : Allocated 4KB Block Count
- `0x20 - 0x27` (8 Bytes) : Access Timestamp `atime` (POSIX nanoseconds)
- `0x28 - 0x2F` (8 Bytes) : Modification Timestamp `mtime`
- `0x30 - 0x37` (8 Bytes) : Status Change Timestamp `ctime`
- `0x38 - 0x77` (64 Bytes): 8 Direct Block Pointers (32KB Inline Data Payload)
- `0x78 - 0x7F` (8 Bytes) : Extents Tree Root Pointer
- `0x80 - 0x9F` (32 Bytes): BLAKE3 256-bit Data Integrity Checksum

---

## 3. Detailed Hardware & Algorithm Specifications

### 3.1 Hardware AES-256-XTS Sector Encryption Engine (`crypto/ufs_crypto.asm`)
- **Tweak Polynomial**: Galois Field $GF(2^{128})$ primitive polynomial $P(x) = x^{128} + x^7 + x^2 + x + 1$.
- **Tweak Computation**: $T_j = \text{AES-ECB}(K_2, j)$ where $j$ is the 512-byte physical sector index.
- **Galois Multiplication**: $T_{j+1} = (T_j \ll 1) \oplus ((T_j \gg 127) \cdot 0x87)$.
- **Encryption Step**: $C = \text{AES-256-ECB}(K_1, P \oplus T_j) \oplus T_j$.

### 3.2 Post-Quantum Hybrid Disk Encryption (`crypto/ufs_pqc.asm`)
- **ML-KEM-1024 KEM Encapsulation**: Uses NIST ML-KEM-1024 (FIPS 203) from `crypto/upqc/kyber.asm` to encapsulate master disk keys, establishing quantum-resistant confidentiality against "harvest now, decrypt later" threats.

### 3.3 BLAKE3 Bit-Rot Self-Healing Engine (`btree/ufs_cow_btree.asm`)
- **Checksum Routine**: Every 4KB storage block is hashed with BLAKE3 (`crypto/uhash/blake3/blake3.asm`).
- **Bit-Rot Verification**: Upon sector read, `ufs_cow_btree_verify()` recomputes the 256-bit BLAKE3 digest.
- **Automatic Repair**: If a mismatch occurs due to silent hardware corruption, `ufs` retrieves the previous Copy-on-Write (CoW) B-tree parent block and automatically overwrites/repairs the corrupted sector on disk.

### 3.4 BLAKE3 Block-Level Deduplication Engine (`cache/ufs_dedup.asm`)
- **In-Memory Hash Table**: Maintains an in-memory hash index mapping 256-bit BLAKE3 digests to physical block pointers.
- **Implicit Deduplication**: When writing duplicate blocks, `ufs_dedup` reuses existing physical block pointers and increments reference counters without writing duplicate bytes to disk.

### 3.5 ZFS-Grade Adaptive Replacement Cache Engine (`cache/ufs_arc.asm`)
- **Dual List Architecture**: Maintains $T_1$ (Recent LRU pages) and $T_2$ (Frequent LFU pages).
- **Adaptation Math**: Adjusts target cache size $p$ dynamically based on cache miss penalties in ghost lists $B_1$ and $B_2$:
  - On miss in $B_1$: $p = \min(p + \max(1, |B_2| / |B_1|), c)$.
  - On miss in $B_2$: $p = \max(p - \max(1, |B_1| / |B_2|), 0)$.

### 3.6 Direct Access (DAX) Memory-Mapped Engine (`cache/ufs_dax.asm`)
- **Zero-Copy Direct Mapping**: Maps RAMDisk (`ufs_tmpfs.asm`) or NVDIMM physical memory blocks directly into the application's single Ring 0 address space, completely bypassing page cache copies for database workloads.

### 3.7 XFS Allocation Groups Engine (`btree/ufs_alloc_groups.asm`)
- **Parallel Core Allocation**: Divides disk volume into $N_{\text{AG}}$ independent Allocation Groups (AG 0..AG $N-1$).
- **Lock-Free Concurrency**: Each CPU core claims a distinct AG allocator lock, preventing CPU bus contention during heavy parallel I/O workloads.

### 3.8 macOS APFS / ReFS Zero-Cost $O(1)$ File Clones (`vfs/ufs_clone.asm`)
- **Snapshot Math**: Cloning a file creates a new Inode that shares data block pointers with the parent.
- **Reference Counting**: Increments block reference counts. On subsequent writes, CoW allocates a new physical block, keeping unmodified blocks shared.

### 3.9 Reed-Solomon Erasure Coding Cloud Engine (`cluster/ufs_erasure.asm`)
- **$k+m$ Redundancy**: Shards data blocks into $k$ data shards and $m$ parity shards across Ceph/GlusterFS cloud storage nodes using Galois Field $GF(2^8)$ Vandermonde matrix multiplication.

---

## 4. Storage Device Driver Suite (`ufs/drivers/`)

| Driver Module | Target Hardware Medium | Interface & Queue Architecture |
| :--- | :--- | :--- |
| **`nvme.asm`** | PCIe Gen 4/5 NVMe M.2 SSDs | NVMe 1.4 Admin Queue & 64k Entry I/O Submission/Completion Queues (with TRIM) |
| **`nvme_zns.asm`** | Enterprise Zoned Namespaces (ZNS) | Sequential zone write allocation eliminating SSD FTL garbage collection overhead |
| **`usb_storage.asm`** | USB Pendrives & External Disks | USB 3.0 Mass Storage Bulk-Only Transport (BOT) & UASP Protocol |
| **`ahci.asm`** | SATA HDDs & SATA SSDs | AHCI 1.3 Command List & FIS Receive Engine |
| **`ufs_tmpfs.asm`** | In-Memory RAMDisks | Lock-free contiguous RAM memory page allocator |
| **`sdhci.asm`** | SD Cards & eMMC Flash | SDHCI Host Controller Command Register & ADMA2 Descriptor Ring (Packed Commands) |
| **`virtio_blk.asm`** | QEMU / KVM VirtIO Cloud Storage | Paravirtualized Virtqueue Ring Buffers for Unikernel Cloud VMs |
| **`nvme_of.asm`** | Remote Cloud Block Storage | NVMe over Fabrics RDMA (RoCEv2) Queue Pair Protocol |

---

## 5. Explicit Exclusion of `io_uring` & Unikernel Architecture

- **`io_uring` Banned**: `io_uring` was created for monolithic Linux kernels to reduce Ring 3 to Ring 0 system call context switching overhead. In Tattva Unikernel, Application and Kernel execute in a **single unified Ring 0 address space**.
- **Direct PCIe NVMe DMA Rings**: Function calls execute in zero cycles without syscall shims. PCIe NVMe hardware Submission/Completion (SQ/CQ) DMA queues interface directly with driver memory in Ring 0.
- **Unikernel Single-User Performance Mode (`CONFIG_UNIKERNEL_SINGLE_USER`)**: Strips multi-user UID/GID checks and multi-tenant locks for 100% max execution speed.

---

## 6. Security & Executable Integration

- **Transparent Directory Encryption (`crypto/ufs_fscrypt.asm`)**: Implements ext4 `fscrypt` policies using XChaCha20-Poly1305 (192-bit extended nonce) and AES-256-GCM.
- **Executable Validation (`lib/ufile/`)**: Every executable binary read from `ufs` is validated through `lib/ufile/signatures/exec_signatures.asm` before kernel memory loading, guaranteeing zero unauthenticated code execution.
