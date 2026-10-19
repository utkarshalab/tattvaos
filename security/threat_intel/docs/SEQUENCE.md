# threat_intel — Sequence Diagrams

## 1. IOC Ingestion Flow

```
+------------+       +--------------+       +-----------+       +-----------+
|   Caller   |       | threat_intel |       | Ingestor  |       |   Store   |
+------------+       +--------------+       +-----------+       +-----------+
     |                       |                       |               |
     |--- threat_intel_ingest() --->|                       |               |
     |                       |--- ti_ingestor_pull_feed() -->|               |
     |                       |                       |               |
     |                       |                       |--- ti_store_add_ioc() -->|
     |                       |                       |               |
     |                       |<--- ti_store_add_ioc() -----|               |
     |                       |                       |               |
     |<--- threat_intel_ingest() ----|                       |               |
     |                       |                       |               |
```

## 2. IOC Lookup Flow

```
+------------+       +--------------+       +-----------+
|   Caller   |       | threat_intel |       |   Store   |
+------------+       +--------------+       +-----------+
     |                       |                       |
     |--- threat_intel_lookup() --->|                       |
     |                       |--- ti_store_lookup_ioc() -->|
     |                       |                       |
     |                       |<--- verdict, IOC ID -----|   |
     |                       |                       |
     |<--- threat_intel_lookup() ----|                       |
     |                       |                       |
```

## 3. Event Correlation Flow

```
+------------+       +--------------+       +-----------+       +-----------+
|   Caller   |       | threat_intel |       |Correlator |       |   Store   |
+------------+       +--------------+       +-----------+       +-----------+
     |                       |                       |               |
     |--- threat_intel_match() --->|                       |               |
     |                       |--- ti_correlator_match_event() -->| |
     |                       |                       |--- ti_store_lookup_ioc() -->|
     |                       |                       |               |
     |                       |                       |<--- verdict -----|   |
     |                       |                       |               |
     |                       |<--- match result ------|               |
     |                       |                       |               |
     |<--- threat_intel_match() ----|                       |               |
     |                       |                       |               |
```

## 4. Intel Export Flow

```
+------------+       +--------------+       +-----------+
|   Caller   |       | threat_intel |       | Exporter  |
+------------+       +--------------+       +-----------+
     |                       |                       |
     |--- threat_intel_subscribe() --->|                       |
     |                       |--- ti_exporter_share_ioc() -->|
     |                       |                       |
     |                       |<--- ti_exporter_share_ioc() -----|
     |                       |                       |
     |<--- threat_intel_subscribe() ----|                       |
     |                       |                       |
```

## 5. Component Initialization Order

```
threat_intel_init()
    |
    +-- ti_store_init()           (component bit: THREAT_INTEL_STORE)
    |
    +-- ti_ingestor_init()        (component bit: THREAT_INTEL_INGESTOR)
    |
    +-- ti_correlator_init()      (component bit: THREAT_INTEL_CORRELATOR)
    |
    +-- ti_exporter_init()        (component bit: THREAT_INTEL_EXPORTER)
    |
    +-- set global state enabled flag
    |
    +-- return success
```

## License
Apache-2.0