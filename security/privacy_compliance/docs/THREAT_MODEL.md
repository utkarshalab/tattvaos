# privacy_compliance — Threat Model

## Assets

| Asset | Description | Classification |
|-------|-------------|----------------|
| Data Subject Records | Personal data subject information | Confidential |
| Consent Records | User consent preferences | Confidential |
| DLP Policies | Data loss prevention policies | Internal |
| DLP Incidents | Data leakage incidents | Confidential |
| Compliance Reports | Regulatory compliance reports | Confidential |

## Threats

| ID | Threat | Target | Impact | Likelihood | Mitigation |
|----|--------|--------|--------|------------|------------|
| PR-T1 | Unauthorized data collection | Data Subjects | Confidential | Medium | Consent verification before processing |
| PR-T2 | Consent forgery | Consent Records | Confidential | Low | Cryptographic signing of consent records |
| PR-T3 | Data leakage via egress | DLP Engine | Critical | Medium | DLP inspection + blocking |
| PR-T4 | False classification | Classifier | Medium | Low | Confidence scoring + human review |
| PR-T5 | Report tampering | Reporter | Confidential | Low | Cryptographic signature on reports |
| PR-T6 | Right to erasure violation | Data Subjects | Confidential | Medium | Automated deletion workflow |
| PR-T7 | Regulatory non-compliance | Reporter | Confidential | Low | Automated report generation |

## Trust Boundaries

| Boundary | Description | Control |
|----------|-------------|---------|
| Data Subject → Core | Internal boundary | Consent verification |
| Core → DLP Engine | Internal boundary | Data validation |
| DLP Engine → External Systems | External boundary | Policy-based blocking |
| Core → Reporter | Internal boundary | Regulation validation |

## Security Properties

1. **Consent required**: No personal data processing without valid consent.
2. **Right to erasure**: Data subjects can request deletion of their data.
3. **DLP enforcement**: Sensitive data is blocked/encrypted/redacted per policy.
4. **Audit trail**: All processing actions are logged and auditable.

## Attack Scenarios

### Scenario: Unauthorized data processing
1. Attacker gains access to data subject records.
2. Attacker processes data without consent.
3. **Mitigation**: Consent check before any processing; withdrawal stops processing.

### Scenario: Data exfiltration via egress
1. Insider attempts to send sensitive data externally.
2. **Mitigation**: DLP engine inspects outbound data and blocks sensitive content.

### Scenario: Consent record tampering
1. Attacker modifies consent records to appear granted.
3. **Mitigation**: Cryptographic signatures on consent records detect tampering.

### Scenario: Misclassified sensitive data
1. Sensitive data classified as public due to classifier error.
3. **Mitigation**: Confidence scoring; low-confidence classifications default to restrictive.

## License
Apache-2.0