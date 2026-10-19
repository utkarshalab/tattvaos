# security/ — Tattva OS Security Architecture

> Complete enterprise security architecture for Tattva OS — identity, threat
> detection, prevention, response, cryptography, compliance, and zero trust.

---

## Module Layout

```
security/
├── Makefile                    # root build (builds & tests all modules)
├── .gitignore                  # global ignore rules
├── config/security.conf        # global configuration
├── docs/                       # global documentation
├── scripts/                    # global scripts (build-all, test-all)
├── bin/                        # build output
├── build/                      # build artifacts
├── ci/                         # CI/CD pipeline configuration
│   └── github-actions.yml
├── digital_forensics/          # DFIR, disk/memory forensics, chain of custody
├── ids/                        # Intrusion Detection System (network + host)
├── incident_response/          # Incident response playbooks & automation
├── ips/                        # Intrusion Prevention System (inline blocking)
├── malwarescan/                # Malware detection & response (70+ capabilities)
├── privacy_compliance/         # DLP, privacy, regulatory compliance
├── soar/                       # Security Orchestration, Automation & Response
├── supply_chain/               # Supply chain, SBOM, provenance
├── threat_intel/               # Threat intelligence sharing & correlation
├── usrauth/                    # Identity & Access Management (RBAC, ABAC, MAC)
├── vuln_scan/                  # Vulnerability scanning & assessment
└── zero_trust/                 # Zero Trust Architecture (micro-segmentation)
```

---

## Per-Module Layout (Enterprise Standard)

Every module follows the same structure:

```
<module>/
├── Makefile                    # module build (all, test, clean)
├── .gitignore                  # module ignore rules
├── config/<module>.conf        # module configuration
├── src/                        # NASM source files (*.asm)
├── include/                    # Include files (*.inc)
├── docs/                       # Documentation (README.md, API.md, ARCHITECTURE.md, DESIGN.md)
├── tests/                      # Test files (run.sh, test_*.asm)
├── scripts/                    # Module scripts (build.sh, test.sh)
├── bin/                        # Build output (gitignored)
└── build/                      # Build artifacts (gitignored)
```

---

## Design Principles (Enterprise)

| Principle | Requirement |
|-----------|-------------|
| **Fail closed** | Every module defaults to deny/block until explicitly initialized. |
| **Least privilege** | `usrauth` enforces intersection semantics — many ways to deny, one way to grant. |
| **Auditability** | Every security decision emits an immutable audit event (`usrauth/audit`). |
| **Memory safety** | All buffers bounds-checked; no unchecked pointer arithmetic. |
| **Constant time** | Crypto/comparison primitives constant-time where secrets are involved. |
| **Observable** | Every module exposes `*_init`, `*_shutdown`, `*_status`, `*_version`. |
| **Testable** | Every module ships `tests/run.sh` + `tests/test_<module>.asm`. |

---

## Build

```bash
# From the security/ directory
make                # build all modules
make test           # run all tests
make clean          # clean all artifacts
make usrauth        # build single module
make test-usrauth   # test single module

# Or from the repository root
make -C security all
make -C security test
```

---

## Module Index

| Module | Responsibility |
|--------|----------------|
| `digital_forensics/` | DFIR, disk/memory forensics, chain of custody |
| `ids/` | Network & host intrusion detection |
| `incident_response/` | Incident triage, containment, eradication, recovery |
| `ips/` | Intrusion prevention, inline traffic blocking |
| `malwarescan/` | Malware, ransomware, EDR, scan engine, YARA |
| `privacy_compliance/` | DLP, privacy controls, regulatory reporting |
| `soar/` | Security orchestration, automation & response |
| `supply_chain/` | SBOM, provenance, supply-chain attestation |
| `threat_intel/` | Threat intelligence ingestion & correlation |
| `usrauth/` | IAM — authentication, authorization, RBAC, ABAC, MAC |
| `vuln_scan/` | Vulnerability discovery, assessment, reporting |
| `zero_trust/` | Micro-segmentation, continuous auth, least-privilege |

---

## License

Apache-2.0 — see `LICENSE` at the repository root.
