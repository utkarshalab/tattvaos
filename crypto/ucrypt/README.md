# crypto/ucrypt — Master Symmetric, Asymmetric & Authenticated Cipher Subsystem

The **`crypto/ucrypt`** library is the single, authoritative Symmetric, Asymmetric, and Message Authentication Code (MAC) Encryption Subsystem for Tattva OS, matching Hyperscale Cloud and Operating System Security Architecture.

---

## 1. Directory Layout & Module Breakdown

```
crypto/ucrypt/
├── symmetric/
│   ├── ucrypt.inc             ← Cipher schemas & algorithm IDs
│   ├── aes_gcm.asm            ← Intel AES-NI + PCLMULQDQ AES-GCM AEAD
│   ├── aes_gcm_4way.asm       ← 4-way parallel AES-GCM high-throughput pipeline (>10 GB/s)
│   ├── aes_gcm_siv.asm        ← RFC 8452 AES-GCM-SIV Nonce-Misuse-Resistant AEAD
│   ├── aes_xts.asm            ← AES-XTS Dual-Key uFS Sector Encryption
│   ├── chacha20_poly1305.asm  ← AVX2 SIMD ChaCha20-Poly1305 AEAD
│   ├── xchacha20_poly1305.asm ← XChaCha20-Poly1305 192-bit Extended Nonce AEAD
│   ├── aes_cbc.asm            ← AES-CBC with PKCS#7 Padding
│   ├── aes_ctr.asm            ← AES-CTR Counter Mode Streaming Cipher
│   ├── aes_ccm.asm            ← AES-CCM AEAD for Wi-Fi WPA2/WPA3 CCMP
│   ├── aes_kw.asm             ← AES Key Wrap / Key Unwrap (RFC 3394)
│   └── aes_kw_ad.asm          ← AES-KWP Key Wrap with Associated Data
├── asymmetric/
│   ├── x25519.asm             ← Curve25519 Diffie-Hellman Key Exchange (RFC 7748)
│   ├── curve448.asm           ← X448 High-Security Curve Diffie-Hellman Key Exchange (RFC 7748)
│   ├── ecdh_p256.asm          ← NIST P-256 & secp256k1 ECDH Key Exchange
│   └── rsa_oaep.asm           ← RSA-2048/4096 OAEP Data Encryption
├── mac/
│   ├── hmac.asm               ← Generic HMAC-SHA256 / HMAC-SHA512 MAC (RFC 2104)
│   ├── kmac.asm               ← KMAC-256 Keccak MAC (NIST SP 800-185)
│   ├── poly1305.asm           ← Standalone 130-bit Poly1305 MAC (RFC 8439)
│   └── poly1305_2way.asm      ← 2-way parallel Poly1305 vector accumulator
├── guards/
│   ├── ct_guard.asm           ← Constant-time side-channel protection guard (Bleichenbacher defense)
│   ├── s2n_guard.asm          ← Formally-verified constant-time key zeroization guard
│   ├── corecrypto_guard.asm   ← Memory barrier key zeroization (volatile cc_clear)
│   └── wipe.asm               ← Cold-boot key zeroization & SIMD vector scrubbing (vzeroall)
├── README.md                  ← Master documentation
└── ucrypt.asm                 ← Master Cipher Dispatcher API
```

---

## 2. Hyperscale Security Features

- **Security Guards Division (`crypto/ucrypt/guards/`)**: Centralized security guards housing side-channel protection, memory barrier key clearing, and cold-boot SIMD scrubbing (`vzeroall`).
- **Nonce-Misuse Resistance (AES-GCM-SIV)**: Synthetic IV (SIV) guarantees that plaintexts cannot be forged or decrypted even if IV nonces are accidentally reused.
- **Extended Nonce AEAD (XChaCha20-Poly1305)**: 192-bit (24-byte) extended nonce variant eliminating nonce collision risks across petabytes of network traffic.
- **X448 High-Security Key Exchange**: 224-bit security level ($2^{448} - 2^{224} - 1$) for next-generation TLS 1.3 key exchanges.
- **KMAC-256 Keccak Engine**: Post-Quantum resistant Message Authentication Code based on Keccak-f[1600] sponge permutation.
