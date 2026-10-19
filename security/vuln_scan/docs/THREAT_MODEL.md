# vuln_scan — Threat Model

## Assets

| Asset | Description | Classification |
|-------|-------------|----------------|
| Vulnerability Database | CVE, CWE, advisory data | Confidential |
| Scan Results | Scan findings and results | Confidential |
| Scan Reports | Vulnerability reports | Confidential |
| Target Inventory | List of scanned targets | Internal |

## Threats

| ID | Threat | Target | Impact | Likelihood | Mitigation |
|----|--------|--------|--------|------------|------------|
| VS-T1 | Scan denial of service | Scanner | High | Medium | Rate limiting on scans |
| VS-T2 | False positive findings | Assessor | Medium | Medium | CVSS scoring + validation |
| VS-T3 | Data leakage via egress | Reporter | High | Low | Report access control |
| VS-T4 | Incomplete vulnerability coverage | Scanner | High | Medium | Comprehensive signature database |
| VS-T5 | Database tampering | Database | Critical | Low | Database integrity verification |

## Trust Boundaries

| Boundary | Description | Control |
|----------|-------------|---------|
| Scanner → Target | External boundary | Non-invasive scanning |
| Scanner → Vuln Scan Core | Internal boundary | Target validation |
| Core → Assessor | Internal boundary | Finding validation |
| Core → Reporter | Internal boundary | Scan validation |

## Security Properties

1. **Non-invasive scanning**: Scans must not disrupt target systems.
2. **Accuracy**: Findings must be validated before reporting.
3. **Completeness**: All discovered vulnerabilities must be reported.
4. **Audit trail**: All scans and findings are logged.

## Attack Scenarios

### Scenario: Denial of service via scanning
1. Attacker triggers excessive scans against critical systems.
2. **Mitigation**: Rate limiting and scan scheduling controls.

### Scenario: False positive findings
1. Attacker reports non-existent vulnerabilities.
2. **Mitigation**: CVSS scoring and manual validation before remediation.

### Scenario: Scan result tampering
1. Attacker modifies scan results to hide vulnerabilities.
3. **Mitigation**: Cryptographic signing of scan reports.

### Scenario: Database compromise
1. Attacker modifies vulnerability database to remove known CVEs.
3. **Mitigation**: Database integrity verification and signed updates.

## License
Apache-2.0