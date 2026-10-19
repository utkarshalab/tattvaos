# waf — Threat Model

## Assets Protected

| Asset | Description |
|-------|-------------|
| Web applications | Web applications hosted behind waf |
| Web traffic | HTTP/HTTPS requests and responses |
| Application data | Data submitted via web forms, APIs, file uploads |
| Application logic | Business logic implemented in web applications |

## Attackers

| Actor | Motivation | Capabilities |
|-------|------------|--------------|
| External attacker | Data theft, ransomware, disruption | Network scanning, exploitation, malware |
| Insider threat | Data exfiltration, sabotage | Legitimate access, privilege abuse |
| APT group | Espionage, long-term access | Zero-days, WAF evasion techniques |
| Automated bot | Scraping, credential stuffing, DDoS | Scripted attacks, headless browsers |

## Threats & Mitigations

| Threat | Attack Vector | waf Mitigation | Residual Risk |
|--------|-------------|----------------|---------------|
| Network reconnaissance | Port scanning, service enumeration | waf rate limiting + blocklist | Low (detected + blocked) |
| Exploitation | Buffer overflow, RCE, SQL injection | Signature matching + behavioral analysis | Medium (depends on signature coverage) |
| Malware C2 | Beaconing to command servers | Blocklist + quarantine | Medium (encrypted C2 hard to detect) |
| Data exfiltration | Large outbound transfers | Rate limit + blocklist | Medium (encrypted exfil hard to detect) |
| Brute force | Repeated login attempts | Rate limiter + blocklist | Low-Medium |
| Protocol abuse | Malformed DNS, HTTP smuggling | waf protocol violation detection | Medium |
| Evasion | Fragmentation, encryption, tunneling | waf inspection + heuristics | High (encrypted traffic limits inspection) |
| waf evasion | Polymorphic malware, protocol tunneling | Behavioral heuristics + anomaly scoring | High (cat-and-mouse game) |
| Alert flooding | DoS the waf with noise | Rate limiting + default-deny | Medium |
| Blocklist tampering | Add/remove entries unauthorized | Signed blocklist updates | Low |
| Fail-open bypass | Component crash allows all traffic | waf_FAIL_CLOSED default | Low (misconfiguration risk) |

## Trust Boundaries

```text\n┌─────────────────────────────────────────────────────────────────────────────┐\n│  TRUST BOUNDARY: waf Enforcement Point                                       │\n│  Outside: Raw network traffic (untrusted)                                    │\n│  Inside: Enforced traffic (validated by policy)                              │\n│  Mitigation: All packets inspected before forwarding                         │\n└─────────────────────────────────────────────────────────────────────────────┘\n\n┌─────────────────────────────────────────────────────────────────────────────┐\n│  TRUST BOUNDARY: Blocklist/Quarantine                                        │\n│  Outside: Endpoint IPs (untrusted until verified)                            │\n│  Inside: Blocked/quarantined state (trusted after verification)              │\n│  Mitigation: Signed blocklist updates, TTL expiry on blocks                  │\n└─────────────────────────────────────────────────────────────────────────────┘\n\n┌─────────────────────────────────────────────────────────────────────────────┐\n│  TRUST BOUNDARY: Rule Updates                                                │\n│  Outside: Rule files from admin/threat intel (untrusted until verified)      │\n│  Inside: Compiled rule database (trusted after verification)                 │\n│  Mitigation: Signature verification on rule updates                          │\n└─────────────────────────────────────────────────────────────────────────────┘\n```

## Limitations

1. **Encrypted traffic**: TLS/QUIC/encrypted DNS cannot be inspected without decryption keys. waf can only see metadata (SNI, packet size, timing).
2. **Evasion**: Fragmentation, out-of-order packets, protocol tunneling can bypass inspection.
3. **Zero-day**: Unknown vulnerabilities have no signatures; relies on anomaly detection which has higher false positive rates.
4. **Performance**: Full packet inspection at 10Gbps+ requires significant CPU; sampling may be needed.
5. **Fail-closed risk**: Misconfiguration can cause availability issues (legitimate traffic blocked).

## Assumptions

- Network traffic passes through waf inline point (or is mirrored).
- `usrauth/audit` is available for enforcement logging.
- Rule updates are signed and verified before loading.
- SIEM export is best-effort; local event storage is bounded.
- Fail-closed is the default and desired security posture.