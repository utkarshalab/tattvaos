# zero_trust — Architecture

## Component Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         Access Request                                      │
│  Subject ──► Object, Verb, Context                                          │
└────────────────┬────────────────────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  zero_trust.asm (Main Dispatcher)                                           │
│  Orchestrates all components, short-circuits on usrauth deny                │
└────────────────┬────────────────────────────────────────────────────────────┘
                 │
    ┌────────────┼────────────┐
    ▼            ▼            ▼
┌──────────┐ ┌──────────┐ ┌──────────┐
│ Policy   │ │ Session  │ │ Posture  │
│ Engine   │ │ Manager  │ │ Checker  │
│ (eval)   │ │ (lifecycle)│ │ (device) │
└────┬─────┘ └────┬─────┘ └────┬─────┘
     │            │            │
     ▼            ▼            ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  Enforcement Point (inline at micro-segment boundaries)                     │
│  ─────────────────────────────────────────────────────────────────────────  │
│  Continuous Auth (re-auth on context change)                                │
└────────────────┬────────────────────────────────────────────────────────────┘
                 │
    ┌────────────┴────────────┐
    ▼                         ▼
┌──────────┐           ┌──────────┐
│ Micro-   │           │ Audit    │
│ Segment- │           │ (usrauth)│
│ ation    │           │          │
└──────────┘           └──────────┘
```

## Layer Diagram (Stack Integration)

```
┌─────────────────────────────────────────────────────────────┐
│  Caller (kernel subsystem, driver, filesystem, network)    │
└─────────────────┬───────────────────────────────────────────┘
                  │ access request
┌─────────────────▼───────────────────────────────────────────┐
│  zero_trust (L2)                                              │
│  Dynamic policy + session + posture + micro-segmentation     │
└─────────────────┬───────────────────────────────────────────┘
                  │ usrauth deny short-circuits here
┌─────────────────▼───────────────────────────────────────────┐
│  usrauth (L1 Reference Monitor)                               │
│  Intersection: token ∩ subject ∩ capability ∩ policy ∩ MAC   │
└─────────────────┬───────────────────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────────────────┐
│  Kernel objects (files, devices, sockets, processes)         │
└─────────────────────────────────────────────────────────────┘
```

## Integration Points

| Interface | Direction | Purpose |
|-----------|-----------|---------|
| `usrauth.audit` | zero_trust → usrauth | Log every allow/deny with reason code |
| `usrauth.subject` | zero_trust → usrauth | Resolve subject handle to subject record |
| `usrauth.capability` | zero_trust → usrauth | Check held capabilities as policy input |
| `ips` | zero_trust → ips | Block traffic at network level when session revoked |
| `ids` | ids → zero_trust | Feed detected anomalies as context change triggers |
| `malwarescan` | malwarescan → zero_trust | Revoke sessions on infected hosts |

## Trust Boundaries

- **Session boundary**: 30s default TTL. Every access within a session still requires policy evaluation.
- **Micro-segment boundary**: Cross-segment traffic requires explicit enforcement point approval.
- **Device posture boundary**: Non-compliant devices cannot create sessions.
- **Context boundary**: IP change, new process, or anomaly triggers re-authentication.
