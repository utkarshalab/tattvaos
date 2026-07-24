# crypto/ucrypt — Master Symmetric, Asymmetric & Authenticated Cipher Subsystem

The **`crypto/ucrypt`** library is the single, authoritative Symmetric, Asymmetric, and Message Authentication Code (MAC) Encryption Subsystem for Tattva OS, matching Aerospace and Military-Grade Security Architecture.

---

## 1. Directory Layout & Module Breakdown (32 Modules)

```
crypto/ucrypt/
├── symmetric/
│   ├── ucrypt.inc             ← Cipher schemas & algorithm IDs
│   ├── aes_gcm.asm            ← Intel AES-NI + PCLMULQDQ AES-GCM AEAD
│   ├── aes_gcm_4way.asm       ← 4-way parallel AES-GCM pipeline (>10 GB/s)
│   ├── aes_gcm_avx512.asm     ← AVX-512 8-way parallel AES-GCM pipeline (400 Gbps)
│   ├── aes_gcm_siv.asm        ← RFC 8452 AES-GCM-SIV Nonce-Misuse-Resistant AEAD
│   ├── aes_ocb3.asm           ← RFC 7253 AES-OCB3 Single-Pass AEAD (2x GCM speed)
│   ├── aes_xts.asm            ← AES-XTS Dual-Key uFS Sector Encryption
│   ├── sm4_gcm.asm            ← SM4-GCM 128-bit Block Cipher AEAD
│   ├── aria_gcm.asm           ← ARIA-GCM 128/256-bit Block Cipher AEAD
│   ├── camellia_gcm.asm       ← Camellia-GCM 128/256-bit Block Cipher AEAD
│   ├── chacha20_poly1305.asm  ← AVX2 SIMD ChaCha20-Poly1305 AEAD
│   ├── xchacha20_poly1305.asm ← XChaCha20-Poly1305 192-bit Extended Nonce AEAD
│   ├── aes_cbc.asm            ← AES-CBC with PKCS#7 Padding
│   ├── aes_ctr.asm            ← AES-CTR Counter Mode Streaming Cipher
│   ├── aes_ccm.asm            ← AES-CCM AEAD for Wi-Fi WPA2/WPA3 CCMP
│   ├── aes_kw.asm             ← AES Key Wrap / Key Unwrap (RFC 3394)
│   └── aes_kw_ad.asm          ← AES-KWP Key Wrap with Associated Data
├── asymmetric/
│   ├── x25519.asm             ← Curve25519 Diffie-Hellman Key Exchange (RFC 7748)
│   ├── curve448.asm           ← X448 High-Security Curve Key Exchange (RFC 7748)
│   ├── ed448.asm              ← Ed448 Goldilocks High-Security Signatures (RFC 8032)
│   ├── ecdh_p256.asm          ← NIST P-256 & secp256k1 ECDH Key Exchange
│   ├── rsa_oaep.asm           ← RSA-2048/4096 OAEP Data Encryption
│   ├── bip32_hdkey.asm        ← BIP-32 / SLIP-0010 Hierarchical Deterministic Key Engine
│   └── secp256k1_schnorr.asm  ← BIP-0340 Schnorr Signature & Key Engine
├── mac/
│   ├── hmac/
│   │   └── hmac.asm           ← Generic HMAC-SHA256 / HMAC-SHA512 MAC (RFC 2104)
│   ├── kmac/
│   │   └── kmac.asm           ← KMAC-256 Keccak MAC (NIST SP 800-185)
│   ├── cmac/
│   │   └── cmac.asm           ← AES-CMAC Cipher-based MAC (NIST SP 800-38B)
│   ├── vmac/
│   │   └── vmac.asm           ← VMAC Fast 64-bit Vector MAC (RFC 5664)
│   └── poly1305/
│       ├── poly1305.asm       ← Standalone 130-bit Poly1305 MAC (RFC 8439)
│       └── poly1305_2way.asm  ← 2-way parallel Poly1305 vector accumulator
├── guards/
│   ├── ct_guard.asm           ← Constant-time side-channel protection guard (Bleichenbacher defense)
│   ├── s2n_guard.asm          ← Formally-verified constant-time key zeroization guard
│   ├── memory_barrier_guard.asm ← Volatile memory barrier key zeroization (mfence)
│   └── wipe.asm               ← Cold-boot key zeroization & SIMD vector scrubbing (vzeroall)
├── ucrypt_post.asm            ← FIPS 140-3 Power-On Self-Test (POST) & KAT engine
├── README.md                  ← Master documentation
└── ucrypt.asm                 ← Master Cipher Dispatcher API
```

---

## 2. Hyperscale Security Features

- **FIPS 140-3 Power-On Self-Test (`ucrypt_post.asm`)**: Automatically executes NIST Known-Answer Tests (KAT) for AES-GCM, AES-XTS, ChaCha20-Poly1305, X25519, and Poly1305 during kernel boot.
- **AVX-512 8-Way Pipeline (`aes_gcm_avx512.asm`)**: 512-bit ZMM vector processing using `vaesenc` and `vpclmulqdq` achieving 400 Gbps network encryption.
- **RFC 7253 AES-OCB3 Single-Pass AEAD (`aes_ocb3.asm`)**: Single-pass AEAD mode doubling GCM throughput.
- **BIP-32 & BIP-0340 HD Key & Schnorr Suite (`bip32_hdkey.asm`, `secp256k1_schnorr.asm`)**: Hierarchical deterministic key tree derivation and Schnorr batch signatures.
- **Goldilocks Ed448 Signature Engine (`ed448.asm`)**: High-security 224-bit security level signature engine.
