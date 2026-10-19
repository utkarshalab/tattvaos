# incident_response — Sequence Diagrams

## 1. Incident Triage Flow

```
+------------+       +--------------+       +-----------+
|   Caller   |       |   IR Core    |       |  Triage   |
+------------+       +--------------+       +-----------+
     |                       |                       |
     |--- ir_create_incident() --->|                       |
     |                       |                       |
     |                       |--- ir_triage_assess_severity() -->|
     |                       |                       |
     |                       |<--- severity ------|   |
     |                       |                       |
     |<--- ir_create_incident() ----|                       |
     |                       |                       |
```

## 2. Containment Flow

```
+------------+       +--------------+       +-----------+
|   Caller   |       |   IR Core    |       | Containment|
+------------+       +--------------+       +-----------+
     |                       |                       |
     |--- ir_contain_incident() --->|                       |
     |                       |--- ir_containment_isolate_host() -->|
     |                       |                       |
     |                       |<--- action ID ------|   |
     |                       |                       |
     |<--- ir_contain_incident() ----|                       |
     |                       |                       |
```

## 3. Eradication Flow

```
+------------+       +--------------+       +-----------+
|   Caller   |       |   IR Core    |       | Eradication|
+------------+       +--------------+       +-----------+
     |                       |                       |
     |--- ir_eradicate_incident() --->|                       |
     |                       |--- ir_eradication_remove_malware() -->|
     |                       |                       |
     |                       |<--- action ID ------|   |
     |                       |                       |
     |<--- ir_eradicate_incident() ----|                       |
     |                       |                       |
```

## 4. Recovery Flow

```
+------------+       +--------------+       +-----------+
|   Caller   |       |   IR Core    |       |  Recovery |
+------------+       +--------------+       +-----------+
     |                       |                       |
     |--- ir_recover_incident() --->|                       |
     |                       |--- ir_recovery_restore_backup() -->|
     |                       |                       |
     |                       |<--- action ID ------|   |
     |                       |                       |
     |<--- ir_recover_incident() ----|                       |
     |                       |                       |
```

## 5. Playbook Execution Flow

```
+------------+       +--------------+       +-----------+
|   Caller   |       |   IR Core    |       | Playbooks |
+------------+       +--------------+       +-----------+
     |                       |                       |
     |--- ir_playbooks_execute() --->|                       |
     |                       |                       |
     |                       |<--- result ------|   |
     |                       |                       |
     |<--- ir_playbooks_execute() ----|                       |
     |                       |                       |
```

## License
Apache-2.0