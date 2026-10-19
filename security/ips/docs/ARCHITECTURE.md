# ips — Architecture

## Component Diagram (21 Components)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         Inline Traffic Path                                   │
│  Client ◄──────────────────── [IPS Enforcement Point] ─────────────────────► Server│
│                        (drop/reset/throttle/quarantine/block/redirect)      │
└───────────────────────────┬─────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  ips.asm — Main Dispatcher / Enforcement Pipeline                             │
│  ─────────────────────────────────────────────────────────────────────────  │
│  1. Validate state + input                                                   │
│  2. Bypass check (fail-open/closed)                                          │
│  3. Blocklist check                                                          │
│  4. Quarantine check                                                         │
│  5. Rate limiter check                                                       │
│  6. Policy evaluation                                                        │
│  7. GeoIP check                                                              │
│  8. App Control                                                              │
│  9. TLS Inspector                                                            │
│  10. DNS Filter                                                              │
│  11. File Analysis                                                           │
│  12. URL Filter                                                              │
│  13. Bot Detector                                                            │
│  14. DDoS Protector                                                          │
│  15. Threat Feed                                                             │
│  17. WAF Engine                                                              │
│  18. Inspector                                                               │
│  19. Enforcer                                                                │
│  20. Connection Tracker                                                      │
│  21. SIEM Export                                                             │
│  22. Stats Record                                                            │
│  23. ML Anomaly Score                                                        │
│  24. Return action + reason + duration                                       │
└───────────┬──────────────────────────────────────────────────────────────────┘
            │
    ┌───────┴───────┬───────────┬───────────┬───────────┐
    ▼               ▼           ▼           ▼           ▼
┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐
│ Bypass   │  │ Blocklist│  │ Quarantine│ │ RateLimit│  │ Policy   │
│ (fail-   │  │ (blocked │  │ (isolated│  │ (per-IP  │  │ (allow/  │
│  closed) │  │  IPs)    │  │  IPs)    │  │  limits) │  │  deny)   │
└────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘
     │             │             │           │           │
     └─────────────┴─────────────┴───────────┴───────────┘
                            │
                            ▼
┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐
│ GeoIP    │  │ AppCtrl  │  │ TLS Insp │  │ DNS Fltr │  │ File Anls│
│ (country │  │ (app sig │  │ (JA3/    │  │ (domain  │  │ (file    │
│  block)  │  │  detect) │  │  JA3S)   │  │  block)  │  │  hash)   │
└────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘
     │             │             │           │           │
     └─────────────┴─────────────┴───────────┴───────────┘
                            │
                            ▼
┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐
│ URL Fltr │  │ Bot Det  │  │ DDoS Prot│  │ ThreatFeed│ │ WAF Eng  │
│ (cat/blk │  │ (behavior│  │ (threshold│ │ (IOC)    │ │ (SQLi/   │
│  block)  │  │  score)  │  │  detect) │  │          │ │  XSS)    │
└────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘
     │             │             │           │           │
     └─────────────┴─────────────┴───────────┴───────────┘
                            │
                            ▼
┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐
│ Pkt Cap  │  │ HA Clust │  │ API Prot │  │ ML Anom  │  │   SIEM   │
│ (PCAP)   │  │ (failover│  │ (JWT/    │  │ (score)  │  │ (export) │
│          │  │  sync)   │  │  API key)│  │          │          │
└──────────┘  └──────────┘  └──────────┘  └──────────┘           │
                                                                    │
                                                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  Stats Engine (enforcement metrics, blocked/quarantined tracking)            │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Layer Diagram (Stack Integration)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Kernel Network Stack (net/)                                                 │
└─────────────────────────┬────────────────────────────────────────────────────┘
                          │ inline packet hook
┌─────────────────────────▼────────────────────────────────────────────────────┐
│  ips (IPS — Prevention)                                                      │
│  Active blocking. Can modify/drop packets in-line.                           │
│  FAILS CLOSED by default.                                                    │
└─────────────────────────┬────────────────────────────────────────────────────┘
                          │ enforcement event → audit log
┌─────────────────────────▼────────────────────────────────────────────────────┐
│  usrauth (Reference Monitor) — audit decision log                            │
└─────────────────────────┬────────────────────────────────────────────────────┘
                          │ alert → policy update
┌─────────────────────────▼────────────────────────────────────────────────────┐
│  ids (IDS — Detection)                                                       │
│  Passive monitoring. Feeds alerts to IPS policy.                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Integration Points

| Interface | Direction | Purpose |
|-----------|-----------|---------|
| `kernel/net/` | ips ↔ net | Inline packet hook (can modify/drop) |
| `usrauth/audit` | ips → usrauth | Log every enforcement action with reason code |
| `ids` | ids → ips | IDS alerts feed IPS policy for automated prevention |
| `zero_trust` | zero_trust → ips | Session revocation → block endpoint |
| `threat_intel` | threat_intel → ips | IOCs fed into threat_feed component |

## Trust Boundaries

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  TRUST BOUNDARY: IPS Enforcement Point                                       │
│  Outside: Raw network traffic (untrusted)                                    │
│  Inside: Enforced traffic (validated by policy)                              │
│  Mitigation: All packets inspected before forwarding                         │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│  TRUST BOUNDARY: Blocklist/Quarantine                                        │
│  Outside: Endpoint IPs (untrusted until verified)                            │
│  Inside: Blocked/quarantined state (trusted after verification)              │
│  Mitigation: Signed blocklist updates, TTL expiry on blocks                  │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│  TRUST BOUNDARY: Rule Updates                                                │
│  Outside: Rule files from admin/threat intel (untrusted until verified)      │
│  Inside: Compiled rule database (trusted after validation)                   │
│  Mitigation: Signature verification on rule updates                          │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Data Flow (Inline, Can Modify)

```
Network Card → Inline Hook → Inspector → [Enforcement Pipeline] →
                                           ↳ Allow → Forward to destination
                                           ↳ Drop → Packet discarded
                                           ↳ Reset → TCP RST injected
                                           ↳ Throttle → Rate limit applied
                                           ↳ Quarantine → Redirect to quarantine VLAN
                                           ↳ Block → Add to blocklist
                                           ↳ Redirect → Send to different destination
                                           ↳ Deep Inspect → Send to secondary analysis
                                           ↳ Sandbox → Send file to sandbox
                                           ↳ Challenge → CAPTCHA/challenge-response
```
