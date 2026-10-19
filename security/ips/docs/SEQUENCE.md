# ips — Call Flow (Sequence Diagrams)

## 1. Enforcement Flow (Allow)

```
External                      IPS Main            Inspector         Enforcer       Policy
Traffic                       Dispatcher                         │               (evaluate)
  │                           ┌──────────────┐   ┌──────────────┐   ┌──────────┐
  │──── packet ───────────────►│              │   │              │   │          │
  src_ip, dst_ip, ports,       │ ips_enforce  │   │              │   │          │
  proto, action_hint           │              │   │              │   │          │
  │                           ├──────────────►│              │   │          │
  │                           │ ips_bypass_  │   │              │   │          │
  │                           │ check        │   │              │   │          │
  │                           │◄─────────────│   │              │   │          │
  │                           │ bypass=0     │   │              │   │          │
  │                           │              │   │              │   │          │
  │                           │ ips_blocklist│   │              │   │          │
  │                           │ _check       │   │              │   │          │
  │                           ├──────────────►│              │   │          │
  │                           │              │   │              │   │          │
  │                           │◄─────────────│   │              │   │          │
  │                           │ not blocked  │   │              │   │          │
  │                           │              │   │              │   │          │
  │                           │ ips_policy_  │   │              │   │          │
  │                           │ evaluate     │   │              │   │          │
  │                           ├──────────────►│              │   │          │
  │                           │              │   │              │   │          │
  │                           │◄─────────────│   │              │   │          │
  │                           │ ALLOW        │   │              │   │          │
  │                           │              │   │              │   │          │
  │                           │ ips_inspecto │   │              │   │          │
  │                           │ r_inspect    │   │              │   │          │
  │                           ├──────────────►│   │              │   │          │
  │                           │              │   │              │   │          │
  │                           │◄─────────────│   │              │   │          │
  │                           │ clean        │   │              │   │          │
  │                           │              │   │              │   │          │
  │                           │ ips_enforcer │   │              │   │          │
  │                           │ _apply_actio │   │              │   │          │
  │                           │ n            │   │              │   │          │
  │                           ├──────────────►│   │              │   │          │
  │                           │              │   │              │   │          │
  │                           │◄─────────────│   │              │   │          │
  │                           │ applied      │   │              │   │          │
  │                           │              │   │              │   │          │
  │                           │ ips_stats_r  │   │              │   │          │
  │                           │ ecord        │   │              │   │          │
  │                           ├──────────────►│   │              │   │          │
  │                           │              │   │              │   │          │
  │                           │◄─────────────│   │              │   │          │
  │                           │ recorded     │   │              │   │          │
  │                           │              │   │              │   │          │
  │◄── ALLOW ─────────────────│              │   │              │   │          │
```

## 2. Enforcement Flow (Drop - Blocklist)

```
Traffic                    IPS Main            Blocklist        Enforcer
Packet                     (ips_enforce)                         │
  │                           ┌──────────────┐   ┌──────────────┐   ┌──────────┐
  │──── packet ───────────────►│              │   │              │   │          │
  blocked_ip                   │ ips_enforce  │   │              │   │          │
  │                           ├──────────────►│              │   │          │
  │                           │ ips_bypass_  │   │              │   │          │
  │                           │ check        │   │              │   │          │
  │                           ├──────────────►│              │   │          │
  │                           │              │   │              │   │          │
  │                           │◄─────────────│   │              │   │          │
  │                           │ bypass=0     │   │              │   │          │
  │                           │              │   │              │   │          │
  │                           │ ips_blocklist│   │              │   │          │
  │                           │ _check       │   │              │   │          │
  │                           ├──────────────►│   │              │   │          │
  │                           │              │   │              │   │          │
  │                           │◄─────────────│   │              │   │          │
  │                           │ BLOCKED      │   │              │   │          │
  │                           │              │   │              │   │          │
  │                           │ ips_enforcer │   │              │   │          │
  │                           │ _apply_actio │   │              │   │          │
  │                           │ n(DROP)      │   │              │   │          │
  │                           ├──────────────►│   │              │   │          │
  │                           │              │   │              │   │          │
  │                           │◄─────────────│   │              │   │          │
  │                           │ dropped      │   │              │   │          │
  │                           │              │   │              │   │          │
  │                           │ ips_stats_r  │   │              │   │          │
  │                           │ ecord        │   │              │   │          │
  │                           ├──────────────►│   │              │   │          │
  │                           │              │   │              │   │          │
  │                           │◄─────────────│   │              │   │          │
  │                           │ recorded     │   │              │   │          │
  │                           │              │   │              │   │          │
  │◄── DROP ──────────────────│              │   │              │   │          │
```

## 3. Enforcement Flow (Fail-Closed - Component Down)

```
Traffic                    IPS Main            Enforcer
Packet                     (ips_enforce)                         │
  │                           ┌──────────────┐   ┌──────────────┐
  │──── packet ───────────────►│              │   │              │
  │                           │ ips_bypass_  │   │              │
  │                           │ check        │   │              │
  │                           ├──────────────►│              │   │
  │                           │              │   │              │
  │                           │◄─────────────│   │              │
  │                           │ bypass=0     │   │              │
  │                           │              │   │              │
  │                           │ ips_policy_  │   │              │
  │                           │ evaluate     │   │              │
  │                           ├──────────────►│              │   │
  │                           │              │   │              │
  │                           │◄─────────────│   │              │
  │                           │ COMPONENT    │   │              │
  │                           │ DOWN         │   │              │
  │                           │              │   │              │
  │                           │ fail_mode=CLOSED│   │   │   │   │
  │                           │              │   │              │
  │                           │ ACTION_DROP  │   │              │
  │                           │ reason=COMPONENT_DOWN│   │   │   │
  │                           │              │   │              │
  │◄── DROP ──────────────────│              │   │              │
```

## 4. Blocklist Add Flow

```
Admin                     IPS Main            Blocklist
  │                         (ips_blocklist)                │
  │                         ┌──────────────┐   ┌──────────┐
  │─── add_block ───────────►│              │   │          │
  │   ip, reason, duration   │ ips_blocklis │   │          │
  │                          │ t_add        │   │          │
  │                          ├──────────────►│   │          │
  │                          │              │   │          │
  │                          │ allocate entry│   │          │
  │                          │              │   │          │
  │                          │◄─────────────│   │          │
  │                           added        │   │          │
  │                           │              │   │          │
  │◄── added ─────────────────┘              │   │          │
```

## 5. Quarantine Isolate Flow

```
Alert/Event               IPS Main            Quarantine
  │                         (ips_quarantine)              │
  │                         ┌──────────────┐   ┌──────────┐
  │─── isolate ─────────────►│              │   │          │
  │   ip, reason             │ ips_quaranti │   │          │
  │                          │ ne_isolate   │   │          │
  │                          ├──────────────►│   │          │
  │                          │              │   │          │
  │                          │ redirect to  │   │          │
  │                          │ quarantine   │   │          │
  │                          │ VLAN         │   │          │
  │                          │              │   │          │
  │                          │◄─────────────│   │          │
  │                           isolated      │   │          │
  │                           │              │   │          │
  │◄── isolated ──────────────┘              │   │          │
```

## 6. Rate Limit Flow

```
Traffic                    IPS Main            Rate Limiter
Packet                     (ips_enforce)                         │
  │                           ┌──────────────┐   ┌──────────┐
  │──── packet ───────────────►│              │   │          │
  │                           │ ips_rate_li  │   │          │
  │                           │ miter_check  │   │          │
  │                           ├──────────────►│   │          │
  │                           │              │   │          │
  │                           │◄─────────────│   │          │
  │                           │ RATE_LIMITED │   │          │
  │                           │ retry_after  │   │          │
  │                           │              │   │          │
  │                           │ ACTION_THROTTLE│   │   │   │
  │                           │              │   │              │
  │◄── THROTTLE ───────────────│              │   │              │
```

## 7. Connection Tracking Flow

```
Traffic                    IPS Main            Conn Tracker
Packet                     (ips_enforce)                         │
  │                           ┌──────────────┐   ┌──────────┐
  │──── new connection ───────►│              │   │          │
  │   5-tuple                  │ ips_connecti │   │          │
  │                           │ on_tracker_  │   │          │
  │                           │ track        │   │          │
  │                           ├──────────────►│   │          │
  │                           │              │   │          │
  │                           │ create entry │   │          │
  │                           │              │   │          │
  │                           │◄─────────────│   │          │
  │                           │ conn_id=1    │   │          │
  │                           │              │   │          │
  │◄── tracked ────────────────┘              │   │          │
```

## 8. SIEM Export Flow

```
Enforcement               IPS Main            SIEM
Event                     (ips_siem)                         │
  │                         ┌──────────────┐   ┌──────────┐
  │─── export ───────────────►│              │   │          │
  │   action, reason, ips   │ ips_siem_ex  │   │          │
  │                         │ port         │   │          │
  │                           ├──────────────►│   │          │
  │                           │              │   │          │
  │                           │ serialize    │   │          │
  │                           │ CEF format   │   │          │
  │                           │              │   │          │
  │                           │ send to SIEM │   │          │
  │                           │              │   │          │
  │                           │◄─────────────│   │          │
  │                           │ sent         │   │          │
  │                           │              │   │          │
  │◄── exported ───────────────┘              │   │          │
```

## 9. IDS → IPS Integration Flow

```
IDS Alert                 IPS Main            Policy Engine
  │                         (ips_policy)                         │
  │                         ┌──────────────┐   ┌──────────┐
  │─── threat_detected ─────►│              │   │          │
  │   src_ip, reason         │ ips_policy_  │   │          │
  │                          │ load         │   │          │
  │                          ├──────────────►│   │          │
  │                          │              │   │          │
  │                          │ create DENY  │   │          │
  │                          │ rule for     │   │          │
  │                          │ src_ip       │   │          │
  │                          │              │   │          │
  │                          │◄─────────────│   │          │
  │                           rule_added    │   │          │
  │                           │              │   │          │
  │◄── policy_updated ─────────┘              │   │          │
```

Subsequent traffic from the blocked IP:

```
Traffic                    IPS Main            Policy
Packet                     (ips_enforce)                         │
  │                           ┌──────────────┐   ┌──────────┐
  │──── from blocked IP ──────►│              │   │          │
  │                           │ ips_policy_  │   │          │
  │                           │ evaluate     │   │          │
  │                           ├──────────────►│   │          │
  │                           │              │   │          │
  │                           │◄─────────────│   │          │
  │                           │ DENY         │   │          │
  │                           │              │   │          │
  │◄── DROP ───────────────────│              │   │          │
```
