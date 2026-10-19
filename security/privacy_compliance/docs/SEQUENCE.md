# privacy_compliance — Sequence Diagrams

## 1. Data Classification Flow

```
+------------+       +--------------+       +-----------+
|   Caller   |       | Privacy Core |       | Classifier|
+------------+       +--------------+       +-----------+
     |                       |                       |
     |--- privacy_classify_data() --->|                       |
     |                       |                       |
     |                       |--- scan data for PII patterns -->|
     |                       |                       |
     |                       |<--- classification ------|   |
     |                       |                       |
     |<--- privacy_classify_data() ----|                       |
     |                       |                       |
```

## 2. Consent Management Flow

```
+------------+       +--------------+       +-----------+
|   Caller   |       | Privacy Core |       | Consent   |
+------------+       +--------------+       +-----------+
     |                       |                       |
     |--- privacy_consent_grant() --->|                       |
     |                       |                       |
     |                       |--- create consent record -->|
     |                       |                       |
     |                       |<--- consent ID ------|   |
     |                       |                       |
     |<--- privacy_consent_grant() ----|                       |
     |                       |                       |
```

## 3. DLP Inspection Flow

```
+------------+       +--------------+       +-----------+
|   Caller   |       | Privacy Core |       | DLP Engine |
+------------+       +--------------+       +-----------+
     |                       |                       |
     |--- privacy_dlp_inspect() --->|                       |
     |                       |                       |
     |                       |--- scan data vs policies -->|
     |                       |                       |
     |                       |<--- action + policy ID --|   |
     |                       |                       |
     |<--- privacy_dlp_inspect() ----|                       |
     |                       |                       |
```

## 4. Report Generation Flow

```
+------------+       +--------------+       +-----------+
|   Caller   |       | Privacy Core |       | Reporter  |
+------------+       +--------------+       +-----------+
     |                       |                       |
     |--- privacy_generate_report() --->|                       |
     |                       |                       |
     |                       |--- gather DLP incidents -->|
     |                       |                       |
     |                       |--- gather consent stats --->|
     |                       |                       |
     |                       |--- gather subject stats --->|
     |                       |                       |
     |                       |--- render report --->|
     |                       |                       |
     |                       |<--- report ID -----|   |
     |                       |                       |
     |<--- privacy_generate_report() ----|                       |
     |                       |                       |
```

## License
Apache-2.0