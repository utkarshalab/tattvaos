# supply_chain — Sequence Diagrams

## 1. Artifact Registration Flow

```
+------------+       +--------------+       +-----------+
|   Caller   |       |   Supply Chain |      |   Store   |
+------------+       +--------------+       +-----------+
     |                       |                       |
     |--- supply_chain_register_artifact() --->|                       |
     |                       |                       |
     |                       |--- assign artifact ID --->|
     |                       |                       |
     |                       |--- insert into list --->|
     |                       |                       |
     |                       |<--- artifact ID ------|   |
     |                       |                       |
     |<--- supply_chain_register_artifact() ----|      |
     |                       |                       |
```

## 2. SBOM Generation Flow

```
+------------+       +--------------+       +-----------+
|   Caller   |       |   Supply Chain |       |   SBOM    |
+------------+       +--------------+       +-----------+
     |                       |                       |
     |--- supply_chain_generate_sbom() --->|                       |
     |                       |                       |
     |                       |--- gather dependencies --->|
     |                       |                       |
     |                       |--- render SBOM ------->|
     |                       |                       |
     |                       |--- write SBOM ------->|
     |                       |                       |
     |                       |<--- SBOM ID -------|   |
     |                       |                       |
     |<--- supply_chain_generate_sbom() ----|          |
     |                       |                       |
```

## 3. Attestation Flow

```
+------------+       +--------------+       +-----------+
|   Caller   |       |   Supply Chain |       | Attestation|
+------------+       +--------------+       +-----------+
     |                       |                       |
     |--- supply_chain_attest_artifact() --->|                       |
     |                       |                       |
     |                       |--- create attestation --->|
     |                       |                       |
     |                       |--- sign artifact --->|
     |                       |                       |
     |                       |<--- attestation ID --|   |
     |                       |                       |
     |<--- supply_chain_attest_artifact() ----|          |
     |                       |                       |
```

## 4. Verification Flow

```
+------------+       +--------------+       +-----------+
|   Caller   |       |   Supply Chain |       | Verification|
+------------+       +--------------+       +-----------+
     |                       |                       |
     |--- supply_chain_verify_artifact() --->|                       |
     |                       |                       |
     |                       |--- verify signature --->|
     |                       |                       |
     |                       |<--- status -------|   |
     |                       |                       |
     |<--- supply_chain_verify_artifact() ----|          |
     |                       |                       |
```

## License
Apache-2.0