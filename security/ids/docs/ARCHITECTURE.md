# ids — Architecture

## Component Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         Traffic Sources                                       │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐                          │
│  │  NIC    │  │ Syscall │  │  Logs   │  │  API    │                          │
│  │ (eth0)  │  │  Audit  │  │  Files  │  │  Calls  │                          │
│  └────┬────┘  └────┬────┘  └────┬────┘  └────┬────┘                          │
└─────────┼──────────┼──────────┼──────────┼─────────────────────────────────┘
          │          │          │          │
          └──────────┴──────────┴──────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  ids.asm — Main Dispatcher                                                   │
│  Inspection Pipeline Orchestrator                                            │
│  ─────────────────────────────────────────────────────────────────────────  │
│  1. Validate state + input                                                   │
│  2. Increment packet counter                                                 │
│  3. Call each component in pipeline order                                    │
│  4. Return verdict + reason code                                             │
└───────────┬──────────────────────────────────────────────────────────────────┘
            │
    ┌───────┴───────┬───────────┬───────────┬───────────┐
    ▼               ▼           ▼           ▼           ▼
┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐
│ Sensor   │  │ Reasmblr │  │ Analyzer │  │ Rules    │  │ Detector │
│ capture  │  │ reassembly│  │ protocol │  │ signatures│ │ anomaly  │
│          │  │          │  │ parsing  │  │ matching  │ │ heuristic│
└────┬─────┘  └────┬────┘  └────┬────┘  └────┬─────┘  └────┬─────┘
     │               │           │           │           │
     └───────────────┴───────────┴───────────┴───────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  Alert Engine (ids_alert)                                                    │
│  Deduplication → Severity → State → Audit Log                                │
└───────────┬──────────────────────────────────────────────────────────────────┘
            │
    ┌───────┴───────────┐
    ▼                   ▼
┌──────────┐      ┌──────────┐
│ Correlator│      │   SIEM   │
│ threat   │      │ export   │
│ score    │      │ (CEF/    │
│          │      │  LEEF/   │
│          │      │  JSON/   │
│          │      │  SYSLOG) │
└──────────┘      └──────────┘
            │
            ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  Stats Engine (metrics, thresholds, baselines)                               │
│  Feeds back into detector thresholds and alert severity scoring              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Layer Diagram (Stack Integration)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Kernel Network Stack (net/, ips/, etc.)                                     │
└─────────────────────────┬────────────────────────────────────────────────────┘
                          │ packet copy (read-only)
┌─────────────────────────▼────────────────────────────────────────────────────┐
│  ids (IDS — Detection Only)                                                  │
│  Passive monitoring. Never modifies or drops packets.                        │
└─────────────────────────┬────────────────────────────────────────────────────┘
                          │ alert → audit log
┌─────────────────────────▼────────────────────────────────────────────────────┐
│  usrauth (Reference Monitor) — audit decision log                            │
└─────────────────────────┬────────────────────────────────────────────────────┘
                          │ alert → block decision
┌─────────────────────────▼────────────────────────────────────────────────────┐
│  ips (IPS — Prevention)                                                      │
│  Active blocking based on IDS alerts + policy                                │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Integration Points

| Interface | Direction | Purpose |
|-----------|-----------|---------|
| `kernel/net/` | ids → net | Read-only packet tap (mirror/copy) |
| `usrauth/audit` | ids → usrauth | Log every alert with reason code |
| `ips` | ids → ips | Feed alerts for blocking decisions |
| `threat_intel` | threat_intel → ids | IOCs fed into rules engine |
| `usrauth` | ids → usrauth | Subject context for alert attribution |

## Trust Boundaries

- **IDS boundary**: IDS runs in kernel context but has read-only access to packet data. It cannot modify traffic.
- **Alert boundary**: Alerts are written to an append-only audit log; they cannot be modified or deleted after creation.
- **SIEM boundary**: Export is best-effort; if SIEM is unreachable, alerts are queued locally and may be dropped when queue is full.

## Data Flow (Read-Only)

```
Network Card → Ring Buffer → Sensor → [Read-only pipeline] → Alert → Audit Log
                                    ↑
                              No packet modification possible
```
