# vuln_scan — Sequence Diagrams

## 1. Target Registration Flow

```
+------------+       +--------------+       +-----------+
|   Caller   |       |  Vuln Scan   |       |   State   |
+------------+       +--------------+       +-----------+
     |                       |                       |
     |--- vuln_scan_register_target() --->|                       |
     |                       |                       |
     |                       |--- assign target ID --->|
     |                       |                       |
     |                       |--- insert into list --->|
     |                       |                       |
     |                       |<--- target ID ------|   |
     |                       |                       |
     |<--- vuln_scan_register_target() ----|          |
     |                       |                       |
```

## 2. Vulnerability Scan Flow

```
+------------+       +--------------+       +-----------+
|   Caller   |       |   Vuln Scan    |       |  Scanner  |
+------------+       +--------------+       +-----------+
     |                       |                       |
     |--- vuln_scan_run_scan() --->|                       |
     |                       |                       |
     |                       |--- perform scan --->|
     |                       |                       |
     |                       |--- create findings --->|
     |                       |                       |
     |                       |<--- scan ID -------|   |
     |                       |                       |
     |<--- vuln_scan_run_scan() ----|            |
     |                       |                       |
```

## 3. Vulnerability Assessment Flow

```
+------------+       +--------------+       +-----------+
|   Caller   |       | Vuln Scan    |       | Assessor  |
+------------+       +--------------+       +-----------+
     |                       |                       |
     |--- vuln_scan_assess_finding() --->|                       |
     |                       |                       |
     |                       |--- calculate CVSS score --->|
     |                       |                       |
     |                       |<--- severity -------|   |
     |                       |                       |
     |<--- vuln_scan_assess_finding() ----|            |
     |                       |                       |
```

## 4. Report Generation Flow

```
+------------+       +--------------+       +-----------+
|   Caller   |       | Vuln Scan    |       | Reporter  |
+------------+       +--------------+       +-----------+
     |                       |                       |
     |--- vuln_scan_generate_report() --->|                       |
     |                       |                       |
     |                       |--- gather scan results --->|
     |                       |                       |
     |                       |--- render report --->|
     |                       |                       |
     |                       |<--- report ID -----|   |
     |                       |                       |
     |<--- vuln_scan_generate_report() ----|            |
     |                       |                       |
```

## License
Apache-2.0