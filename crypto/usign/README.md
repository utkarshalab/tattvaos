# crypto/usign — Classical Digital Signature Subsystem

The **`crypto/usign`** library is the Classical Digital Signature Verification Subsystem for Tattva OS, covering **Ed25519, ECDSA P-256 / secp256k1, RSA-PSS**, and signature envelope formats.

*(Note: All Post-Quantum Cryptography algorithms have been consolidated into **`crypto/upqc/`**).*

---

## 1. Directory Layout & Module Breakdown

```
crypto/usign/
├── ed25519/               ← Curve25519 256-bit scalar verification engine ($2^{255}-19$)
├── ecdsa/                 ← NIST P-256 & secp256k1 Jacobian scalar multiplication
├── rsa/                   ← RSA-PSS Montgomery REDC modular exponentiation
├── formats/               ← Signature envelope parsers (Raw, PEM, PKCS#7, UPK)
├── README.md              ← Master documentation
└── usign.asm              ← Master Signature Verification Dispatcher API
```
