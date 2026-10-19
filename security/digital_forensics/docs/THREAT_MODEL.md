# digital_forensics — Threat Model

## Assets

| Asset | Description | Classification |
|-------|-------------|----------------|
| Evidence Store | Acquired disk/memory/file images | Confidential |
| Case Records | Investigation case metadata | Confidential |
| Custody Chain | Chain-of-custody journal entries | Confidential |
| Analysis Results | Forensic analysis findings | Confidential |
| Reports | Generated forensic reports | Confidential |
| Hash Algorithms | SHA-256/SHA-512/BLAKE3 implementations | Internal |

## Threats

| ID | Threat | Target | Impact | Likelihood | Mitigation |
|----|--------|--------|--------|------------|------------|
| DF-T1 | Evidence tampering post-acquisition | Evidence Store | Critical | Low | Write-blocked acquisition + cryptographic hashing |
| DF-T2 | Chain-of-custody break | Custody Chain | Critical | Low | Cryptographic signing of each custody entry |
| DF-T3 | False evidence injection | Acquirer | High | Medium | Source device verification + hash verification |
| DF-T4 | Timing side-channel on analysis | Analyzer | Medium | Low | Constant-time comparison where feasible |
| DF-T5 | Report forgery | Reporter | High | Low | Cryptographic signature on all reports |
| DF-T6 | Evidence hash mismatch | Acquirer | High | Medium | Verify image hash matches source hash |
| DF-T7 | Unauthorized case access | Core | High | Low | Access control on case operations |
| DF-T8 | Denial of service via large acquisition | Acquirer | Medium | High | Size limits + rate limiting on acquisitions |

## Trust Boundaries

| Boundary | Description | Control |
|----------|-------------|---------|
| Source Device → Acquirer | Untrusted storage media | Write-blocker enforcement + hash verification |
| Acquirer → Core | Internal component boundary | Input validation, bounds checking |
| Core → Analyzer | Internal component boundary | Evidence ID validation |
| Analyzer → Core | Internal component boundary | Return verdicts, not raw evidence data |
| Reporter → Output Filesystem | Output destination | Path validation, write permission checks |

## Security Properties

1. **Fail-closed**: If write-blocker cannot be engaged, acquisition aborts rather than proceeding without protection.
2. **Write-blocked acquisition**: All acquisitions default to write-blocked mode to preserve evidence integrity.
3. **Cryptographic hashing**: All evidence is hashed at acquisition time (SHA-256/SHA-512/BLAKE3).
4. **Signed custody chain**: Each custody transfer is cryptographically signed, creating a tamper-evident chain.
5. **Append-only custody**: Custody entries are never modified or deleted, only appended.

## Attack Scenarios

### Scenario: Attacker modifies evidence after acquisition
1. Attacker gains access to acquired evidence image.
2. Attacker modifies incriminating files in the image.
3. **Mitigation**: Evidence hash computed at acquisition; any modification detected on re-verification.

### Scenario: Custody chain break
1. Evidence transferred between analysts without proper documentation.
2. **Mitigation**: Every transfer requires a signed custody entry; broken chain detected on verification.

### Scenario: False evidence planted
1. Attacker with access to source device plants false evidence before acquisition.
2. **Mitigation**: Acquisition captures source as-is; analysis determines authenticity separately from acquisition integrity.

### Scenario: Report tampering
1. Attacker modifies generated forensic report to alter findings.
2. **Mitigation**: Reports are cryptographically signed; signature verification detects tampering.

## License
Apache-2.0