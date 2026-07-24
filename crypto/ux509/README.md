# crypto/ux509 — Hyperscale X.509 PKI Certificate Subsystem

The **`crypto/ux509`** library is the single, authoritative Public Key Infrastructure (PKI) Certificate Engine for Tattva OS, covering 100% of Web PKI RFC standards (**RFC 5280, RFC 6125, RFC 6960, RFC 6962, RFC 2986, RFC 7468, RFC 5912**).

---

## 1. Subsystem Architecture

```
                                  +-----------------------+
                                  |   PEM / DER INPUT     |
                                  +-----------------------+
                                              |
                                              v
                              +-------------------------------+
                              | PEM DECODER & ASN.1 TLV READER|
                              | - Base64 PEM Strip            |
                              | - Multi-byte length (0x81/82) |
                              | (ux509_asn1.asm)              |
                              +-------------------------------+
                                              |
                                              v
                              +-------------------------------+
                              | ASN.1 RECURSION GUARD         |
                              | Max Nesting Depth Limit = 16  |
                              | (ux509_sanitize.asm)          |
                              +-------------------------------+
                                              |
                                              v
                              +-------------------------------+
                              | CERTIFICATE FIELD EXTRACTOR   |
                              | - Serial, Dates, PubKey, DN   |
                              | - SHA-256 Thumbprint Hashing  |
                              | (ux509_parse.asm)             |
                              +-------------------------------+
                                              |
                   +--------------------------+--------------------------+
                   |                          |                          |
                   v                          v                          v
          +------------------+       +------------------+       +--------------------+
          | SAN DOMAIN MATCH |       | EKU POLICY CHECK |       | PATH LEN BUDGET    |
          | RFC 6125 Wildcard|       | (serverAuth)     |       | Constraint check   |
          | (ux509_san_match)|       | (ux509_policy.asm|       | (ux509_path.asm)   |
          +------------------+       +------------------+       +--------------------+
                   |                          |                          |
                   +--------------------------+--------------------------+
                                              |
                                              v
                              +-------------------------------+
                              | CERTIFICATE CHAIN VALIDATOR   |
                              | Root CA -> Inter CA -> Server |
                              | Verifies via `usign` API      |
                              | (ux509_chain.asm)             |
                              +-------------------------------+
```

---

## 2. Directory Layout & Module Breakdown

```
crypto/ux509/
├── ux509.inc                  ← Context schema, OID constants & policy flags
├── ux509_oid.asm              ← Binary ASN.1 OID matcher & lookup registry
├── ux509_asn1.asm             ← ASN.1 DER Tag-Length-Value (TLV) reader & PEM decoder
├── ux509_sanitize.asm         ← ASN.1 stack-overflow, depth limit & length bounds checker
├── ux509_parse.asm            ← X.509 v3 Certificate field extractor
├── ux509_ext.asm              ← Extensions parser (SAN hostnames, Basic Constraints)
├── ux509_san_match.asm        ← RFC 6125 Wildcard domain & IP matching engine
├── ux509_policy.asm           ← Extended Key Usage (EKU) policy validator
├── ux509_path.asm             ← Path length constraint & hierarchy budget validator
├── ux509_time.asm             ← UTCTime / GeneralizedTime parser with 5-min clock-skew window
├── ux509_crl.asm              ← Certificate Revocation List (CRL) 16-byte serial checker
├── ux509_ocsp.asm             ← RFC 6960 OCSP Stapling Response reader & validator
├── ux509_aia.asm              ← Authority Information Access (AIA) extension parser
├── ux509_name_constraints.asm ← RFC 5280 Permitted & Excluded domain tree name constraints
├── ux509_sct.asm              ← RFC 6962 Certificate Transparency (CT) SCT verifier
├── ux509_fingerprint.asm      ← SHA-256 certificate thumbprint & public key pinning engine
├── ux509_key_match.asm        ← Certificate public key vs private keypair validator
├── ux509_trust_store.asm      ← Unikernel Root CA Trust Store manager (Dynamic registration)
├── ux509_self_signed.asm      ← Self-Signed Root Certificate Auto-Detector
├── ux509_name_norm.asm        ← Canonical DN string normalizer & case-insensitive matcher
├── ux509_csr.asm              ← PKCS#10 Certificate Signing Request (CSR) parser & generator
├── ux509_pqc_cert.asm         ← Dual-signature PQC hybrid cert parser (ECDSA + Dilithium)
├── ux509_chain.asm            ← Chain of trust validator (Root CA -> Inter. CA -> Server Cert)
└── ux509.asm                  ← Master X.509 PKI Dispatcher API
```

---

## 3. Technical Specifications & RFC Compliance Matrix

| RFC Specification | Domain | Implementation Module |
| :--- | :--- | :--- |
| **RFC 5280** | X.509 v3 Certificate & CRL Profile | `ux509_parse`, `ux509_ext`, `ux509_crl`, `ux509_path` |
| **RFC 6125** | Domain Service Identity Matching | `ux509_san_match.asm` |
| **RFC 6960** | Online Certificate Status Protocol (OCSP) | `ux509_ocsp.asm` |
| **RFC 6962** | Certificate Transparency (CT) Log SCT | `ux509_sct.asm` |
| **RFC 2986** | PKCS#10 Certificate Request (CSR) | `ux509_csr.asm` |
| **RFC 7468** | PEM ASCII Text Encodings | `ux509_asn1.asm` |
| **RFC 5912** | ASN.1 DER Modules & Encoding Rules | `ux509_asn1.asm`, `ux509_sanitize.asm` |

---

## 4. Master Data Container Schema (`ux509_cert_t`)

Aligned to **512 bytes** (L1 Cache Line Aligned):

```asm
struc ux509_cert_t
    .version        resd 1          ; +000: X.509 Version (3 = v3)
    .sig_algo       resd 1          ; +004: Signature Algo ID (Ed25519, ECDSA_P256, RSA...)
    .serial         resb 16         ; +008: 16-byte Serial Number
    .not_before     resq 1          ; +024: 64-bit Unix Timestamp (Validity start)
    .not_after      resq 1          ; +032: 64-bit Unix Timestamp (Validity expiry)
    .pubkey_algo    resd 1          ; +040: Public Key Algo ID
    .pubkey_ptr     resq 1          ; +044: Pointer to extracted Public Key
    .pubkey_len     resd 1          ; +052: Public Key size in bytes
    .issuer_str     times 64 db 0   ; +056: Sanitized ASCII Issuer string
    .subject_str    times 64 db 0   ; +120: Sanitized ASCII Subject string
    .san_domain     times 64 db 0   ; +184: Primary SAN Domain Name (e.g. "*.tattva.os")
    .fingerprint    resb 32         ; +248: 32-byte SHA-256 Certificate Thumbprint
    .is_ca          resd 1          ; +280: 1 if CA certificate, 0 if End-Entity
    .is_self_signed resd 1          ; +284: 1 if Self-Signed Root CA
    .path_len_limit resd 1          ; +288: Max intermediate path length constraint
    .eku_flags      resd 1          ; +292: Extended Key Usage flags (serverAuth...)
    .flags          resd 1          ; +296: Security & Validation Flags
    .sig_ptr        resq 1          ; +300: Pointer to raw Signature bytes
    .sig_len        resd 1          ; +308: Raw Signature length
    .reserved       resq 25         ; +312..+512: L1 Cache Line Padding
endstruc
```

---

## 5. API Reference & Register Conventions

### `ux509_init`
Initializes X.509 PKI Subsystem and pre-loads Root CA Trust Store.
- **Input**: None
- **Output**: `RAX = 1`

### `ux509_parse_cert`
Parses DER binary certificate into `ux509_cert_t` container and computes 32-byte SHA-256 thumbprint.
- **Input**: `RDI`: DER Buffer, `RSI`: DER Length, `RDX`: Target `ux509_cert_t` Pointer
- **Output**: `RAX = 1` on success

### `ux509_verify_cert`
Parses DER / PEM certificate and validates timestamps, EKU policies, and domain matching.
- **Input**: `RDI`: Cert Buffer, `RSI`: Cert Length, `RDX`: Target Domain String, `RCX`: Unix Timestamp
- **Output**: `RAX = 1` if valid, `0` if expired or invalid

### `ux509_verify_chain`
Validates certificate chain of trust from Root CA to Intermediate CA to Server Cert using **`usign`** digital signatures.
- **Input**: `RDI`: Server Cert Container, `RSI`: Intermediate CA Cert Container
- **Output**: `RAX = 1` if chain is valid, `0` if untrusted

### `ux509_trust_store_add_root`
Registers a new trusted Root CA 32-byte public key into kernel trust store.
- **Input**: `RDI`: 32-byte Public Key Pointer, `RSI`: Issuer String Pointer
- **Output**: `RAX = 1` on success

### `ux509_generate_csr`
Formats PKCS#10 Certificate Signing Request (`.csr`).
- **Input**: `RDI`: Subject String, `RSI`: Private Key, `RDX`: Output CSR Buffer
- **Output**: `RAX = CSR Length`
