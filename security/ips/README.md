# security/ips — Intrusion Prevention System (IPS)

> **Intrusion Prevention System** — "Detect, block, never trust."
> Enterprise-grade inline prevention engine: sits in the traffic path and can
> DROP, RESET, THROTTLE, QUARANTINE, BLOCK, REDIRECT, or SANDBOX traffic.
> FAILS CLOSED — if enforcement cannot be verified, traffic is blocked.
> Works WITH IDS: IDS detects, IPS prevents.

---

## Module Layout (21 Components)

```
ips/
├── Makefile                    # builds all 24 components + test
├── .gitignore
├── config/ips.conf             # module configuration
├── src/
│   ├── ips.asm                 # main dispatcher / enforcement pipeline
│   ├── inspector.asm           # inline packet inspection
│   ├── enforcer.asm            # drop/reset/throttle/quarantine/block actions
│   ├── policy.asm              # allow/deny rules, default-deny evaluation
│   ├── bypass.asm              # fail-open/fail-closed for HA paths
│   ├── rate_limiter.asm        # per-IP rate limiting
│   ├── connection_tracker.asm  # stateful connection tracking
│   ├── quarantine.asm          # isolate infected endpoints
│   ├── blocklist.asm           # IP/domain blacklist management
│   ├── siem.asm                # SIEM export (CEF, LEEF, JSON, SYSLOG)
│   ├── stats.asm               # metrics, thresholds, baselines
│   ├── geoip.asm               # geographic IP filtering
│   ├── app_control.asm         # application-layer allow/deny
│   ├── tls_inspector.asm       # SSL/TLS inspection, JA3 fingerprinting
│   ├── dns_filter.asm          # DNS filtering, tunneling detection
│   ├── file_analysis.asm       # file hash reputation, sandbox integration
│   ├── url_filter.asm          # URL/web filtering, categorization
│   ├── bot_detector.asm        # bot detection, behavioral heuristics
│   ├── ddos_protector.asm      # DDoS protection (SYN flood, etc.)
│   ├── threat_feed.asm         # threat intelligence (STIX/TAXII)
│   ├── waf_engine.asm          # Web Application Firewall (SQLi, XSS)
│   ├── packet_capture.asm      # PCAP export, forensic capture
│   ├── ha_cluster.asm          # high availability clustering
│   ├── api_protection.asm      # API gateway protection (OAuth, JWT)
│   └── ml_anomaly.asm          # ML anomaly detection
├── include/
│   └── ips.inc                 # master schema header (strucs, constants,
│                               ; error codes, macros)
├── docs/
│   ├── README.md               # this file
│   ├── API.md                  # complete API reference
│   ├── ARCHITECTURE.md         # component & layer diagrams
│   ├── DESIGN.md               # design principles & state machines
│   ├── SEQUENCE.md             # call flow diagrams
│   └── THREAT_MODEL.md         # threat model & attack scenarios
├── tests/
│   ├── run.sh                  # test runner (146 checks)
│   └── test_ips.asm            # skeleton test (structural validation)
├── bin/                        # build output (gitignored)
└── build/                      # build artifacts (gitignored)
```

---

## Components (21)

| Component | Responsibility | Key Symbols |
|-----------|---------------|-------------|
| `ips` | Main dispatcher, enforcement pipeline | `ips_init`, `ips_enforce`, `ips_get_stats` |
| `inspector` | Inline packet inspection | `ips_inspector_inspect` |
| `enforcer` | Apply drop/reset/throttle/quarantine/block | `ips_enforcer_apply_action` |
| `policy` | Allow/deny rules, default-deny | `ips_policy_load`, `ips_policy_evaluate` |
| `bypass` | Fail-open/fail-closed for HA paths | `ips_bypass_check`, `ips_bypass_set_fail_mode` |
| `rate_limiter` | Per-IP rate limiting | `ips_rate_limiter_check` |
| `connection_tracker` | Stateful connection tracking | `ips_connection_tracker_track` |
| `quarantine` | Isolate compromised endpoints | `ips_quarantine_isolate`, `ips_quarantine_release` |
| `blocklist` | IP/domain blacklist management | `ips_blocklist_add`, `ips_blocklist_check` |
| `siem` | Enforcement event export | `ips_siem_export` |
| `stats` | Enforcement metrics | `ips_stats_record` |
| `geoip` | Geographic IP filtering | `ips_geoip_lookup`, `ips_geoip_is_blocked` |
| `app_control` | Application allow/deny | `ips_app_control_detect`, `ips_app_control_is_allowed` |
| `tls_inspector` | TLS inspection, JA3 fingerprinting | `ips_tls_inspector_inspect`, `ips_tls_inspector_check_fingerprint` |
| `dns_filter` | DNS filtering, tunneling detection | `ips_dns_filter_check`, `ips_dns_filter_block` |
| `file_analysis` | File hash reputation, sandbox | `ips_file_analysis_check_hash`, `ips_file_analysis_send_sandbox` |
| `url_filter` | URL/web filtering | `ips_url_filter_check`, `ips_url_filter_categorize` |
| `bot_detector` | Bot detection | `ips_bot_detector_check`, `ips_bot_detector_score` |
| `ddos_protector` | DDoS protection | `ips_ddos_protector_check`, `ips_ddos_protector_mitigate` |
| `threat_feed` | Threat intelligence (STIX/TAXII) | `ips_threat_feed_update`, `ips_threat_feed_check_ioc` |
| `waf_engine` | Web Application Firewall | `ips_waf_engine_inspect`, `ips_waf_engine_block` |
| `packet_capture` | PCAP export, forensics | `ips_packet_capture_start`, `ips_packet_capture_stop` |
| `ha_cluster` | High availability clustering | `ips_ha_cluster_failover`, `ips_ha_cluster_sync` |
| `api_protection` | API gateway protection | `ips_api_protection_authenticate`, `ips_api_protection_rate_limit` |
| `ml_anomaly` | ML anomaly detection | `ips_ml_anomaly_score`, `ips_ml_anomaly_train` |

---

## Design Principles

| Principle | Requirement |
|-----------|-------------|
| **Fail closed** | If enforcement cannot be verified, traffic is blocked. Default-deny posture. |
| **Inline enforcement** | IPS sits in the traffic path and can modify/drop packets. |
| **Default-deny** | No traffic is allowed unless an explicit policy rule permits it. |
| **Composable with IDS** | IDS detects, IPS prevents. IDS alerts feed IPS policy. |
| **Stateful enforcement** | Connection tracking enables context-aware decisions. |
| **Auditability** | Every enforcement action is logged through `usrauth/audit`. |
| **Observable** | Every component exposes `*_init`, `*_shutdown`, `*_status`, `*_version`. |
| **Testable** | Every component ships structural tests and symbol export checks. |
| **Pluggable** | Bypass rules for HA paths; SIEM export format configurable. |

---

## Build

```bash
# From security/ips/
make              # assemble all 21 components + test binary
make test         # run skeleton tests (146 checks)
make clean        # remove all .bin files

# From repository root
make -C security/ips all
make -C security/ips test
```

---

## Enforcement Flow

```
Packet → Bypass → Blocklist → Quarantine → RateLimiter → Policy →
GeoIP → AppControl → TLS Inspector → DNS Filter → File Analysis →
URL Filter → Bot Detector → DDoS Protector → Threat Feed → WAF Engine →
Inspector → Enforcer → ConnectionTracker → SIEM → Stats → ML Anomaly
                                    ↳ Action returned to caller
```

Actions: `IPS_ACTION_ALLOW` (0), `IPS_ACTION_DROP` (1), `IPS_ACTION_RESET` (2),
`IPS_ACTION_THROTTLE` (3), `IPS_ACTION_QUARANTINE` (4), `IPS_ACTION_BLOCK` (5),
`IPS_ACTION_REDIRECT` (6), `IPS_ACTION_INSPECT_DEEP` (7),
`IPS_ACTION_SANDBOX` (8), `IPS_ACTION_CHALLENGE` (9).

---

## IDS + IPS Integration

```
IDS (Detection Only)          IPS (Prevention)
─────────────────             ───────────────
Passive monitoring            Inline enforcement
Fail-open (traffic flows)     Fail-closed (traffic blocked)
Alerts → Audit log            Alerts → Block/Drop/Reset
No packet modification        Can modify/drop packets
       ↓                           ↓
  IDS alert ──┐              ┌──── IPS enforcement
              │              │
              └──── feed ────┘
           IPS policy updated
```

IDS alerts feed into IPS policy rules, enabling automated prevention based on detection.

---

## Roadmap (Implementation)

| Phase | Work |
|-------|------|
| **Phase 1 (skeleton)** | All 21 components compile & link as stubs; tests pass. ← current |
| **Phase 2 (core)** | Implement `init`/`shutdown`/`status`, blocklist, quarantine tables |
| **Phase 3 (enforcement)** | Implement enforcer drop/reset/throttle at netfilter hooks |
| **Phase 4 (policy)** | Default-deny rule engine with 5-tuple matching |
| **Phase 5 (rate limiting)** | Token bucket rate limiter per IP |
| **Phase 6 (stateful)** | Connection tracking with state machine |
| **Phase 7 (advanced)** | GeoIP, TLS inspection, DNS filter, WAF, DDoS protection |
| **Phase 8 (integration)** | Wire into kernel network stack, IDS alert integration |

---

## License

Apache-2.0 — see `LICENSE` at the repository root.
