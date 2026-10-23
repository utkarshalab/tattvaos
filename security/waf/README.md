# security/waf — Web Application Firewall (WAF)

> **Web Application Firewall** — Layer 7 application security for Utkarsha OS.
> Detects and blocks SQL injection, XSS, CSRF, command injection, file inclusion,
;              deserialization attacks, bot traffic, API abuse, and more.
> Works WITH IPS: IPS handles network-layer enforcement, WAF handles application-layer enforcement.

---

## Module Layout (18 Components)

```
waf/
├── Makefile                    # builds all 18 components + test
├── .gitignore
├── config/waf.conf             # module configuration
├── src/
│   ├── waf.asm                 # main dispatcher / inspection pipeline
│   ├── waf_core.asm            # core engine, state management
│   ├── waf_rule.asm            # rule engine, rule compilation
│   ├── waf_http.asm            # HTTP/HTTPS request parsing
│   ├── waf_sqli.asm            # SQL injection detection
│   ├── waf_xss.asm             # XSS detection
│   ├── waf_csrf.asm            # CSRF protection
│   ├── waf_fim.asm             # File inclusion detection
│   ├── waf_cmd.asm             # Command injection detection
│   ├── waf_deser.asm           # Deserialization detection
│   ├── waf_api.asm             # API protection (OAuth, JWT, rate limiting)
│   ├── waf_rate.asm            # Rate limiting
│   ├── waf_bot.asm             # Bot detection
│   ├── waf_session.asm         # Session protection
│   ├── waf_geoip.asm           # Geographic IP filtering
│   ├── waf_rulec.asm           # Custom rule compiler
│   ├── waf_siem.asm            # SIEM export
│   └── waf_stats.asm           # Statistics engine
├── include/
│   └── waf.inc                 # master schema header
├── docs/
│   ├── README.md               # this file
│   ├── API.md                  # complete API reference
│   ├── ARCHITECTURE.md         # component & layer diagrams
│   ├── DESIGN.md               # design principles & state machines
│   ├── SEQUENCE.md             # call flow diagrams
│   └── THREAT_MODEL.md         # threat model & attack scenarios
├── tests/
│   ├── run.sh                  # test runner (98+ checks)
│   └── test_waf.asm            # skeleton test
├── bin/                        # build output (gitignored)
└── build/                      # build artifacts (gitignored)
```

---

## Components (18)

| Component | Responsibility | Key Symbols |
|-----------|---------------|-------------|
| `waf` | Main dispatcher, inspection pipeline orchestration | `waf_init`, `waf_inspect`, `waf_get_stats` |
| `core` | Core engine, state management | `waf_core_init`, `waf_core_status` |
| `rule` | Rule engine, rule compilation | `waf_rule_load`, `waf_rule_evaluate` |
| `http` | HTTP/HTTPS request parsing | `waf_http_parse`, `waf_http_extract` |
| `sqli` | SQL injection detection | `waf_sqli_detect` |
| `xss` | XSS detection | `waf_xss_detect` |
| `csrf` | CSRF protection | `waf_csrf_validate` |
| `fim` | File inclusion detection | `waf_fim_detect` |
| `cmd` | Command injection detection | `waf_cmd_detect` |
| `deser` | Deserialization detection | `waf_deser_detect` |
| `api` | API protection (OAuth, JWT, rate limiting) | `waf_api_authenticate`, `waf_api_rate_limit` |
| `rate` | Rate limiting | `waf_rate_check` |
| `bot` | Bot detection | `waf_bot_detect`, `waf_bot_score` |
| `session` | Session protection | `waf_session_validate`, `waf_session_track` |
| `geoip` | Geographic IP filtering | `waf_geoip_lookup`, `waf_geoip_is_blocked` |
| `rulec` | Custom rule compiler | `waf_rulec_compile` |
| `siem` | SIEM export | `waf_siem_export` |
| `stats` | Statistics engine | `waf_stats_record` |

---

## Design Principles

| Principle | Requirement |
|-----------|-------------|
| **Fail closed** | If WAF cannot verify a request, it is blocked |
| **Application-layer** | Inspects HTTP/HTTPS at Layer 7 |
| **OWASP Top 10** | Covers SQLi, XSS, CSRF, file inclusion, command injection, deserialization |
| **Auditability** | Every WAF decision logged through `usrauth/audit` |
| **Observable** | Every component exposes `*_init`, `*_shutdown`, `*_status`, `*_version` |
| **Testable** | Every component ships structural tests and symbol export checks |
| **Pluggable** | Custom rule compiler for WAF rule customization |

---

## Build

```bash
# From security/waf/
make              # assemble all 18 components + test binary
make test         # run skeleton tests (98 checks)
make clean        # remove all .bin files

# From repository root
make -C security/waf all
make -C security/waf test
```

---

## Inspection Pipeline

```
HTTP Request → WAF Dispatcher → HTTP Parser → Signature Detection →
  → SQLi → XSS → CSRF → File Inclusion → Command Injection →
  → Deserialization → Rule Engine → API Protection → Rate Limit →
  → Bot Detection → Session → GeoIP → WAF Engine → SIEM → Stats →
  → Allow / Block / Challenge / Quarantine
```

---

## Roadmap (Implementation)

| Phase | Work |
|-------|------|
| **Phase 1 (skeleton)** | All 18 components compile & link as stubs; tests pass. ← current |
| **Phase 2 (core)** | Implement `init`/`shutdown`/`status`, rule database, rule engine |
| **Phase 3 (detection)** | Implement SQLi, XSS, CSRF, file inclusion, command injection detection |
| **Phase 4 (API & rate)** | API key validation, JWT, rate limiting per IP/key |
| **Phase 5 (bot & session)** | Bot detection, session tracking, geoIP filtering |
| **Phase 6 (SIEM & stats)** | SIEM export, statistics, dashboard data |
| **Phase 7 (integration)** | Wire into kernel HTTP server, IDS alert integration |

---

## License

Apache-2.0 — see `LICENSE` at the repository root.
