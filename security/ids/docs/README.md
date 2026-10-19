# security/ids — Intrusion Detection System (IDS)

## Purpose
Monitor network traffic and host system activity for malicious activity or
policy violations. Passive (detect-only) by design — does not block traffic.

## Architecture
- **Sensor** — packet capture, system-call audit, log ingestion
- **Detector** — signature matching, anomaly/heuristic detection, thresholding
- **Alert** — alert generation, deduplication, severity scoring, SIEM export
- **Rules** — rule compiler, rule database, hot reload

## API (skeleton)
| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `ids_init` | none | rax = 0 | Initialize IDS |
| `ids_shutdown` | none | rax = 0 | Shut down IDS |
| `ids_status` | none | rax = status | Current subsystem status |
| `ids_load_rules` | rules_path | rax = result | Load detection rules |
| `ids_scan_packet` | packet, len | rax = verdict | Inspect a single packet |
| `ids_alert_count` | none | rax = count | Number of active alerts |

## Design Decisions
- Detection-only: IDS never drops or modifies packets (that is `ips`'s job).
- Rule engine supports both signature (exact match) and anomaly (baseline deviation) modes.
- Alerts are deduplicated within a configurable time window to prevent storm.

## Threat Model
- Evasion via fragmentation/encoding → mitigated by packet reassembly + normalization before inspection.
- Alert flooding (DoS) → mitigated by rate-limiting and deduplication.

## Status
Skeleton. `ids.asm` exports `ids_init`, `ids_shutdown`, `ids_status` as no-op stubs.

## Tests
Run: `make -C security/ids test`

## License
Apache-2.0
