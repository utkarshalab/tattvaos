# security/ids — Intrusion Detection System (IDS)

> **Intrusion Detection System** — "Detect, alert, never block."
> Passive monitoring of network traffic and system activity for malicious
> activity or policy violations. IDS is detection-only — it never drops or
> modifies packets (that is IPS's job). Every detection emits an auditable
> alert that can be exported to SIEM.

---

## Module Layout

```
ids/
├── Makefile                    # builds all 10 components + test
├── .gitignore
├── config/ids.conf             # module configuration
├── src/
│   ├── ids.asm                 # main dispatcher / inspection pipeline
│   ├── sensor.asm              # packet capture, syscall audit, log ingestion
│   ├── reassembler.asm         # TCP stream reassembly, IP defragmentation
│   ├── analyzer.asm            # HTTP, DNS, TLS, SMB protocol parsing
│   ├── rules.asm               # signature database, rule compiler, hot reload
│   ├── detector.asm            # anomaly detection, behavioral heuristics
│   ├── alert.asm               # alert generation, deduplication, severity
│   ├── correlator.asm          # cross-source threat correlation
│   ├── siem.asm                # SIEM export (CEF, LEEF, JSON, SYSLOG)
│   └── stats.asm               # metrics, thresholds, baselines
├── include/
│   └── ids.inc                 # master schema header (strucs, constants,
│                               ; error codes, macros)
├── docs/
│   ├── README.md               # this file
│   ├── API.md                  # complete API reference
│   ├── ARCHITECTURE.md         # component & layer diagrams
│   ├── DESIGN.md               # design principles & state machines
│   ├── SEQUENCE.md             # call flow diagrams
│   └── THREAT_MODEL.md         # threat model & attack scenarios
├── tests/
│   ├── run.sh                  # test runner (36+ checks)
│   └── test_ids.asm            # skeleton test (structural validation)
├── bin/                        # build output (gitignored)
└── build/                      # build artifacts (gitignored)
```

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          Network / Host Traffic                              │
│  Packets ─► Syscalls ─► Logs ─► API Calls                                    │
└───────────────────────────┬─────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  ids.asm (Main Dispatcher / Inspection Pipeline)                             │
│  Orchestrates all 9 components, returns verdict + reason code                │
└───────────┬──────────────────────────────────────────────────────────────────┘
            │
    ┌───────┴───────┐
    ▼               ▼
┌──────────┐    ┌──────────┐
│ Sensor   │    │ Reassembler│
│ (capture)│    │ (TCP/IP    │
│          │    │  reassembly)│
└────┬─────┘    └──────┬────┘
     │                 │
     ▼                 ▼
┌──────────┐    ┌──────────┐
│ Analyzer │    │ Rules    │
│ (proto   │    │ (sig/    │
│  parse)  │    │  anomaly)│
└────┬─────┘    └──────┬────┘
     │                 │
     ▼                 ▼
┌──────────┐    ┌──────────┐
│ Detector │    │ Alert    │
│ (anomaly │    │ (gen/dedup│
│  heur.)  │    │  /sev)   │
└────┬─────┘    └──────┬────┘
     │                 │
     ▼                 ▼
┌──────────┐    ┌──────────┐
│Correlator│    │   SIEM   │
│(threat   │    │ (export) │
│  score)  │    │          │
└────┬─────┘    └──────┬────┘
     │                 │
     ▼                 ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  Stats Engine (metrics, thresholds, baselines) — feeds all components       │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Components

| Component | Responsibility | Key Symbols |
|-----------|---------------|-------------|
| `ids` | Main dispatcher, inspection pipeline orchestration | `ids_init`, `ids_inspect_packet`, `ids_get_stats` |
| `sensor` | Packet capture, syscall audit, log ingestion | `ids_sensor_capture` |
| `reassembler` | TCP stream reassembly, IP fragment defragmentation | `ids_reassembler_add_packet` |
| `analyzer` | HTTP, DNS, TLS, SMB, FTP, SSH protocol parsing | `ids_analyzer_parse` |
| `rules` | Signature database, rule compiler, hot reload | `ids_rules_load`, `ids_rules_match` |
| `detector` | Anomaly detection, behavioral heuristics, scan/brute-force | `ids_detector_evaluate` |
| `alert` | Alert generation, deduplication, severity, state mgmt | `ids_alert_emit`, `ids_alert_acknowledge` |
| `correlator` | Cross-source threat correlation, scoring, campaigns | `ids_correlator_update` |
| `siem` | Alert export to SIEM (CEF, LEEF, JSON, SYSLOG) | `ids_siem_export` |
| `stats` | Metrics, thresholds, baselines, top-talkers | `ids_stats_record` |

---

## Design Principles

| Principle | Requirement |
|-----------|-------------|
| **Detection only** | IDS never blocks, drops, or modifies traffic. That is IPS's responsibility. |
| **Fail open** | If the IDS component fails, traffic continues (unlike IPS which fails closed). |
| **Auditability** | Every alert is emitted through the audit subsystem with reason code. |
| **Observable** | Every component exposes `*_init`, `*_shutdown`, `*_status`, `*_version`. |
| **Testable** | Every component ships structural tests and symbol export checks. |
| **Pluggable** | Rules engine supports hot-reload; SIEM export format is configurable. |
| **Memory-bounded** | Ring buffers, stream tables, and alert queues have configurable limits. |

---

## Build

```bash
# From security/ids/
make              # assemble all 10 components + test binary
make test         # run skeleton tests (36+ checks)
make clean        # remove all .bin files

# From repository root
make -C security/ids all
make -C security/ids test
```

---

## Pipeline Flow

```
Packet → Sensor → Reassembler → Analyzer → Rules → Detector → Correlator →
     ↳ Alert (emit) → SIEM (export) → Stats (record)
                                    ↳ Verdict returned to caller
```

Verdicts: `IDS_VERDICT_CLEAN` (0), `IDS_VERDICT_SUSPICIOUS` (1),
`IDS_VERDICT_THREAT` (2), `IDS_VERDICT_ERROR` (-1).

---

## Roadmap (Implementation)

| Phase | Work |
|-------|------|
| **Phase 1 (skeleton)** | All 10 components compile & link as stubs; tests pass. ← current |
| **Phase 2 (core)** | Implement `init`/`shutdown`/`status`, ring buffer, stream table, alert pool |
| **Phase 3 (capture)** | Implement sensor packet capture from NIC and syscall audit |
| **Phase 4 (analysis)** | Protocol parsers (HTTP, DNS, TLS), signature matching engine |
| **Phase 5 (detection)** | Anomaly detection, scan/brute-force/exfil/C2 heuristics |
| **Phase 6 (export)** | Alert deduplication, SIEM export, stats sampling |
| **Phase 7 (integration)** | Wire into kernel network stack, IPS integration, usrauth audit |

---

## License

Apache-2.0 — see `LICENSE` at the repository root.
