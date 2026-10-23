# security/digital_forensics — Digital Forensics & Incident Response (DFIR)

## Purpose
Provide disk and memory forensics, evidence acquisition, chain-of-custody
management, and artifact analysis for Utkarsha OS security incidents.

## Architecture
- **Acquirer** — bit-for-mat disk/memory imaging with write-blocking
- **Analyzer** — file-system carving, timeline reconstruction, string search
- **Custody** — tamper-evident hashing (SHA-256), evidence signing, log integrity
- **Reporter** — machine-readable and human-readable forensic reports

## API (skeleton)
| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `dfir_init` | none | rax = 0 | Initialize DFIR subsystem |
| `dfir_shutdown` | none | rax = 0 | Shut down, release devices |
| `dfir_status` | none | rax = status | Current subsystem status |
| `dfir_acquire` | device, out_path | rax = result | Acquire forensic image |
| `dfir_hash` | file, out_digest | rax = result | Compute evidence digest |
| `dfir_verify` | file, digest | rax = result | Verify evidence integrity |

## Design Decisions
- All evidence writes go through a write-blocking layer to prevent source mutation.
- Every acquisition is logged to an append-only, signed custody journal.
- Hashing is constant-time where secret material may be present.

## Threat Model
- Attacker attempts to tamper with evidence post-acquisition → mitigated by signed custody journal.
- Attacker forces acquisition of wrong device → mitigated by device-path validation.

## Status
Skeleton. `dfir.asm` exports `dfir_init`, `dfir_shutdown`, `dfir_status` as no-op stubs.

## Tests
Run: `make -C security/digital_forensics test`

## License
Apache-2.0
