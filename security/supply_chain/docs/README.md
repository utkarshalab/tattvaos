# security/supply_chain — Supply Chain Security

## Purpose
Supply chain integrity: SBOM generation, provenance tracking, supply-chain
attestation, and component verification for Utkarsha OS.

## Architecture
- **SBOM** — Software Bill of Materials generation and storage
- **Provenance** — build-system attestation, signer identity tracking
- **Verification** — component signature verification before load
- **Attestation** — signed attestations for dependencies and artifacts

## API (skeleton)
| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `supply_chain_init` | none | rax = 0 | Initialize subsystem |
| `supply_chain_shutdown` | none | rax = 0 | Shut down |
| `supply_chain_status` | none | rax = status | Current status |
| `supply_chain_sbom` | artifact, out | rax = result | Generate SBOM for artifact |
| `supply_chain_verify` | artifact, signature | rax = result | Verify component signature |
| `supply_chain_attest` | component | rax = result | Produce attestation |

## Design Decisions
- All components must have a verifiable SBOM before being loaded into the kernel.
- Attestations are signed by the build system's root key.
- Verification failures fail-closed (component not loaded).

## Threat Model
- Compromised build system injects backdoor → mitigated by reproducible builds + multi-party attestation.
- Stolen signing key → mitigated by HSM-backed keys + key rotation.

## Status
Skeleton. `supply_chain.asm` exports `supply_chain_init`, `supply_chain_shutdown`, `supply_chain_status` as no-op stubs.

## Tests
Run: `make -C security/supply_chain test`

## License
Apache-2.0
