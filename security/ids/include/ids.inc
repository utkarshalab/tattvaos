%ifndef GUARD_SECURITY_IDS_INC_IDS_INC
%define GUARD_SECURITY_IDS_INC_IDS_INC

; =============================================================================
; File     : security/ids/include/ids.inc
; Project  : Utkarsha OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Intrusion Detection System - master schema header.
;              Constants, structures, macros, and error codes shared by every
;              IDS component.
;
; DESIGN INVARIANT:
;   IDS is DETECTION-ONLY. It never blocks or drops traffic (that is IPS's job).
;   Every detection emits an alert through the alert engine. All alerts are
;   auditable and exportable to SIEM.
;
;   Component contract:
;     *_init      - allocate state, load config, register component
;     *_shutdown  - release state, unregister component
;     *_status    - return component health/code
;     *_version   - return NUL-terminated version string
;
; Status: PREMIUM SKELETON - data structures, state machines, API contracts,
;         error codes defined. Logic bodies marked STUB with TODO comments.
; =============================================================================

%ifndef IDS_INC
%define IDS_INC

; -----------------------------------------------------------------------------
; Version
; -----------------------------------------------------------------------------
%define IDS_VERSION_MAJOR   1
%define IDS_VERSION_MINOR   0
%define IDS_VERSION_PATCH   0
%define IDS_VERSION_STR     "1.0.0-enterprise-skeleton"

; -----------------------------------------------------------------------------
; Magic numbers for state structure validation
; -----------------------------------------------------------------------------
%define IDS_STATE_MAGIC             0x49445344   ; "IDSD"
%define IDS_STATE_MAGIC_FREED       0xDEADBEEF

; -----------------------------------------------------------------------------
; Component IDs (bitmask for enabled/disabled components)
; -----------------------------------------------------------------------------
%define IDS_COMP_SENSOR             (1 << 0)
%define IDS_COMP_PACKET_REASSEMBLER (1 << 1)
%define IDS_COMP_PROTOCOL_ANALYZER  (1 << 2)
%define IDS_COMP_DETECTOR           (1 << 3)
%define IDS_COMP_RULES              (1 << 4)
%define IDS_COMP_ALERT              (1 << 5)
%define IDS_COMP_THREAT_CORRELATOR  (1 << 6)
%define IDS_COMP_SIEM_EXPORTER      (1 << 7)
%define IDS_COMP_STATS_ENGINE       (1 << 8)
%define IDS_COMP_ANOMALY_DETECTOR   (1 << 9)
%define IDS_COMP_FLOW_ANALYZER      (1 << 10)
%define IDS_COMP_PACKET_INSPECTOR   (1 << 11)
%define IDS_COMP_SIGNATURE_COMPILER (1 << 12)
%define IDS_COMP_ANOMALY_BASELINE   (1 << 13)
%define IDS_COMP_ENCRYPTED_TRAFFIC_ANALYZER (1 << 14)
%define IDS_COMP_SCADA_PROTOCOL_DETECTOR (1 << 15)
%define IDS_COMP_DNS_TUNNEL_DETECTOR   (1 << 16)
%define IDS_COMP_LATERAL_MOVEMENT_DETECTOR (1 << 17)
%define IDS_COMP_DATA_EXFIL_DETECTOR     (1 << 18)
%define IDS_COMP_CREDENTIAL_STUFFING_DETECTOR (1 << 19)
%define IDS_COMP_BRUTE_FORCE_DETECTOR    (1 << 20)
%define IDS_COMP_PORT_SCAN_DETECTOR      (1 << 21)
%define IDS_COMP_OS_FINGERPRINTER        (1 << 22)
%define IDS_COMP_APPLICATION_IDENTIFIER  (1 << 23)
%define IDS_COMP_SSL_TLS_ANALYZER        (1 << 24)
%define IDS_COMP_FILE_CARVER             (1 << 25)
%define IDS_COMP_ALL                     0x3FFFFFF

; -----------------------------------------------------------------------------
; Verdict codes
; -----------------------------------------------------------------------------
%define IDS_VERDICT_CLEAN       0       ; no threat detected
%define IDS_VERDICT_SUSPICIOUS  1       ; suspicious activity, watch
%define IDS_VERDICT_THREAT      2       ; confirmed threat, alert
%define IDS_VERDICT_ERROR      -1       ; inspection error

; -----------------------------------------------------------------------------
; Denial/Alert reason codes (returned in rbx for alert context)
; -----------------------------------------------------------------------------
%define IDS_REASON_NONE                  0
%define IDS_REASON_SIGNATURE_MATCH      -1   ; signature rule matched
%define IDS_REASON_ANOMALY_THRESHOLD    -2   ; statistical anomaly exceeded
%define IDS_REASON_PROTOCOL_VIOLATION   -3   ; malformed protocol traffic
%define IDS_REASON_BLACKLISTED_IP       -4   ; source/dest in blocklist
%define IDS_REASON_SCAN_DETECTED        -5   ; port/network scan pattern
%define IDS_REASON_BRUTE_FORCE          -6   ; authentication brute force
%define IDS_REASON_DATA_EXFILTRATION    -7   ; potential data exfiltration
%define IDS_REASON_MALWARE_C2           -8   ; command & control beacon
%define IDS_REASON_POLICY_VIOLATION     -9   ; organizational policy breach
%define IDS_REASON_INSPECTOR_ERROR     -10   ; inspection subsystem error

; -----------------------------------------------------------------------------
; Severity levels
; -----------------------------------------------------------------------------
%define IDS_SEV_INFO        0
%define IDS_SEV_LOW         1
%define IDS_SEV_MEDIUM      2
%define IDS_SEV_HIGH        3
%define IDS_SEV_CRITICAL    4

; -----------------------------------------------------------------------------
; Alert states
; -----------------------------------------------------------------------------
%define IDS_ALERT_NEW          0
%define IDS_ALERT_ACKNOWLEDGED 1
%define IDS_ALERT_INVESTIGATING 2
%define IDS_ALERT_RESOLVED     3
%define IDS_ALERT_FALSE_POSITIVE 4

; -----------------------------------------------------------------------------
; Configuration defaults
; -----------------------------------------------------------------------------
%define IDS_DEFAULT_MAX_ALERTS        100000
%define IDS_DEFAULT_ALERT_TTL_SECONDS 604800   ; 7 days
%define IDS_DEFAULT_DEDUP_WINDOW_MS   300000   ; 5 minutes
%define IDS_DEFAULT_MAX_RULES         100000
%define IDS_DEFAULT_MAX_STREAMS       10000
%define IDS_DEFAULT_REASSEMBLY_TIMEOUT_MS 30000 ; 30 seconds

; -----------------------------------------------------------------------------
; Spinlock macros (architecture placeholder)
; -----------------------------------------------------------------------------
%macro IDS_SPIN_LOCK 1
    ; STUB: acquire spinlock on %1
%endmacro

%macro IDS_SPIN_UNLOCK 1
    ; STUB: release spinlock on %1
%endmacro

; -----------------------------------------------------------------------------
; Linked list macros (intrusive)
; -----------------------------------------------------------------------------
%define IDS_LIST_INIT(head)  head

%macro IDS_LIST_ADD 2
    ; STUB: insert node %1 at head of list %2
%endmacro

%macro IDS_LIST_REMOVE 2
    ; STUB: remove node %1 from list %2
%endmacro

; -----------------------------------------------------------------------------
; Alert emission macro - call alert engine
; -----------------------------------------------------------------------------
%macro IDS_EMIT_ALERT 8
    ; %1=severity, %2=reason_code, %3=src_ip, %4=dst_ip, %5=src_port,
    ; %6=dst_port, %7=protocol, %8=description_ptr
    ; STUB: emit alert through alert engine
%endmacro

; -----------------------------------------------------------------------------
; Return value helper
; -----------------------------------------------------------------------------
%macro IDS_RET 1
    mov     eax, %1
    ret
%endmacro

; -----------------------------------------------------------------------------
; State structure base (embedded at start of every component state)
; -----------------------------------------------------------------------------
struc ids_state_base_t
    .magic:         resd 1      ; IDS_STATE_MAGIC for validation
    .version:       resd 1      ; component version
    .refcount:      resd 1      ; reference count
    .spinlock:      resq 1      ; SMP spinlock (STUB)
    .enabled:       resb 1      ; component enabled flag
    .pad:           resb 7      ; alignment
    .init_ns:       resq 1      ; initialization timestamp
    .stats_packets: resq 1      ; total packets inspected
    .stats_alerts:  resq 1      ; total alerts generated
    .stats_drops:   resq 1      ; total packets dropped (error)
endstruc

; -----------------------------------------------------------------------------
; Network packet context (input to inspection pipeline)
; -----------------------------------------------------------------------------
struc ids_packet_ctx_t
    .timestamp_ns:  resq 1      ; packet capture timestamp
    .src_ip:        resd 1      ; IPv4 source address (STUB: IPv6 later)
    .dst_ip:        resd 1      ; IPv4 destination address
    .src_port:      resd 1
    .dst_port:      resd 1
    .protocol:      resd 1      ; 6=TCP, 17=UDP, 1=ICMP, etc.
    .packet_len:    resd 1
    .payload_ptr:   resq 1      ; pointer to packet payload
    .payload_len:   resd 1
    .ingress_iface: resd 1      ; interface index
    .flags:         resd 1      ; IDS_PKT_* flags
endstruc

%define IDS_PKT_FRAGMENT    (1 << 0)   ; IP fragment
%define IDS_PKT_RETRANSMIT  (1 << 1)   ; suspected TCP retransmit
%define IDS_PKT_ENCRYPTED   (1 << 2)   ; TLS/encrypted payload
%define IDS_PKT_INTERNAL    (1 << 3)   ; internal network source

; -----------------------------------------------------------------------------
; Stream / connection tracking (TCP reassembly)
; -----------------------------------------------------------------------------
struc ids_stream_t
    .stream_id:       resq 1
    .src_ip:          resd 1
    .dst_ip:          resd 1
    .src_port:        resd 1
    .dst_port:        resd 1
    .state:           resd 1      ; IDS_STREAM_* state
    .seq_offset:      resq 1      ; reassembly sequence offset
    .reasm_buf_ptr:   resq 1      ; reassembly buffer
    .reasm_buf_len:   resd 1
    .reasm_buf_cap:   resd 1
    .last_seen_ns:    resq 1
    .bytes_seen:      resq 1
    .alert_count:     resd 1
    .pad:             resd 1
    .next:            resq 1      ; linked list
endstruc

%define IDS_STREAM_CLOSED     0
%define IDS_STREAM_SYN_SENT   1
%define IDS_STREAM_ESTABLISHED 2
%define IDS_STREAM_FIN_WAIT   3
%define IDS_STREAM_CLOSE_WAIT 4
%define IDS_STREAM_ERROR      5

; -----------------------------------------------------------------------------
; Detection rule (signature)
; -----------------------------------------------------------------------------
struc ids_rule_t
    .rule_id:           resq 1
    .rule_name:         resb 128     ; NUL-terminated rule name
    .rule_type:         resd 1      ; IDS_RULE_* type
    .protocol:          resd 1      ; protocol filter (0 = any)
    .dst_port:          resd 1      ; port filter (0 = any)
    .content_ptr:       resq 1      ; pattern to match (STUB: byte signature)
    .content_len:       resd 1
    .content_offset:    resd 1      ; offset within payload to start match
    .threshold:         resd 1      ; match count threshold
    .severity:          resd 1      ; IDS_SEV_*
    .enabled:           resb 1
    .pad:               resb 3
    .hit_count:         resq 1
    .last_hit_ns:       resq 1
    .next:              resq 1      ; linked list
endstruc

%define IDS_RULE_SIGNATURE   0   ; byte-pattern signature
%define IDS_RULE_ANOMALY     1   ; statistical anomaly
%define IDS_RULE_PROTOCOL    2   ; protocol violation
%define IDS_RULE_BLACKLIST   3   ; IP/domain blacklist
%define IDS_RULE_BEHAVIORAL  4   ; behavioral heuristic

; -----------------------------------------------------------------------------
; Alert record
; -----------------------------------------------------------------------------
struc ids_alert_t
    .alert_id:          resq 1
    .timestamp_ns:      resq 1
    .severity:          resd 1
    .reason_code:       resd 1
    .src_ip:            resd 1
    .dst_ip:            resd 1
    .src_port:          resd 1
    .dst_port:          resd 1
    .protocol:          resd 1
    .rule_id:           resq 1      ; rule that triggered (0 = anomaly)
    .stream_id:         resq 1      ; associated stream (0 = none)
    .state:             resd 1      ; IDS_ALERT_*
    .pad:               resd 1
    .description_ptr:   resq 1      ; NUL-terminated description
    .description_len:   resd 1
    .next:              resq 1      ; linked list
endstruc

; -----------------------------------------------------------------------------
; Threat correlation entry
; -----------------------------------------------------------------------------
struc ids_correlation_t
    .corr_id:           resq 1
    .subject_ip:        resd 1      ; suspected attacker/target
    .threat_score:      resd 1      ; 0-100 aggregated score
    .alert_count:       resd 1
    .first_seen_ns:     resq 1
    .last_seen_ns:      resq 1
    .tags_ptr:          resq 1      ; tag list pointer (STUB)
    .tags_count:        resd 1
    .pad:               resd 1
    .next:              resq 1
endstruc

; -----------------------------------------------------------------------------
; Statistics snapshot
; -----------------------------------------------------------------------------
struc ids_stats_t
    .packets_total:     resq 1
    .packets_by_proto:  resq 16     ; per-protocol counts
    .alerts_total:      resq 1
    .alerts_by_sev:     resq 5      ; per-severity counts
    .alerts_by_reason:  resq 16     ; per-reason counts
    .top_talkers_ptr:   resq 1      ; top N source IPs (STUB)
    .top_talkers_count: resd 1
    .pad:               resd 3
    .sample_interval_ns:resq 1
    .last_sample_ns:    resq 1
endstruc

; -----------------------------------------------------------------------------
; Global IDS state
; -----------------------------------------------------------------------------
struc ids_global_state_t
    .magic:             resd 1
    .version:           resd 1
    .enabled:           resb 1
    .pad:               resb 3
    .components:        resd 1      ; bitmask of initialized components
    .spinlock:          resq 1
    .max_alerts:        resq 1
    .alert_ttl_seconds: resq 1
    .dedup_window_ms:   resq 1
    .max_rules:         resq 1
    .max_streams:       resq 1
    .reassembly_timeout_ms: resq 1
    .total_packets:     resq 1
    .total_alerts:      resq 1
    .active_streams:    resq 1
    .sensor_state:      resq 1
    .reassembler_state: resq 1
    .analyzer_state:    resq 1
    .detector_state:    resq 1
    .rules_state:       resq 1
    .alert_state:       resq 1
    .correlator_state:  resq 1
    .siem_state:        resq 1
    .stats_state:       resq 1
    .anomaly_state:           resq 1
    .flow_state:                resq 1
    .packet_inspector_state:    resq 1
    .signature_compiler_state:  resq 1
    .anomaly_baseline_state:    resq 1
    .encrypted_traffic_state:   resq 1
    .scada_state:               resq 1
    .dns_tunnel_state:          resq 1
    .lateral_movement_state:    resq 1
    .data_exfil_state:          resq 1
    .credential_stuffing_state: resq 1
    .brute_force_state:         resq 1
    .port_scan_state:           resq 1
    .os_fingerprint_state:      resq 1
    .app_identifier_state:      resq 1
    .ssl_tls_state:             resq 1
    .file_carver_state:         resq 1
endstruc

; -----------------------------------------------------------------------------
; Extern declarations (cross-component references)
; -----------------------------------------------------------------------------

%endif ; IDS_INC
%endif ; GUARD_SECURITY_IDS_INC_IDS_INC
