# zero_trust — Call Flow (Sequence Diagrams)

## 1. Access Request Flow

```
Subject                          zero_trust          usrauth       Enforcement
  │                              Dispatcher           (Reference     Point
  │                              (zt_evaluate_access) Monitor)          
  │                              ┌──────────────┐   ┌─────────────┐ ┌─────────┐
  │──── access_req ─────────────►│              │   │             │ │         │
  subj, obj, verb, ctx           │ zt_init      │   │             │ │         │
  │                              │ (if not yet) │   │             │ │         │
  │                              └──────┬───────┘   └──────┬──────┘ └────┬────┘
  │                                     │                  │             │
  │                                     │ usrauth_check    │             │
  │                                     ├─────────────────►│             │
  │                                     │                  │             │
  │                                     │◄── deny / allow ─┤             │
  │                                     │                  │             │
  │                              ┌──────┴───────┐          │             │
  │                              │ usrauth allow?│─────────┘             │
  │                              └──────┬───────┘                      │
  │                                     │ yes                           │
  │                                     │                               │
  │                              ┌──────┴───────┐                       │
  │                              │ create/lookup │                       │
  │                              │ trust session │                       │
  │                              └──────┬───────┘                       │
  │                                     │                               │
  │                              ┌──────┴───────┐                       │
  │                              │ posture check │                       │
  │                              └──────┬───────┘                       │
  │                                     │                               │
  │                              ┌──────┴───────┐                       │
  │                              │ enforce at   │───────────────────────┘
  │                              │ boundary     │                         │
  │                              └──────┬───────┘                         │
  │                                     │                                 │
  │                              ┌──────┴───────┐                         │
  │                              │ allow / deny │                         │
  │                              └──────┬───────┘                         │
  │                                     │                                 │
  │                              ┌──────┴───────┐                         │
  │                              │ audit log    │─────────────────────────┘
  │                              └──────┬───────┘                         │
  │                                     │                                 │
  │◄── verdict + reason ───────────────┘                                  │
```

## 2. Trust Session Lifecycle

```
Subject                          Policy Admin       Session Manager     Posture
  │                              (zt_policy_admin)   (zt_session_mgr)    Checker
  │                              ┌──────────────┐   ┌──────────────┐   ┌─────────┐
  │──── create_session ─────────►│              │   │              │   │         │
  subject, context, ttl          │ session_create│   │              │   │         │
  │                              └──────┬───────┘   └──────┬───────┘   └────┬────┘
  │                                     │                  │             │
  │                                     │ check_posture    │             │
  │                                     ├─────────────────►│             │
  │                                     │                  │             │
  │                                     │◄── compliant ─────┤             │
  │                                     │                  │             │
  │                              ┌──────┴───────┐          │             │
  │                              │ allocate_id  │          │             │
  │                              └──────┬───────┘          │             │
  │                                     │                  │             │
  │                              ┌──────┴───────┐          │             │
  │                              │ store_session│─────────►│             │
  │                              └──────┬───────┘          └─────────────┘
  │                                     │
  │                              ┌──────┴───────┐
  │                              │ session_id   │
  │                              └──────┬───────┘
  │                                     │
  │◄── session_id ──────────────────────┘
```

## 3. Continuous Re-authentication

```
Context Change                    Continuous Auth   Session Manager   zero_trust
  │                              (zt_continuous)    (zt_session_mgr)    Dispatcher
  │                              ┌──────────────┐   ┌──────────────┐   ┌─────────┐
  │──── new_context ────────────►│              │   │              │   │         │
  subject, context_change        │ check_context│   │              │   │         │
  │                              └──────┬───────┘   └──────┬───────┘   └────┬────┘
  │                                     │                  │             │
  │                                     │ reauth_required? │             │
  │                              ┌──────┴───────┐          │             │
  │                              │ yes           │          │             │
  │                              └──────┬───────┘          │             │
  │                                     │                  │             │
  │                              ┌──────┴───────┐          │             │
  │                              │ reauthenticate│─────────►│             │
  │                              └──────┬───────┘          │             │
  │                                     │                  │             │
  │                              ┌──────┴───────┐          │             │
  │                              │ update_session│─────────►│             │
  │                              └──────┬───────┘          └─────────────┘
  │                                     │
  │                              ┌──────┴───────┐
  │                              │ refreshed    │
  │                              └──────┬───────┘
  │                                     │
  │◄── reauth_result ───────────────────┘
```

## 4. Session Revocation

```
Admin/Event                      Policy Admin       Session Manager   Enforcement
                                 (zt_policy_admin)   (zt_session_mgr)    Point
  │                              ┌──────────────┐   ┌──────────────┐   ┌─────────┐
  │──── revoke_session ─────────►│              │   │              │   │         │
  session_id                     │ session_revoke│   │              │   │         │
  │                              └──────┬───────┘   └──────┬───────┘   └────┬────┘
  │                                     │                  │             │
  │                              ┌──────┴───────┐          │             │
  │                              │ mark_revoked │─────────►│             │
  │                              └──────┬───────┘          └─────────────┘
  │                                     │
  │                              ┌──────┴───────┐
  │                              │ notify_ips   │─────────────────────────┐
  │                              └──────┬───────┘                         │
  │                                     │                                 │
  │                              ┌──────┴───────┐                         │
  │                              │ revoked_ack  │                         │
  │                              └──────┬───────┘                         │
  │                                     │                                 │
  │◄── revoked ─────────────────────────┘                                 │
```

## 5. Cross-Micro-Segment Access

```
Source Segment                  Enforcement Point   Micro-Segmentation   Dest Segment
  │                              (zt_enforcement)     (zt_micro_seg)       
  │                              ┌──────────────┐   ┌──────────────┐   ┌─────────┐
  │──── cross_seg_req ──────────►│              │   │              │   │         │
  src_seg, dst_seg, verb         │ enforce      │   │              │   │         │
  │                              └──────┬───────┘   └──────┬───────┘   └────┬────┘
  │                                     │                  │             │
  │                              ┌──────┴───────┐          │             │
  │                              │ check_policy │          │             │
  │                              └──────┬───────┘          │             │
  │                                     │                  │             │
  │                              ┌──────┴───────┐          │             │
  │                              │ check_segment│─────────►│             │
  │                              └──────┬───────┘          └─────────────┘
  │                                     │
  │                              ┌──────┴───────┐
  │                              │ allow / deny │
  │                              └──────┬───────┘
  │                                     │
  │◄── verdict ─────────────────────────┘
```
