# lib/urand — Hyperscale Hardware TRNG & Fortuna CSPRNG Subsystem

The **`lib/urand`** library is the single, authoritative Cryptographically Secure Pseudo-Random Number Generator (CSPRNG) and True Random Number Generator (TRNG) subsystem for Tattva OS. It combines hardware silicon entropy sources, CPU execution timing jitter, a 32-pool Fortuna accumulator, NIST SP 800-90B online health monitors, and ChaCha20/AES-CTR-DRBG stream generators with automatic key erasure for forward secrecy.

---

## 1. Subsystem Architecture

```
                                  +-----------------------+
                                  | HARDWARE TRNG SOURCES |
                                  +-----------------------+
                                              |
                   +--------------------------+--------------------------+
                   |                          |                          |
                   v                          v                          v
          +------------------+       +------------------+       +------------------+
          | RDRAND / RDSEED  |       |   RDTSC JITTER   |       |    IRQ JITTER    |
          | (sources/rdrand) |       | (sources/jitter) |       | (sources/irq.asm)|
          +------------------+       +------------------+       +------------------+
                   |                          |                          |
                   +--------------------------+--------------------------+
                                              |
                                              v
                              +-------------------------------+
                              |  NIST SP 800-90B HEALTH MONITOR|
                              |  - Repetition Count Test (RCT)|
                              |  - Adaptive Proportion (APT)  |
                              |   (health/entropy_health.asm) |
                              +-------------------------------+
                                              |
                                              v
                              +-------------------------------+
                              | FORTUNA 32-POOL ACCUMULATOR   |
                              | (P0, P1, P2 ... P31)          |
                              | (pools/fortuna_pools.asm)     |
                              +-------------------------------+
                                              | SHA-256 Reseed
                                              v
                              +-------------------------------+
                              |    CSPRNG STREAM GENERATORS   |
                              | - ChaCha20 20-Round (Default) |
                              | - NIST AES-256 CTR-DRBG       |
                              | (generators/chacha20_rng.asm) |
                              +-------------------------------+
                                              |
                        +---------------------+---------------------+
                        |                                           |
                        v                                           v
         +-----------------------------+             +-----------------------------+
         | LOCK-FREE PER-CPU BUFFERS   |             |  KEY ERASURE & SCRUBBING    |
         | Dedicated 4KB buffer (GS)   |             |  Scrubs stack scratch       |
         | (urand_percpu.asm)          |             |  (urand_wipe.asm)           |
         +-----------------------------+             +-----------------------------+
```

---

## 2. Directory Layout & Module Breakdown

```
lib/urand/
├── sources/
│   ├── rdrand.asm             ← Intel RDRAND & RDSEED hardware instruction reader
│   ├── jitter.asm             ← CPU execution timing jitter entropy accumulator
│   └── interrupt_entropy.asm  ← Hardware IRQ packet arrival & timer tick harvester
├── health/
│   └── entropy_health.asm     ← NIST SP 800-90B Continuous Hardware Health Monitor
├── pools/
│   └── fortuna_pools.asm      ← Fortuna 32-Pool Entropy Accumulator
├── generators/
│   ├── chacha20_rng.asm       ← ChaCha20 20-round CSPRNG with Forward Secrecy
│   └── aes_ctr_drbg.asm       ← NIST SP 800-90A AES-256 CTR-DRBG generator
├── tests/
│   ├── test_rdrand.asm        ← RDRAND & RDSEED hardware verification test
│   ├── test_jitter.asm        ← CPU clock jitter accumulation test
│   ├── test_fortuna.asm       ← Fortuna 32-pool distribution test
│   ├── test_health.asm        ← NIST SP 800-90B RCT stuck-bit detection test
│   ├── test_chacha20_rng.asm  ← ChaCha20 stream generator & forward secrecy test
│   └── test_aes_drbg.asm      ← NIST SP 800-90A AES-256 CTR-DRBG test
├── urand_percpu.asm           ← Lock-Free Per-CPU Core Random Buffers (GS-base)
├── urand_wipe.asm             ← Automatic Zeroization & Memory Scrubbing
├── urand.inc                  ← Master CSPRNG Schemas & Constants
└── urand.asm                  ← Master Entropy Manager & CSPRNG API Dispatcher
```

---

## 3. Mathematical & Algorithmic Specifications

### 3.1 Fortuna 32-Pool Scheduling
Entropy samples from hardware sources are distributed round-robin across 32 independent pools $P_0, P_1, \dots, P_{31}$. On reseed $N$, pool $P_i$ is included in the SHA-256 key update if and only if $2^i \mid N$:

$$K_{\text{new}} = \text{SHA-256}\left(K_{\text{old}} \parallel \text{Pools}(N)\right) \quad \text{where } \text{Pools}(N) = \sum_{i: 2^i \mid N} P_i$$

### 3.2 NIST SP 800-90B Health Monitoring
- **Repetition Count Test (RCT)**: Verifies that consecutive samples $S_k \neq S_{k-1}$. If $S_k = S_{k-1}$ exceeds 3 consecutive samples, the source is flagged as `URAND_HEALTH_FAILED` and quarantined.
- **Adaptive Proportion Test (APT)**: Monitors sample window frequencies to detect statistical bias or thermal drift in silicon TRNG gates.

### 3.3 Forward Secrecy & Key Erasure
Immediately after generating an $L$-byte random block, the first 32 bytes of the internal 256-bit CSPRNG key state are overwritten with fresh random bytes derived from the block:

$$K_{t+1} = \text{ChaCha20-Block}_0(K_t)$$

This guarantees that an attacker who compromises kernel memory at time $T$ can **never** recover previous keys $K_{T-1}$ or past random outputs.

---

## 4. API Reference

### `urand_init`
Initializes global CSPRNG state, resets counters, and performs initial hardware entropy harvest.
- **Input**: None
- **Output**: `RAX = 1` on success

### `urand_reseed`
Harvests RDRAND, RDSEED, CPU jitter, and feeds Fortuna pools to generate a fresh 256-bit key.
- **Input**: None
- **Output**: `RAX = 1`

### `urand_get_bytes`
Generates $N$ cryptographically secure random bytes into caller buffer.
- **Input**:
  - `RDI`: Output Buffer Pointer
  - `RSI`: Output Length in bytes
- **Output**: `RAX`: Total bytes generated

---

## 5. Verification & Testing

Run all unit tests:
```bash
make -C boot
```
The test suite validates RDRAND availability, jitter deltas, Fortuna pool distribution, RCT health monitors, and ChaCha20 key erasure forward secrecy.
