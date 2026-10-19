# crypto/upqc — Master Unified Post-Quantum Cryptography (PQC) Subsystem

The **`crypto/upqc`** library is the single, authoritative Post-Quantum Cryptography Engine for Tattva OS, consolidating 100% of NIST Post-Quantum Cryptography Standards (ML-DSA, ML-KEM, FALCON, SPHINCS+).

---

## 1. Directory Layout & Module Breakdown

```
crypto/upqc/
├── upqc.inc         ← Master PQC context schema & algorithm IDs
├── dilithium.asm    ← NIST ML-DSA (CRYSTALS-Dilithium Signatures)
├── kyber.asm        ← NIST ML-KEM (CRYSTALS-Kyber Key Encapsulation)
├── falcon.asm       ← NIST FALCON (Fast Fourier Lattice Signatures)
├── sphincs.asm      ← NIST SPHINCS+ (Stateless Hash-based Signatures)
├── README.md        ← Master PQC documentation
└── upqc.asm         ← Master PQC API Dispatcher
```

---

## 2. NIST Post-Quantum Standards Matrix

| Algorithm | Type | NIST Standard | Key Size / Security Level | Module |
| :--- | :--- | :--- | :--- | :--- |
| **Dilithium** | Digital Signature | NIST ML-DSA | ML-DSA-44 / 65 / 87 | `dilithium.asm` |
| **Kyber** | Key Encapsulation | NIST ML-KEM | ML-KEM-512 / 768 / 1024 | `kyber.asm` |
| **FALCON** | Lattice Signature | NIST FALCON | FALCON-512 / 1024 | `falcon.asm` |
| **SPHINCS+** | Hash Signature | NIST SPHINCS+ | SPHINCS+-128f / 256f | `sphincs.asm` |
