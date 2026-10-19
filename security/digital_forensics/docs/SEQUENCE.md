# digital_forensics — Sequence Diagrams

## 1. Evidence Acquisition Flow

```
+------------+       +--------------+       +-----------+       +-----------+
|   Caller   |       |   dfir Core  |       |  Acquirer |       |  Custody  |
+------------+       +--------------+       +-----------+       +-----------+
     |                       |                       |               |
     |--- dfir_acquire_evidence() --->|                       |               |
     |                       |--- dfir_acquirer_acquire_disk() -->| |
     |                       |                       |               |
     |                       |                       |--- custody_log_entry() -->|
     |                       |                       |               |
     |                       |                       |<--- entry ID ------|   |
     |                       |                       |               |
     |<--- dfir_acquire_evidence() ----|                       |
     |                       |                       |               |
```

## 2. Forensic Analysis Flow

```
+------------+       +--------------+       +-----------+
|   Caller   |       |   dfir Core  |       | Analyzer  |
+------------+       +--------------+       +-----------+
     |                       |                       |
     |--- dfir_analyze_evidence() --->|                       |
     |                       |--- dfir_analyzer_carve_filesystem() -->|
     |                       |                       |
     |                       |<--- carved file count -----|   |
     |                       |                       |
     |<--- dfir_analyze_evidence() ----|                       |
     |                       |                       |
```

## 3. Chain-of-Custody Transfer Flow

```
+------------+       +--------------+       +-----------+
|   Caller   |       |   dfir Core  |       |  Custody  |
+------------+       +--------------+       +-----------+
     |                       |                       |
     |--- dfir_custody_transfer() --->|                       |
     |                       |--- dfir_custody_log_entry() -->|
     |                       |                       |
     |                       |<--- entry ID ------|   |
     |                       |                       |
     |<--- dfir_custody_transfer() ----|                       |
     |                       |                       |
```

## 4. Report Generation Flow

```
+------------+       +--------------+       +-----------+
|   Caller   |       |   dfir Core  |       | Reporter  |
+------------+       +--------------+       +-----------+
     |                       |                       |
     |--- dfir_generate_report() --->|                       |
     |                       |--- dfir_reporter_generate_pdf() -->|
     |                       |                       |
     |                       |<--- report ID ------|   |
     |                       |                       |
     |<--- dfir_generate_report() ----|                       |
     |                       |                       |
```

## 5. Component Initialization Order

```
dfir_init()
    |
    +-- dfir_custody_init()           (component bit: DFIR_CUSTODY)
    |
    +-- dfir_acquirer_init()          (component bit: DFIR_ACQUIRER)
    |
    +-- dfir_analyzer_init()          (component bit: DFIR_ANALYZER)
    |
    +-- dfir_reporter_init()          (component bit: DFIR_REPORTER)
    |
    +-- set global state enabled flag
    |
    +-- return success
```

## License
Apache-2.0