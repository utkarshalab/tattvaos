# ips — Threat Model

## Assets Protected

| Asset | Description |
|-------|-------------|
| Network traffic | All packets traversing monitored inline paths |
| Endpoint integrity | Prevent compromised hosts from communicating |
| Service availability | DDoS protection via rate limiting |
| Policy integrity | Allow/deny rules must be tamper-evident |
| Enforcement integrity | Drop/reset/quarantine actions must be auditable |

## Attackers

| Actor | Motivation | Capabilities |
|-------|------------|--------------|
| External attacker | Data theft, ransomware, disruption | Network scanning, exploitation, malware |
| Insider threat | Data exfiltration, sabotage | Legitimate network access, privilege abuse |
| APT group | Espionage, long-term access | Zero-days, C2 infrastructure, social engineering |
| Automated bot | Cryptomining, scanning, DDoS | Scripted attacks, credential stuffing |

## Threats & Mitigations

| Threat | Attack Vector | IPS Mitigation | Residual Risk |
|--------|-------------|----------------|---------------|
| Network reconnaissance | Port scanning, service enumeration | Rate limiting + blocklist | Low (detected + blocked) |
| Exploitation | Buffer overflow, RCE, SQL injection | Policy deny + inspector drop | Medium (depends on signature coverage) |
| Malware C2 | Beaconing to command servers | Blocklist + quarantine | Medium (encrypted C2 hard to detect) |
| Data exfiltration | Large outbound transfers | Rate limit + blocklist | Medium (encrypted exfil hard to detect) |
| Brute force | Repeated login attempts | Rate limiter + blocklist | Low-Medium |
| Protocol abuse | Malformed DNS, HTTP smuggling | Inspector protocol violation detection | Medium |
| Evasion | Fragmentation, encryption, tunneling | Inspector fragmentation handling | High (encrypted traffic limits inspection) |
| IPS evasion | Polymorphic malware, protocol tunneling | Behavioral heuristics + anomaly scoring | High (cat-and-mouse game) |
| Alert flooding | DoS the IPS with noise | Rate limiting + default-deny | Medium |
| Blocklist tampering | Add/remove entries unauthorized | Signed blocklist updates | Low |
| Fail-open bypass | Component crash allows all traffic | IPS_FAIL_CLOSED default | Low (misconfiguration risk) |
| Quarantine escape | Compromised host leaves quarantine | Network VLAN enforcement | Low (network-level control) |

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

## Limitations

1. **Encrypted traffic**: TLS/QUIC/encrypted DNS cannot be inspected without decryption keys. IPS can only see metadata (SNI, packet size, timing).
2. **Evasion**: Fragmentation, out-of-order packets, protocol tunneling can bypass inspection.
3. **Zero-day**: Unknown vulnerabilities have no signatures; relies on anomaly detection which has higher false positive rates.
4. **Performance**: Full packet inspection at 10Gbps+ requires significant CPU; sampling may be needed.
5. **Fail-closed risk**: Misconfiguration can cause availability issues (legitimate traffic blocked).

## Assumptions

- Network traffic passes through IPS inline point (or is mirrored).
- `usrauth/audit` is available for enforcement logging.
- Rule updates are signed and verified before loading.
- SIEM export is best-effort; local event storage is bounded.
- Fail-closed is the default and desired security posture.
