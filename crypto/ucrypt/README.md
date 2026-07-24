# crypto/ucrypt — Hyperscale Symmetric & Asymmetric Encryption Subsystem

The **`crypto/ucrypt`** library is the single, authoritative Symmetric, Asymmetric, and Message Authentication Code (MAC) Encryption Subsystem for Tattva OS, matching Linux Kernel 7.x and Google BoringSSL security architecture.

---

## 1. Subsystem Architecture

```
crypto/ucrypt/
├── symmetric/
│   ├── ucrypt.inc             ← Cipher schemas & algorithm IDs
│   ├── aes_gcm.asm            ← Intel AES-NI + PCLMULQDQ AES-GCM AEAD
│   ├── aes_gcm_siv.asm        ← RFC 8452 AES-GCM-SIV Nonce-Misuse-Resistant AEAD (Google BoringSSL)
│   ├── aes_xts.asm            ← AES-XTS Dual-Key uFS Sector Encryption
│   ├── chacha20_poly1305.asm  ← AVX2 SIMD ChaCha20-Poly1305 AEAD
│   ├── xchacha20_poly1305.asm ← XChaCha20-Poly1305 192-bit Extended Nonce AEAD (Google Chrome)
│   ├── aes_cbc.asm            ← AES-CBC with PKCS#7 Padding
│   ├── aes_ctr.asm            ← AES-CTR Counter Mode Streaming Cipher
│   ├── aes_ccm.asm            ← AES-CCM AEAD for Wi-Fi WPA2/WPA3 CCMP
│   └── aes_kw.asm             ← AES Key Wrap / Key Unwrap (RFC 3394)
├── asymmetric/
│   ├── x25519.asm             ← Curve25519 Diffie-Hellman Key Exchange (RFC 7748)
│   ├── curve448.asm           ← X448 High-Security Curve Diffie-Hellman Key Exchange (RFC 7748)
│   ├── ecdh_p256.asm          ← NIST P-256 & secp256k1 ECDH Key Exchange
│   └── rsa_oaep.asm           ← RSA-2048/4096 OAEP Data Encryption
├── mac/
│   ├── hmac.asm               ← Generic HMAC-SHA256 / HMAC-SHA512 MAC (RFC 2104)
│   └── poly1305.asm           ← Standalone 130-bit Poly1305 MAC (RFC 8439)
├── ucrypt_ct_guard.asm        ← Constant-time side-channel protection guard (Bleichenbacher defense)
├── ucrypt_wipe.asm            ← Cold-boot key zeroization & SIMD vector scrubbing (vzeroall)
├── README.md                  ← Master documentation
└── ucrypt.asm                 ← Master Cipher Dispatcher API
```

---

## 2. Hyperscale Security Features

- **Constant-Time Side-Channel Protection Guard (`ucrypt_ct_guard.asm`)**: Zero-branching constant-time memory comparison (`ucrypt_ct_memcmp`) protecting against Lucky Thirteen and Bleichenbacher cache-timing side-channel attacks.
- **Cold-Boot Key Zeroization & Vector Scrubbing (`ucrypt_wipe.asm`)**: Automatic SIMD vector register clearing (`vzeroall`) and stack scrubbing immediately after encryption calls.
- **Nonce-Misuse Resistance (AES-GCM-SIV)**: RFC 8452 Synthetic IV (SIV) guarantees that plaintexts cannot be forged or decrypted even if IV nonces are accidentally reused.
- **Extended Nonce AEAD (XChaCha20-Poly1305)**: 192-bit (24-byte) extended nonce variant eliminating nonce collision risks across petabytes of network traffic.
- **X448 High-Security Key Exchange**: 224-bit security level ($2^{448} - 2^{224} - 1$) for next-generation TLS 1.3 key exchanges.
