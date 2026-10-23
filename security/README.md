# security/ — Utkarsha OS Enterprise Security Stack

> Enterprise-grade security subsystem for Utkarsha OS. Identity, threat
> detection, prevention, response, forensics, compliance, and zero trust — all
> implemented as NASM (x86-64) skeleton modules with detailed design
> documentation. Implementation is intentional-stub: every module compiles and
> links, but contains no security logic yet.

---

## Module Layout

```
security/
├── README.md                 # this file
├── security_architecture.md  # high-level architecture & layer map
├── digital_forensics/        # DFIR, disk/memory forensics, chain of custody
├── ids/                      # Intrusion Detection System (network + host)
├── incident_response/        # Incident response playbooks & automation
├── ips/                      # Intrusion Prevention System (inline blocking)
├── malwarescan/              # Malware detection & response (70+ capabilities)
├── privacy_compliance/       # DLP, privacy, regulatory compliance
├── soar/                     # Security Orchestration, Automation & Response
├── supply_chain/             # Supply chain, SBOM, provenance
├── threat_intel/             # Threat intelligence sharing & correlation
├── usrauth/                  # Identity & Access Management (RBAC, ABAC, MAC)
├── vuln_scan/                # Vulnerability scanning & assessment
└── zero_trust/               # Zero Trust Architecture (micro-segmentation)
```

---

## Design Principles (Enterprise)

| Principle | Requirement |
|-----------|-------------|
| **Fail closed** | Every module defaults to deny/block until explicitly initialized and policy-loaded. |
| **Least privilege** | `usrauth` enforces intersection semantics: many ways to deny, exactly one way to grant. |
| **Auditability** | Every security-relevant decision emits an immutable audit event (`usrauth/audit`). |
| **Memory safety** | All buffers bounds-checked; no unchecked pointer arithmetic in hot paths. |
| **Constant time** | Crypto/comparison primitives must be constant-time where secrets are involved. |
| **Observable** | Each module exposes `*_init`, `*_shutdown`, `*_status` and a version string. |
| **Testable** | Every module ships `tests/run.sh` + `tests/test_<module>.asm`. |

---

## Conventions (NASM x86-64)

All `.asm` modules follow the same skeleton template:

```nasm
%ifndef GUARD_SECURITY_<MODULE>_<MODULE>_ASM
%define GUARD_SECURITY_<MODULE>_<MODULE>_ASM

bits 64

section .bss          ; mutable state (zero-initialized)
section .data         ; initialized constants / version strings
section .text         ; executable code

global <module>_init
global <module>_shutdown
global <module>_status
global <module>_version
%endif
```

- Include guards named `GUARD_SECURITY_<PATH>_<FILE>_ASM`
- `bits 64` — flat x86-64 binary
- Callee-saved registers (`rbx`, `rbp`, `r12`–`r15`) preserved across calls
- Status convention: `rax = 0` on success, nonzero errno-style on failure

---

## Build

Each module directory contains a `Makefile`. From the repository root:

```bash
make -C security/<module>
make -C security/<module> test   # run module test suite
```

Run the full security test suite:

```bash
make -C security test
```

---

## Module Index

| Module | Responsibility | Status |
|--------|----------------|--------|
| `usrauth/` | Authentication, authorization, RBAC, ABAC, MAC, sessions, tokens | skeleton |
| `malwarescan/` | Malware, ransomware, EDR, scan engine, YARA, memory protection | skeleton |
| `ids/` | Network & host intrusion detection | skeleton |
| `ips/` | Intrusion prevention, inline traffic blocking | skeleton |
| `soar/` | Security orchestration, automation & response playbooks | skeleton |
| `threat_intel/` | Threat intelligence ingestion, sharing, correlation | skeleton |
| `vuln_scan/` | Vulnerability discovery, assessment, reporting | skeleton |
| `incident_response/` | Incident triage, containment, eradication, recovery | skeleton |
| `digital_forensics/` | Disk/memory forensics, chain of custody, DFIR | skeleton |
| `privacy_compliance/` | DLP, privacy controls, regulatory reporting | skeleton |
| `supply_chain/` | SBOM, provenance, supply-chain attestation | skeleton |
| `zero_trust/` | Micro-segmentation, continuous auth, least-privilege access | skeleton |

---

## Roadmap

1. **Phase 1 (skeleton)** — all modules compile & link; tests pass (no-op stubs). ← current
2. **Phase 2 (core)** — implement `init`/`shutdown`/`status`, state structures, config loading
3. **Phase 3 (detection)** — scan engines, signatures, heuristics, anomaly detection
4. **Phase 4 (response)** — quarantine, blocking, SOAR playbooks, automated containment
5. **Phase 5 (hardening)** — constant-time crypto, memory protections, formal verification

---

## License

Apache-2.0 — see `LICENSE` at the repository root.
