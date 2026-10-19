# supply_chain — Threat Model

## Assets

| Asset | Description | Classification |
|-------|-------------|----------------|
| Artifact Store | Acquired disk/memory/file images | Confidential |
| SBOMs | Software Bill of Materials | Internal |
| Attestations | Signed attestations for artifacts | Confidential |
| Provenance Records | Build provenance information | Confidential |
| Signer Keys | Signer cryptographic keys | Secret |

## Threats

| ID | Threat | Target | Impact | Likelihood | Mitigation |
|----|--------|--------|--------|------------|------------|
| SC-T1 | Malicious artifact injection | Artifacts | Critical | Medium | Signature verification before load |
| SC-T2 | Supply chain compromise | Attestations | Critical | Medium | Trusted signer verification |
| SC-T3 | Unverified artifact execution | Verification | Critical | High | Fail-closed: unverified artifacts rejected |
| SC-T4 | SBOM tampering | SBOMs | High | Low | Cryptographic signing of SBOMs |
| SC-T5 | Provenance forgery | Provenance Records | Medium | Medium | Signer attestation verification |

## Trust Boundaries

| Boundary | Description | Control |
|----------|-------------|---------|
| Build System → Supply Chain | Internal boundary | Build environment attestation |
| Supply Chain → Artifact Store | Internal boundary | Artifact validation |
| Signer → Supply Chain | External boundary | Signer key verification |
| Verification → Loader | Internal boundary | Verification status check |

## Security Properties

1. **Fail-closed**: Unverified artifacts are rejected before loading.
2. **Signature verification**: All artifacts must be cryptographically signed.
3. **SBOM tracking**: All artifacts have a corresponding SBOM.
4. **Attestation required**: All artifacts must have a valid attestation from a trusted signer.

## Attack Scenarios

### Scenario: Malicious artifact injection
1. Attacker submits malicious artifact to supply chain.
2. **Mitigation**: Artifact must have valid attestation from trusted signer before loading.

### Scenario: Compromised build system
1. Attacker compromises build system and injects malicious code.
2. **Mitigation**: Provenance records track build environment; attestation verifies integrity.

### Scenario: Unsigned artifact execution
1. Unsigned artifact is loaded into runtime.
2. **Mitigation**: Fail-closed: unverified artifacts are rejected before loading.

### Scenario: SBOM tampering
1. Attacker modifies SBOM to hide malicious components.
3. **Mitigation**: SBOMs are cryptographically signed; signature verification detects tampering.

## License
Apache-2.0