# waf — Architecture

## Component Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         HTTP/HTTPS Traffic                                    │
│  Client ◄──────────────────────────────────────────────────────────────────► Web App │
│                        (WAF Enforcement Point)                              │
└───────────────────────────┬─────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  waf.asm — Main Dispatcher                                                    │
│  Inspection Pipeline Orchestrator                                             │
│  Routes requests through: sensor → scan engine → rules engine →             │
│  detection engine → quarantine engine → audit engine                         │
└───────────┬──────────────────────────────────────────────────────────────────┘
            │
    ┌───────┴───────┬───────────┬───────────┬───────────┬───────────┐
    ▼               ▼           ▼           ▼           ▼           ▼
┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐
│ waf_core   │  │ waf_rule │  │ waf_http │  │ waf_sqli │  │ waf_xss  │  │ waf_csrf │
│ (core)     │  │ (rules)  │  │ (parser) │  │ detector │  │ detector │  │ detector │
└────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘
     │             │             │           │           │           │
     └─────────────┴─────────────┴───────────┴───────────┴───────────┘
                            │
                            ▼
┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐
│ waf_cmd    │  │ waf_deser│  │ waf_api  │  │ waf_rate │  │ waf_bot  │  │ waf_session│
│ detect     │  │ detect   │  │ protect  │  │ limiter  │  │ detector │  │ tracker  │
└────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘
     │             │             │           │           │           │
     └─────────────┴─────────────┴───────────┴───────────┴───────────┘
                            │
                            ▼
┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐
│ waf_geoip  │  │ waf_rulec│  │ waf_siem │  │ waf_stats│  │          │  │          │
│ filter     │  │ compiler │  │ exporter │  │ engine   │  │          │  │          │
└──────────┘  └──────────┘  └──────────┘  └──────────┘           │
                                                                 │
                                                                ▼
                                                     ┌─────────────────┐
                                                     │ Client Response │
                                                     │ (Allow/Block/   │
                                                     │  Challenge/Redirect)│
                                                     └─────────────────┘
```

## Layer Diagram (Stack Integration)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Web Application (App Server)                                                │
└─────────────────────────┬────────────────────────────────────────────────────┘
                          │ HTTP request/response
┌─────────────────────────▼────────────────────────────────────────────────────┐
│  waf (WAF — Prevention)                                                      │
│  Active blocking. Can modify/drop requests in-line.                          │
│  FAILS CLOSED by default.                                                    │
└─────────────────────────┬────────────────────────────────────────────────────┘
                          │ enforcement event → audit log
┌─────────────────────────▼────────────────────────────────────────────────────┐
│  usrauth (Reference Monitor) — audit decision log                            │
└─────────────────────────┬────────────────────────────────────────────────────┘
                          │ alert → policy update
┌─────────────────────────▼────────────────────────────────────────────────────┐
│  ids (IDS — Detection)                                                       │
│  Passive monitoring. Feeds alerts to waf policy.                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Integration Points

| Interface | Direction | Purpose |
|-----------|-----------|---------|
| `kernel/net/` | waf ↔ net | Inline packet hook (can modify/drop) |
| `usrauth/audit` | waf → usrauth | Log every enforcement action |
| `ids` | ids → waf | IDS alerts feed waf policy |
| `ips` | waf → ips | waf blocks feed ips blocklist |
| `threat_intel` | threat_intel → waf | IOCs fed into waf rules |

## Trust Boundaries

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  TRUST BOUNDARY: WAF Enforcement Point                                       │
│  Outside: Raw HTTP traffic (untrusted)                                       │
│  Inside: Enforced traffic (validated by policy)                              │
│  Mitigation: All HTTP requests inspected before forwarding                   │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│  TRUST BOUNDARY: Rule Updates                                                │
│  Outside: Rule files from admin/threat intel (untrusted until verified)      │
│  Inside: Compiled rule database (trusted after verification)                 │
│  Mitigation: Signature verification on rule updates                          │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Data Flow (Inline, Can Modify)

```
HTTP Request → waf Entry → [Inspection Pipeline] →
    ↳ Allow → Forward to web app
    ↳ Block → Return 403 Forbidden
    ↳ Challenge → Return CAPTCHA challenge
    ↳ Redirect → Redirect to different URL
    ↳ Log → Log only, allow traffic
```
