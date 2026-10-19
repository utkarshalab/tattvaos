# security/vuln_scan — Vulnerability Scanning & Assessment

## Purpose
Vulnerability discovery, assessment, and reporting for Tattva OS components,
configuration, and dependencies.

## Architecture
- **Scanner** — active/passive vulnerability scanning
- **Assessor** — risk scoring, CVSS mapping, prioritization
- **Database** — vulnerability database (CVE, CWE, advisory sources)
- **Reporter** — scan reports, remediation guidance, trend dashboards

## API (skeleton)
| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `vuln_scan_init` | none | rax = 0 | Initialize subsystem |
| `vuln_scan_shutdown` | none | rax = 0 | Shut down |
| `vuln_scan_status` | none | rax = status | Current status |
| `vuln_scan_target` | target | rax = result | Scan a target for vulnerabilities |
| `vuln_scan_assess` | finding | rax = score | Assess risk score for a finding |
| `vuln_scan_report` | scan_id, out | rax = result | Generate scan report |

## Design Decisions
- Scans are non-destructive by default; invasive checks require explicit opt-in.
- Findings are scored using CVSS v3.1 for consistent prioritization.
- Vulnerability DB updates are signed and verified before use.

## Threat Model
- Scanner itself crashes target → mitigated by safe, read-only probes first.
- False positives cause remediation waste → mitigated by verification step before reporting.

## Status
Skeleton. `vuln_scan.asm` exports `vuln_scan_init`, `vuln_scan_shutdown`, `vuln_scan_status` as no-op stubs.

## Tests
Run: `make -C security/vuln_scan test`

## License
Apache-2.0
