# crypto/ucrypt — Symmetric & Asymmetric Encryption Subsystem

The **`crypto/ucrypt`** library is the primary Symmetric, Asymmetric, and Message Authentication Code (MAC) Encryption Subsystem for Tattva OS.

---

## 1. Directory Layout & Module Breakdown

```
crypto/ucrypt/
├── symmetric/
│   ├── ucrypt.inc             ← Cipher schemas & algorithm IDs
│   ├── aes_gcm.asm            ← Intel AES-NI + PCLMULQDQ AES-GCM AEAD
│   ├── aes_xts.asm            ← AES-XTS Dual-Key uFS Sector Encryption
│   ├── chacha20_poly1305.asm  ← AVX2 SIMD ChaCha20-Poly1305 AEAD
│   ├── aes_cbc.asm            ← AES-CBC with PKCS#7 Padding
│   ├── aes_ctr.asm            ← AES-CTR Counter Mode Streaming Cipher
│   ├── aes_ccm.asm            ← AES-CCM AEAD for Wi-Fi WPA2/WPA3 CCMP & Bluetooth LE
│   └── aes_kw.asm             ← AES Key Wrap / Key Unwrap (RFC 3394)
├── asymmetric/
│   ├── x25519.asm             ← Curve25519 Diffie-Hellman Key Exchange (RFC 7748)
│   ├── ecdh_p256.asm          ← NIST P-256 & secp256k1 ECDH Key Exchange
│   └── rsa_oaep.asm           ← RSA-2048/4096 OAEP Data Encryption
├── mac/
│   ├── hmac.asm               ← Generic HMAC-SHA256 / HMAC-SHA512 MAC (RFC 2104)
│   └── poly1305.asm           ← Standalone 130-bit Poly1305 MAC (RFC 8439)
├── README.md                  ← Master documentation
└── ucrypt.asm                 ← Master Cipher Dispatcher API
```

---

## 2. Supported Standards & Hardware Acceleration

- **Intel AES-NI Acceleration**: Dedicated hardware instructions (`aesenc`, `aesenclast`, `aeskeygenassist`) for 14-round AES-256 encryption.
- **PCLMULQDQ Hardware Carryless Multiplication**: Hardware 128-bit GHASH evaluation for AES-GCM AEAD.
- **AVX2 Vectorization**: 256-bit SIMD vectorization for ChaCha20 stream generation.
- **RFC 7748**: X25519 Montgomery curve scalar multiplication for TLS 1.3 key exchange.
- **RFC 3394**: NIST SP 800-38F Key Wrap specification for protecting stored keys.
