# crypto/ux509 — X.509 PKI Certificate Parser & Chain Validation Subsystem

The **`crypto/ux509`** library is the Public Key Infrastructure (PKI) Certificate Engine for Tattva OS, covering 100% of Web PKI RFC standards (**RFC 5280, RFC 6125, RFC 6960, RFC 6962, RFC 2986**).

---

## 1. Subsystem Architecture

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
├── ux509_crl.asm              ← Certificate Revocation List (CRL) checker
├── ux509_ocsp.asm             ← RFC 6960 OCSP Stapling Response reader & validator
├── ux509_aia.asm              ← Authority Information Access (AIA) extension parser
├── ux509_name_constraints.asm ← RFC 5280 Permitted & Excluded domain tree name constraints
├── ux509_sct.asm              ← RFC 6962 Certificate Transparency (CT) SCT verifier
├── ux509_fingerprint.asm      ← SHA-256 certificate thumbprint & public key pinning engine
├── ux509_key_match.asm        ← Certificate public key vs private keypair validator
├── ux509_trust_store.asm      ← Unikernel Root CA Trust Store manager
├── ux509_self_signed.asm      ← Self-Signed Root Certificate Auto-Detector
├── ux509_name_norm.asm        ← Canonical DN string normalizer & case-insensitive matcher
├── ux509_csr.asm              ← PKCS#10 Certificate Signing Request (CSR) parser & generator
├── ux509_pqc_cert.asm         ← Dual-signature PQC hybrid cert parser (ECDSA + Dilithium)
├── ux509_chain.asm            ← Chain of trust validator (Root CA -> Inter. CA -> Server Cert)
└── ux509.asm                  ← Master X.509 PKI Dispatcher API
```

---

## 2. Supported Standards & Specifications

- **RFC 5280**: X.509 v3 Certificate & CRL Profile.
- **RFC 6125**: Representation & Verification of Domain Identity (Wildcard Domain Matching).
- **RFC 6960**: Online Certificate Status Protocol (OCSP Stapling).
- **RFC 6962**: Certificate Transparency (CT) Signed Certificate Timestamps (SCT).
- **RFC 2986**: PKCS#10 Certificate Signing Requests (CSR).
- **RFC 7468**: Base64 ASCII Armored PEM Encodings (`-----BEGIN CERTIFICATE-----`).
