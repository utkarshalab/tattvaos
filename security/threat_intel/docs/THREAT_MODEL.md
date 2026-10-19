# threat_intel — Threat Model

## Assets

| Asset | Description | Classification |
|-------|-------------|----------------|
| IOC Store | Database of indicators-of-compromise | Confidential |
| Feeds | External threat intelligence sources | Confidential |
| Match Results | Correlation outcomes between events and IOCs | Confidential |
| Feed Signing Keys | Cryptographic keys for feed verification | Secret |
| Exporter Credentials | Credentials for SIEM/peer sharing | Secret |

## Threats

| ID | Threat | Target | Impact | Likelihood | Mitigation |
|----|--------|--------|--------|------------|------------|
| TI-T1 | Poisoned feed injects false IOCs | IOC Store | High | Medium | Feed signing + signature verification before ingestion |
| TI-T2 | Intel exfiltration via exporter | Exporter | High | Low | Signed, attested sharing channels; peer allowlisting |
| TI-T3 | Timing side-channel on IOC lookup | Store | Medium | Low | Constant-time comparison for indicator matching |
| TI-T4 | Stale IOCs cause false positives | IOC Store | Medium | Medium | TTL-based expiration; soft-delete rather than hard delete |
| TI-T5 | Feed service unavailable | Ingestor | Low | High | Fail-closed: reject new IOCs rather than accept unverified |
| TI-T6 | Correlation engine evasion | Correlator | Medium | Medium | Multi-indicator matching; confidence scoring |
| TI-T7 | Unauthorized IOC modification | Store | High | Low | Access control on store writes; audit logging |
| TI-T8 | Denial of service via feed volume | Ingestor | Low | High | Rate limiting on feed pulls; max IOC count enforcement |

## Trust Boundaries

| Boundary | Description | Control |
|----------|-------------|---------|
| External Feed → Ingestor | Untrusted network feed | Signature verification, format validation |
| Ingestor → Store | Internal component boundary | Input validation, bounds checking |
| Store → Correlator | Internal component boundary | Read-only access to IOC data |
| Correlator → Caller | Internal component boundary | Return verdicts, not raw IOC data |
| Exporter → External Peer/SIEM | Untrusted external party | Cryptographic signing, mutual TLS |

## Security Properties

1. **Fail-closed**: If the store or correlator is not initialized, lookups return `TI_VERDICT_UNKNOWN` rather than `TI_VERDICT_CLEAN`.
2. **Signature verification**: All feeds must be cryptographically verified before IOCs are accepted into the store.
3. **Constant-time lookups**: Indicator comparison uses constant-time operations to prevent timing side-channels.
4. **Append-only store**: IOCs are marked stale (expires set) rather than deleted, preserving audit history.
5. **Attested sharing**: IOCs exported to peers are signed with the exporter's key for authenticity.

## Attack Scenarios

### Scenario: Malicious feed submits IOC for legitimate domain
1. Attacker controls a threat feed and submits `example.com` as a malicious IOC.
2. Ingestor receives feed, verifies signature (valid).
3. IOC added to store with severity HIGH.
4. Legitimate traffic to `example.com` correlates and matches.
5. **Mitigation**: Confidence scoring, multi-source correlation, admin review before blocking.

### Scenario: Timing attack on IOC lookup
1. Attacker submits many lookup requests with slightly different indicators.
2. Measures response times to determine which prefixes match stored IOCs.
3. **Mitigation**: Constant-time string comparison in `ti_store_lookup_ioc()`.

### Scenario: Compromised signing key
1. Attacker obtains feed signing key.
2. Injects false IOCs that pass signature verification.
3. **Mitigation**: Key rotation, multi-signer verification, reputation scoring for feeds.

## License
Apache-2.0