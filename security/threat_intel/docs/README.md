# security/threat_intel — Threat Intelligence

## Purpose
Threat intelligence ingestion, sharing, correlation, and indicator-of-compromise
(IOC) management for Utkarsha OS security modules.

## Architecture
- **Ingestor** — pull/push feeds (STIX/TAXII, CSV, JSON, proprietary)
- **Store** — IOC database: IPs, domains, hashes, YARA rules, TTPs
- **Correlator** — match observed events against IOCs, scoring
- **Exporter** — share intel with peers, SIEM, and downstream modules

## API (premium enterprise skeleton)
| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `threat_intel_init` | none | rax = status | Initialize subsystem |
| `threat_intel_shutdown` | none | rax = status | Shut down |
| `threat_intel_status` | none | rax = status | Current status |
| `threat_intel_version` | none | rax = ptr | Version string |
| `threat_intel_ingest` | feed_url, type, key | rax = result | Ingest a threat feed |
| `threat_intel_lookup` | indicator, len, type | rax = verdict | Look up an IOC |
| `threat_intel_subscribe` | topic, len | rax = result | Subscribe to intel topic |
| `threat_intel_match` | event, len, type, src | rax = count | Correlate event against IOCs |

### IOC Store Component (`ti_store_*`)
| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `ti_store_init` | none | rax = status | Initialize IOC database |
| `ti_store_shutdown` | none | rax = status | Shut down store |
| `ti_store_status` | none | rax = status | Current status |
| `ti_store_version` | none | rax = ptr | Version string |
| `ti_store_add_ioc` | IOC ptr | rax = IOC ID | Add IOC to store |
| `ti_store_lookup_ioc` | indicator, len, type | rax = verdict | Look up IOC |
| `ti_store_remove_ioc` | IOC ID | rax = status | Mark IOC stale |
| `ti_store_get_ioc_count` | none | rax = count | Return IOC count |

### Threat Feed Ingestor Component (`ti_ingestor_*`)
| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `ti_ingestor_init` | none | rax = status | Initialize ingestor |
| `ti_ingestor_shutdown` | none | rax = status | Shut down ingestor |
| `ti_ingestor_status` | none | rax = status | Current status |
| `ti_ingestor_version` | none | rax = ptr | Version string |
| `ti_ingestor_pull_feed` | URL, type, key | rax = count | Pull feed from remote |
| `ti_ingestor_push_feed` | URL, batch, len | rax = count | Push IOCs to feed |
| `ti_ingestor_verify_signature` | data, len, sig | rax = valid | Verify feed signature |

### Intel Exporter Component (`ti_exporter_*`)
| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `ti_exporter_init` | none | rax = status | Initialize exporter |
| `ti_exporter_shutdown` | none | rax = status | Shut down exporter |
| `ti_exporter_status` | none | rax = status | Current status |
| `ti_exporter_version` | none | rax = ptr | Version string |
| `ti_exporter_share_ioc` | IOC, peer | rax = status | Share IOC with peer |
| `ti_exporter_push_siem` | endpoint, batch | rax = count | Push to SIEM |
| `ti_exporter_pull_peer` | endpoint, creds | rax = count | Pull from peer |

### IOC Correlator Component (`ti_correlator_*`)
| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `ti_correlator_init` | none | rax = status | Initialize correlator |
| `ti_correlator_shutdown` | none | rax = status | Shut down correlator |
| `ti_correlator_status` | none | rax = status | Current status |
| `ti_correlator_version` | none | rax = ptr | Version string |
| `ti_correlator_match_event` | event, len, type | rax = count | Match event vs IOCs |
| `ti_correlator_score_ioc` | IOC ID, evidence | rax = score | Compute confidence |
| `ti_correlator_update_score` | IOC ID, evidence | rax = score | Update confidence |

## Design Decisions
- IOC store is append-only; indicators are marked stale rather than deleted.
- Lookups are constant-time where feasible to avoid timing side-channels.
- Feeds are cryptographically signed and verified before ingestion.
- All components share `ti_state_base_t` for consistent lifecycle management.
- Global state uses fail-closed mode by default.

## Threat Model
- Poisoned feed injects false IOCs → mitigated by feed signing + reputation scoring.
- Intel exfiltration → mitigated by signed, attested sharing channels.
- Timing side-channel on IOC lookup → mitigated by constant-time comparison.
- Stale IOCs causing false positives → mitigated by TTL-based expiration.

## Status
PREMIUM ENTERPRISE SKELETON. All 5 components (core, store, ingestor, exporter, correlator)
export `*_init`, `*_shutdown`, `*_status`, `*_version` plus component-specific functions.
All logic bodies are STUBbed with TODO comments for implementation.

## Tests
Run: `make -C security/threat_intel test`

## License
Apache-2.0
