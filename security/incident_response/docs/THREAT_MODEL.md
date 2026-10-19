# incident_response — Threat Model

## Assets

| Asset | Description | Classification |
|-------|-------------|----------------|
| Incident Records | Investigation case metadata | Confidential |
| Containment Actions | Host isolation, session revocation logs | Confidential |
| Eradication Actions | Malware removal, patch records | Confidential |
| Recovery Actions | Backup restoration records | Confidential |
| Playbooks | Response procedures and procedures | Internal |

## Threats

| ID | Threat | Target | Impact | Likelihood | Mitigation |
|----|--------|--------|--------|------------|------------|
| IR-T1 | Delayed incident response | Core | High | Medium | SLA enforcement + automated triage |
| IR-T2 | Incomplete containment | Containment | Critical | Medium | Verification step after each action |
| IR-T3 | Incomplete eradication | Eradication | Critical | Medium | Verification step + re-scan |
| IR-T4 | Premature recovery | Recovery | High | Low | Validate eradication before recovery |
| IR-T5 | Playbook misconfiguration | Playbooks | Medium | Medium | Playbook validation before assignment |
| IR-T6 | Unauthorized incident access | Core | High | Low | Access control on incident operations |

## Trust Boundaries

| Boundary | Description | Control |
|----------|-------------|---------|
| Detection → IR Core | Internal boundary | Incident validation |
| IR Core → Containment | Internal boundary | Incident ID validation |
| Containment → Target Systems | External boundary | Authentication + authorization |
| IR Core → Recovery | Internal boundary | Status validation (must be eradicated) |

## Security Properties

1. **Fail-closed**: If containment cannot be verified, incident remains open and escalated.
2. **Sequential phases**: Each phase (triage, contain, eradicate, recover) must complete before next.
3. **Verification required**: Each action must be verified before proceeding.
4. **Audit trail**: All actions are logged with timestamps and actor attribution.

## Attack Scenarios

### Scenario: Incomplete malware eradication
1. Attacker establishes persistence mechanism on host.
2. Responder removes visible malware but misses persistence.
3. **Mitigation**: Eradication verification step includes persistence scan.

### Scenario: Recovery before eradication complete
1. Responder restores systems before confirming threat removal.
2. **Mitigation**: Status validation prevents recovery until eradication confirmed.

### Scenario: Playbook misconfiguration
1. Wrong playbook assigned to incident type.
2. **Mitigation**: Playbook validation before assignment and execution.

## License
Apache-2.0