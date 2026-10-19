# waf — Call Flow (Sequence Diagrams)

## 1. Request Inspection Flow (Allow)

```
Client                      waf Main              waf_http
Request                     Dispatcher            Parser
  │                           ┌──────────────┐   ┌──────────────┐
  │──── HTTP Request ─────────►│              │   │              │
  method, url, headers, body   │ waf_inspect  │   │              │
  │                           ├──────────────►│              │   │          │
  │                           │ waf_http_parse│   │              │   │          │
  │                           ├──────────────►│   │              │   │          │
  │                           │              │   │              │   │          │
  │                           │◄─────────────│   │              │   │          │
  │                           │ parsed       │   │              │   │          │
  │                           │              │   │              │   │          │
  │                           │ waf_rule_evaluate│   │              │   │          │
  │                           ├──────────────►│   │              │   │          │
  │                           │              │   │              │   │          │
  │                           │◄─────────────│   │              │   │          │
  │                           │ ALLOW        │   │              │   │          │
  │                           │              │   │              │   │          │
  │                           │ waf_stats_record│   │              │   │          │
  │                           ├──────────────►│   │              │   │          │
  │                           │              │   │              │   │          │
  │                           │◄─────────────│   │              │   │          │
  │                           │ recorded     │   │              │   │          │
  │                           │              │   │              │   │          │
  │◄── ALLOW ─────────────────│              │   │              │   │          │
```

## 2. Request Inspection Flow (Block - SQL Injection)

```
Client                      waf Main              waf_sqli         waf_enforcer
Request                     Dispatcher                         │
  │                           ┌──────────────┐   ┌──────────────┐   ┌──────────┐
  │──── HTTP Request ─────────►│              │   │              │   │          │
  contains SQL injection       │ waf_inspect  │   │              │   │          │
  │                           ├──────────────►│              │   │          │
  │                           │ waf_http_parse│   │              │   │          │
  │                           ├──────────────►│              │   │          │
  │                           │              │   │              │   │          │
  │                           │◄─────────────│   │              │   │          │
  │                           │ parsed       │   │              │   │          │
  │                           │              │   │              │   │          │
  │                           │ waf_sqli_detect│   │              │   │          │
  │                           ├──────────────►│   │              │   │          │
  │                           │              │   │              │   │          │
  │                           │◄─────────────│   │              │   │          │
  │                           │ DETECTED     │   │              │   │          │
  │                           │ rule_id=42   │   │              │   │          │
  │                           │              │   │              │   │          │
  │                           │ waf_enforce  │   │              │   │          │
  │                           │ (BLOCK)      │   │              │   │          │
  │                           ├──────────────►│   │              │   │          │
  │                           │              │   │              │   │          │
  │                           │◄─────────────│   │              │   │          │
  │                           │ blocked      │   │              │   │          │
  │                           │              │   │              │   │          │
  │                           │ waf_siem_export│   │              │   │          │
  │                           ├──────────────►│   │              │   │          │
  │                           │              │   │              │   │          │
  │                           │◄─────────────│   │              │   │          │
  │                           │ exported     │   │              │   │          │
  │                           │              │   │              │   │          │
  │                           │ waf_stats_record│   │              │   │          │
  │                           ├──────────────►│   │              │   │          │
  │                           │              │   │              │   │          │
  │                           │◄─────────────│   │              │   │          │
  │                           │ recorded     │   │              │   │          │
  │                           │              │   │              │   │          │
  │◄── BLOCK ─────────────────│              │   │              │   │          │
```

## 3. Rule Compilation Flow

```
Admin                     WAF Main              Rule Engine
  │                         (waf_rulec)                │
  │                         ┌──────────────┐   ┌──────────┐
  │─── compile_rule ─────────►│              │   │          │
  │   rule_source              │ waf_rulec_compile│   │          │
  │                           ├──────────────►│   │          │
  │                          │              │   │          │
  │                          │ compile rule   │   │          │
  │                          │              │   │          │
  │                          │◄─────────────│   │          │
  │                           rule_id        │   │          │
  │                           │              │   │          │
  │◄── rule_id ──────────────┘              │   │          │
```

## 4. Rate Limit Flow

```
Request                     WAF Main              Rate Limiter
  │                           (waf_inspect)                         │
  │──── request ─────────────►│              │   │          │
  │                           │ waf_rate_check │   │          │
  │                           ├──────────────►│   │          │
  │                           │              │   │          │
  │                           │◄─────────────│   │          │
  │                           │ RATE_LIMITED │   │          │
  │                           │              │   │          │
  │                           │ ACTION_THROTTLE│   │   │   │
  │                           │              │   │              │
  │◄── THROTTLE ─────────────│              │   │              │
```

## 5. IDS → waf Integration Flow

```
IDS Alert                 WAF Main              Rule Engine
  │                         (waf_rulec)                │
  │                         ┌──────────────┐   ┌──────────┐
  │─── threat_detected ─────►│              │   │          │
  │   attack_pattern          │ waf_rulec_compile│   │          │
  │                           ├──────────────►│   │          │
  │                          │              │   │          │
  │                          │ compile rule   │   │          │
  │                          │              │   │          │
  │                          │◄─────────────│   │          │
  │                           rule_id        │   │          │
  │                           │              │   │          │
  │◄── rule_id ──────────────┘              │   │          │
```

Subsequent request matching the IDS-detected pattern:

```
Traffic                    WAF Main              Rule Engine
Packet                     (waf_inspect)                         │
  │                           ┌──────────────┐   ┌──────────┐
  │──── request ─────────────►│              │   │          │
  │                           │ waf_rule_evaluate│   │          │
  │                           ├──────────────►│   │          │
  │                           │              │   │          │
  │                           │◄─────────────│   │          │
  │                           │ BLOCK        │   │          │
  │                           │              │   │          │
  │◄── BLOCK ─────────────────│              │   │          │
```
