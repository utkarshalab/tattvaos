# ids — Threat Model

## Assets Protected

| Asset | Description |
|-------|-------------|
| Network traffic | All packets traversing monitored interfaces |
| Host activity | System calls, process execution, file access |
| Application data | HTTP requests, DNS queries, TLS handshakes, SMB shares |
| Alert integrity | Alert records must be tamper-evident and complete |
| Detection accuracy | False positives and false negatives must be minimized |

## Attackers

| Actor | Motivation | Capabilities |
|-------|------------|--------------|
| External attacker | Data theft, ransomware, disruption | Network scanning, exploitation, malware |
| Insider threat | Data exfiltration, sabotage | Legitimate access, privilege abuse |
| APT group | Espionage, long-term access | Zero-days, C2 infrastructure, social engineering |
| Automated bot | Cryptomining, scanning, DDoS | Scripted attacks, credential stuffing |

## Threats & Mitigations

| Threat | Attack Vector | IDS Mitigation | Residual Risk |
|--------|-------------|----------------|---------------|
| Network reconnaissance | Port scanning, service enumeration | `IDS_REASON_SCAN_DETECTED` — detect port scans | Low (detected, not blocked) |
| Exploitation | Buffer overflow, RCE, SQL injection | Signature matching (`IDS_REASON_SIGNATURE_MATCH`) | Medium (depends on signature coverage) |
| Malware C2 | Beaconing to command servers | `IDS_REASON_MALWARE_C2` — periodic connection detection | Medium (encrypted C2 hard to detect) |
| Data exfiltration | Large outbound transfers | `IDS_REASON_DATA_EXFILTRATION` — volume threshold | Medium (encrypted exfil hard to detect) |
| Brute force | Repeated login attempts | `IDS_REASON_BRUTE_FORCE` — auth failure counting | Low-Medium |
| Protocol abuse | Malformed DNS, HTTP smuggling | `IDS_REASON_PROTOCOL_VIOLATION` | Medium |
| Evasion | Fragmentation, encryption, tunneling | Reassembler + encrypted payload flagging | High (encrypted traffic limits inspection) |
| IDS evasion | Polymorphic malware, protocol tunneling | Behavioral heuristics + anomaly scoring | High (cat-and-mouse game) |
| Alert flooding | DoS the IDS with noise | Deduplication window, rate limiting | Medium |
| Alert tampering | Modify or delete alerts | Append-only audit log via `usrauth/audit` | Low |

## Trust Boundaries

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  TRUST BOUNDARY: IDS Sensor                                                  │
│  Outside: Raw network traffic (untrusted)                                    │
│  Inside: Packet context structs (validated)                                  │
│  Mitigation: Validate all packet fields before processing                    │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│  TRUST BOUNDARY: Alert Output                                                │
│  Inside: IDS alert engine (trusted)                                          │
│  Outside: SIEM, audit log, IPS (partially trusted)                           │
│  Mitigation: Sign/cryptographically bind alert records                       │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│  TRUST BOUNDARY: Rule Updates                                                │
│  Outside: Rule files from admin/threat intel (untrusted until verified)      │
│  Inside: Compiled rule database (trusted after validation)                   │
│  Mitigation: Signature verification on rule updates                          │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Limitations

1. **Encrypted traffic**: TLS/QUIC/encrypted DNS cannot be inspected without decryption keys. IDS can only see metadata (SNI, packet size, timing).
2. **Evasion**: Fragmentation, out-of-order packets, protocol tunneling can bypass signature matching.
3. **Zero-day**: Unknown vulnerabilities have no signatures; relies on anomaly detection which has higher false positive rates.
4. **Performance**: Full packet inspection at 10Gbps+ requires significant CPU; sampling may be needed.
5. **Detection only**: IDS cannot stop an attack in progress; it can only alert. Response requires IPS/SOAR integration.

## Assumptions

- Network interfaces are in promiscuous mode or traffic is mirrored to IDS.
- `usrauth/audit` is available for alert logging.
- Rule updates are signed and verified before loading.
- SIEM export is best-effort; local alert storage is bounded.
