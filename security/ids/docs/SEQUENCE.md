# ids — Call Flow (Sequence Diagrams)

## 1. Packet Inspection Flow

```
External                      IDS Main            Sensor         Reassembler     Analyzer
Traffic                       Dispatcher                         (TCP/IP)        (Protocol)
  │                           (ids_inspect_packet)                    │
  │──── packet ────────────────►│                                       │
  src_ip, dst_ip, ports,        │                                       │
  proto, payload                │ ids_sensor_capture                    │
  │                           ├───────────────────────────────────────►│
  │                           │                                       │
  │                           │◄───────────────────────────────────────│
  │                           │ packet_ctx filled                      │
  │                           │                                       │
  │                           │ ids_reassembler_add_packet             │
  │                           ├────────────────────────────────────────►│
  │                           │                                       │
  │                           │◄────────────────────────────────────────│
  │                           │ stream_id (or 0)                       │
  │                           │                                       │
  │                           │ ids_analyzer_parse                     │
  │                           ├────────────────────────────────────────►│
  │                           │                                       │
  │                           │◄────────────────────────────────────────│
  │                           │ protocol_id                            │
  │                           │                                       │
  │                           │ ids_rules_match                        │
  │                           ├────────────────────────────────────────►│
  │                           │                                       │
  │                           │◄────────────────────────────────────────│
  │                           │ rule_id (or 0)                         │
  │                           │                                       │
  │                           │ ids_detector_evaluate                  │
  │                           ├────────────────────────────────────────►│
  │                           │                                       │
  │                           │◄────────────────────────────────────────│
  │                           │ anomaly_score                          │
  │                           │                                       │
  │                           │ ids_alert_emit (if threat)             │
  │                           ├────────────────────────────────────────►│
  │                           │                                       │
  │                           │◄────────────────────────────────────────│
  │                           │ alert_id                               │
  │                           │                                       │
  │                           │ ids_siem_export                        │
  │                           ├────────────────────────────────────────►│
  │                           │                                       │
  │                           │◄────────────────────────────────────────│
  │                           │ export_status                          │
  │                           │                                       │
  │                           │ ids_stats_record                       │
  │                           ├────────────────────────────────────────►│
  │                           │                                       │
  │                           │◄────────────────────────────────────────│
  │                           │ stats_status                           │
  │                           │                                       │
  │◄── verdict + reason ────────│                                       │
```

## 2. Alert Generation Flow

```
Detector                      Alert Engine            SIEM Exporter         Audit Log
                              (ids_alert)                              (usrauth/audit)
  │                           ┌──────────────┐   ┌──────────────┐   ┌─────────┐
  │─── threat_score ───────────►│              │   │              │   │         │
  │   anomaly_score             │ ids_alert_emit │   │              │   │         │
  │                           └──────┬────────┘   │              │   │         │
  │                                  │              │              │   │         │
  │                                  │ dedup check │              │   │         │
  │                                  ├─────────────►│              │   │         │
  │                                  │              │              │   │         │
  │                                  │◄─ duplicate? ─┤              │   │         │
  │                                  │              │              │   │         │
  │                                  │ allocate ID │              │   │         │
  │                                  ├─────────────►│              │   │         │
  │                                  │              │              │   │         │
  │                                  │◄── alert_id ──┤              │   │         │
  │                                  │              │              │   │         │
  │                                  │ IDS_EMIT_ALERT│─────────────►│   │         │
  │                                  │              │              │   │         │
  │                                  │              │ export alert │   │   log   │
  │                                  │              ├─────────────►│   │ record  │
  │                                  │              │              │   │         │
  │                                  │              │◄── status ───┤   │         │
  │                                  │              │              │   │         │
  │                                  │◄── alert_id ──┤              │   │         │
  │                                  │              │              │   │         │
  │◄── alert_id ─────────────────────┘              │              │   │         │
```

## 3. Alert Acknowledgment Flow

```
Analyst                     Alert Engine
  │                         (ids_alert)
  │                         ┌──────────────┐
  │─── acknowledge ─────────►│              │
  │   alert_id, new_state   │ ids_alert_ack│
  │                           └──────┬─────┘
  │                                  │
  │                                  │ lookup alert
  │                                  │ update state
  │                                  │
  │                                  │◄── status
  │                                  │
  │◄── ack_result ───────────────────┘
```

## 4. Rule Hot-Reload Flow

```
Admin                      Rules Engine
  │                        (ids_rules)
  │                        ┌──────────────┐
  │─── reload_rules ───────►│              │
  │   rules_file_path      │ ids_rules_load│
  │                        └──────┬────────┘
  │                               │
  │                               │ parse rules
  │                               │ compile patterns
  │                               │ insert into rule list
  │                               │
  │                               │◄── rules_loaded
  │                               │
  │◄── load_result ───────────────┘
```

## 5. Stats Sampling Flow

```
Stats Engine                Stats Snapshot
(ids_stats)                    (ids_stats_t)
  │                           ┌──────────────┐
  │─── record ────────────────►│              │
  │   packet_ctx, verdict      │ increment    │
  │                            │ counters     │
  │                            └──────┬───────┘
  │                                  │
  │                                  │ sample interval elapsed?
  │                                  ├─────────────►
  │                                  │
  │                                  │ take snapshot
  │                                  │ rotate history
  │                                  │
  │                                  │◄── snapshot
  │                                  │
  │◄── record_result ────────────────┘
```

## 6. Threat Correlation Flow

```
Alert Engine                Correlator              Threat Profile
(ids_alert)                 (ids_correlator)          Database
  │                         ┌──────────────┐   ┌──────────────┐
  │─── alert_emitted ───────►│              │   │              │
  │   subject_ip, reason     │ ids_correlat│   │              │
  │                          │ or_update   │   │              │
  │                          └──────┬──────┘   │              │
  │                                 │           │              │
  │                                 │ lookup subject│          │
  │                                 ├───────────►│              │
  │                                 │              │              │
  │                                 │◄── profile ──┤              │
  │                                 │           │              │
  │                                 │ update score│            │
  │                                 ├───────────►│              │
  │                                 │              │              │
  │                                 │◄── threat_score ─┐        │
  │                                 │           │        │        │
  │                                 │ check threshold│        │        │
  │                                 ├───────────►│        │        │
  │                                 │           │        │        │
  │                                 │ escalate if │        │        │
  │                                 │   high score │        │        │
  │                                 │           │        │        │
  │◄── threat_score ────────────────┘           │        │        │
```
