%ifndef GUARD_SECURITY_IPS_INC_IPS_INC
%define GUARD_SECURITY_IPS_INC_IPS_INC

; =============================================================================
; File     : security/ips/include/ips.inc
; Project  : Tattva OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Intrusion Prevention System - master schema header (Enterprise).
;              Constants, structures, macros, and error codes shared by every
;              IPS component including advanced premium features.
;
; DESIGN INVARIANT:
;   IPS is INLINE ENFORCEMENT. It sits in the traffic path and can DROP,
;   RESET, THROTTLE, or QUARANTINE traffic. It FAILS CLOSED — if enforcement
;   cannot be verified, traffic is blocked.
;
;   IPS works WITH IDS: IDS detects, IPS prevents. IDS alerts feed IPS policy.
;
;   Component contract:
;     *_init      - allocate state, load config, register component
;     *_shutdown  - release state, unregister component
;     *_status    - return component health/code
;     *_version   - return NUL-terminated version string
;
; Status: PREMIUM ENTERPRISE - full feature set including GeoIP, TLS inspection,
;         DNS filtering, file reputation, URL filtering, bot detection, DDoS
;         protection, threat feeds, WAF engine, sandbox integration.
; =============================================================================

%ifndef IPS_INC
%define IPS_INC

; -----------------------------------------------------------------------------
; Version
; -----------------------------------------------------------------------------
%define IPS_VERSION_MAJOR   2
%define IPS_VERSION_MINOR   0
%define IPS_VERSION_PATCH   0
%define IPS_VERSION_STR     "2.0.0-enterprise"

; -----------------------------------------------------------------------------
; Magic numbers for state structure validation
; -----------------------------------------------------------------------------
%define IPS_STATE_MAGIC             0x49505344   ; "IPSD"
%define IPS_STATE_MAGIC_FREED       0xDEADBEEF

; -----------------------------------------------------------------------------
; Component IDs (bitmask for enabled/disabled components)
; -----------------------------------------------------------------------------
%define IPS_COMP_INSPECTOR          (1 << 0)
%define IPS_COMP_ENFORCER           (1 << 1)
%define IPS_COMP_POLICY             (1 << 2)
%define IPS_COMP_BYPASS             (1 << 3)
%define IPS_COMP_RATE_LIMITER       (1 << 4)
%define IPS_COMP_CONNECTION_TRACKER (1 << 5)
%define IPS_COMP_QUARANTINE         (1 << 6)
%define IPS_COMP_BLOCKLIST          (1 << 7)
%define IPS_COMP_SIEM               (1 << 8)
%define IPS_COMP_STATS              (1 << 9)
%define IPS_COMP_GEOIP              (1 << 10)
%define IPS_COMP_APP_CONTROL        (1 << 11)
%define IPS_COMP_TLS_INSPECTOR      (1 << 12)
%define IPS_COMP_DNS_FILTER         (1 << 13)
%define IPS_COMP_FILE_ANALYSIS      (1 << 14)
%define IPS_COMP_URL_FILTER         (1 << 15)
%define IPS_COMP_BOT_DETECTOR       (1 << 16)
%define IPS_COMP_DDOS_PROTECTOR     (1 << 17)
%define IPS_COMP_THREAT_FEED        (1 << 18)
%define IPS_COMP_WAF_ENGINE         (1 << 19)
%define IPS_COMP_PACKET_CAPTURE     (1 << 20)
%define IPS_COMP_HA_CLUSTER         (1 << 21)
%define IPS_COMP_API_PROTECTION     (1 << 22)
%define IPS_COMP_ML_ANOMALY         (1 << 23)
%define IPS_COMP_DEEP_PACKET_INSPECTOR   (1 << 24)
%define IPS_COMP_PROTOCOL_NORMALIZER     (1 << 25)
%define IPS_COMP_STREAM_REASSEMBLER      (1 << 26)
%define IPS_COMP_PAYLOAD_INSPECTOR       (1 << 27)
%define IPS_COMP_CONNECTION_TERMINATOR   (1 << 28)
%define IPS_COMP_PACKET_INJECTOR         (1 << 29)
%define IPS_COMP_TRAFFIC_SHAPER          (1 << 30)
%define IPS_COMP_LOAD_BALANCER_INTEGRATION 0x40000000
%define IPS_COMP_ALL                     0x7FFFFFFF

; -----------------------------------------------------------------------------
; Enforcement actions
; -----------------------------------------------------------------------------
%define IPS_ACTION_ALLOW            0      ; permit traffic
%define IPS_ACTION_DROP             1      ; silently drop packet
%define IPS_ACTION_RESET            2      ; send TCP RST to both sides
%define IPS_ACTION_THROTTLE         3      ; rate-limit, allow reduced bandwidth
%define IPS_ACTION_QUARANTINE       4      ; isolate endpoint, redirect to quarantine
%define IPS_ACTION_BLOCK            5      ; block endpoint for duration
%define IPS_ACTION_REDIRECT         6      ; redirect to different destination
%define IPS_ACTION_INSPECT_DEEP     7      ; send to deep packet inspection
%define IPS_ACTION_SANDBOX          8      ; send file to sandbox for analysis
%define IPS_ACTION_CHALLENGE        9      ; CAPTCHA / challenge-response

; -----------------------------------------------------------------------------
; Enforcement verdicts
; -----------------------------------------------------------------------------
%define IPS_VERDICT_ALLOW           0
%define IPS_VERDICT_DROP            -1
%define IPS_VERDICT_RESET           -2
%define IPS_VERDICT_THROTTLE        -3
%define IPS_VERDICT_QUARANTINE      -4
%define IPS_VERDICT_BLOCK           -5
%define IPS_VERDICT_ERROR           -100

; -----------------------------------------------------------------------------
; Denial/Enforcement reason codes
; -----------------------------------------------------------------------------
%define IPS_REASON_NONE             0
%define IPS_REASON_BLACKLISTED_IP   -1   ; source/dest in blocklist
%define IPS_REASON_POLICY_VIOLATION -2   ; explicit policy deny
%define IPS_REASON_RATE_LIMIT       -3   ; rate limit exceeded
%define IPS_REASON_IDS_ALERT        -4   ; triggered by IDS detection
%define IPS_REASON_PROTOCOL_VIOLATION -5 ; malformed protocol traffic
%define IPS_REASON_QUARANTINED_HOST -6   ; endpoint is quarantined
%define IPS_REASON_CONNECTION_LIMIT -7   ; connection count limit exceeded
%define IPS_REASON_COMPONENT_DOWN   -8   ; enforcement component unavailable
%define IPS_REASON_INVALID_REQUEST  -9   ; malformed enforcement request
%define IPS_REASON_GEOIP_BLOCKED    -10  ; country/region blocked
%define IPS_REASON_APP_BLOCKED      -11  ; application not allowed
%define IPS_REASON_TLS_VIOLATION    -12  ; TLS certificate/fingerprint violation
%define IPS_REASON_DNS_BLOCKED      -13  ; domain blocked by DNS filter
%define IPS_REASON_FILE_MALICIOUS   -14  ; file hash matches known malware
%define IPS_REASON_URL_BLOCKED      -15  ; URL blocked by category filter
%define IPS_REASON_BOT_DETECTED     -16  ; automated bot behavior detected
%define IPS_REASON_DDoS_ATTACK      -17  ; DDoS attack pattern detected
%define IPS_REASON_THREAT_FEED      -18  ; IOC matched threat intelligence feed
%define IPS_REASON_WAF_VIOLATION    -19  ; web application firewall rule violated
%define IPS_REASON_SANDBOX_MALICIOUS -20 ; sandbox analysis found malware
%define IPS_REASON_API_VIOLATION    -21  ; API protection rule violated

; -----------------------------------------------------------------------------
; Fail modes
; -----------------------------------------------------------------------------
%define IPS_FAIL_CLOSED             0   ; block on error (default, secure)
%define IPS_FAIL_OPEN               1   ; allow on error (HA paths only)

; -----------------------------------------------------------------------------
; Connection states
; -----------------------------------------------------------------------------
%define IPS_CONN_NEW                0
%define IPS_CONN_ESTABLISHED        1
%define IPS_CONN_RELATED            2
%define IPS_CONN_INVALID            3

; -----------------------------------------------------------------------------
; Configuration defaults
; -----------------------------------------------------------------------------
%define IPS_DEFAULT_MAX_CONNECTIONS  100000
%define IPS_DEFAULT_MAX_BLOCKLIST    50000
%define IPS_DEFAULT_MAX_QUARANTINE   10000
%define IPS_DEFAULT_BLOCK_DURATION_MS 3600000   ; 1 hour
%define IPS_DEFAULT_QUARANTINE_DURATION_MS 86400000  ; 24 hours
%define IPS_DEFAULT_RATE_LIMIT_RPS   1000       ; requests per second
%define IPS_DEFAULT_GEOIP_BLOCKED_COUNTRIES 0   ; none blocked by default
%define IPS_DEFAULT_MAX_URL_CATEGORIES 50
%define IPS_DEFAULT_MAX_FILE_HASHES 100000
%define IPS_DEFAULT_MAX_BOT_SIGNATURES 50000
%define IPS_DEFAULT_MAX_DDoS_THRESHOLDS 100

; -----------------------------------------------------------------------------
; Spinlock macros (architecture placeholder)
; -----------------------------------------------------------------------------
%macro IPS_SPIN_LOCK 1
    ; STUB: acquire spinlock on %1
%endmacro

%macro IPS_SPIN_UNLOCK 1
    ; STUB: release spinlock on %1
%endmacro

; -----------------------------------------------------------------------------
; Linked list macros (intrusive)
; -----------------------------------------------------------------------------
%define IPS_LIST_INIT(head)  head

%macro IPS_LIST_ADD 2
    ; STUB: insert node %1 at head of list %2
%endmacro

%macro IPS_LIST_REMOVE 2
    ; STUB: remove node %1 from list %2
%endmacro

; -----------------------------------------------------------------------------
; Enforcement emission macro - call enforcer to apply action
; -----------------------------------------------------------------------------
%macro IPS_ENFORCE 6
    ; %1=action, %2=reason, %3=src_ip, %4=dst_ip, %5=duration_ms, %6=message_ptr
    ; STUB: apply enforcement action through enforcer component
%endmacro

; -----------------------------------------------------------------------------
; Return value helper
; -----------------------------------------------------------------------------
%macro IPS_RET 1
    mov     eax, %1
    ret
%endmacro

; -----------------------------------------------------------------------------
; State structure base (embedded at start of every component state)
; -----------------------------------------------------------------------------
struc ips_state_base_t
    .magic:         resd 1      ; IPS_STATE_MAGIC for validation
    .version:       resd 1      ; component version
    .refcount:      resd 1      ; reference count
    .spinlock:      resq 1      ; SMP spinlock (STUB)
    .enabled:       resb 1      ; component enabled flag
    .pad:           resb 7      ; alignment
    .init_ns:       resq 1      ; initialization timestamp
    .stats_packets: resq 1      ; total packets inspected
    .stats_dropped: resq 1      ; total packets dropped
    .stats_blocked: resq 1      ; total endpoints blocked
    .stats_quarantined: resq 1  ; total endpoints quarantined
endstruc

; -----------------------------------------------------------------------------
; Enforcement request context (input to ips_enforce)
; -----------------------------------------------------------------------------
struc ips_enforce_ctx_t
    .timestamp_ns:  resq 1      ; enforcement timestamp
    .src_ip:        resd 1      ; IPv4 source address
    .dst_ip:        resd 1      ; IPv4 destination address
    .src_port:      resd 1
    .dst_port:      resd 1
    .protocol:      resd 1      ; 6=TCP, 17=UDP, 1=ICMP
    .packet_len:    resd 1
    .action_hint:   resd 1      ; suggested action (IPS_ACTION_*)
    .reason_hint:   resd 1      ; suggested reason (IPS_REASON_*)
    .session_id:    resq 1      ; associated session (0 = none)
    .context_ptr:   resq 1      ; opaque context blob
    .context_size:  resd 1
    .geoip_country: resd 1      ; resolved country code (set by GeoIP)
    .app_id:        resd 1      ; detected application ID (set by App Control)
    .tls_fingerprint: resq 1    ; JA3/JA3S TLS fingerprint (set by TLS Inspector)
    .domain:        resq 1      ; DNS domain (set by DNS Filter)
    .url_category:  resd 1      ; URL category (set by URL Filter)
    .file_hash:     resq 1      ; file SHA-256 (set by File Analysis)
    .bot_score:     resd 1      ; bot probability 0-100 (set by Bot Detector)
    .threat_score:  resd 1      ; aggregated threat score 0-100
    .reputation_score: resd 1   ; IP/domain reputation -100 to 100
endstruc

; -----------------------------------------------------------------------------
; Enforcement result (output from ips_enforce)
; -----------------------------------------------------------------------------
struc ips_enforce_result_t
    .action:        resd 1      ; IPS_ACTION_*
    .reason_code:   resd 1      ; IPS_REASON_*
    .duration_ms:   resq 1      ; block/quarantine duration (0 = permanent)
    .pad:           resd 4
    .enforced_ns:   resq 1      ; enforcement timestamp
endstruc

; -----------------------------------------------------------------------------
; Blocklist entry
; -----------------------------------------------------------------------------
struc ips_blocklist_entry_t
    .ip:            resd 1
    .reason_code:   resd 1
    .blocked_ns:    resq 1
    .expires_ns:    resq 1      ; 0 = permanent
    .hit_count:     resq 1
    .next:          resq 1      ; linked list / hash chain
endstruc

; -----------------------------------------------------------------------------
; Quarantine entry
; -----------------------------------------------------------------------------
struc ips_quarantine_entry_t
    .ip:            resd 1
    .quarantined_ns: resq 1
    .expires_ns:    resq 1
    .reason_code:   resd 1
    .pad:           resd 3
    .next:          resq 1
endstruc

; -----------------------------------------------------------------------------
; Policy rule (allow/deny)
; -----------------------------------------------------------------------------
struc ips_policy_rule_t
    .rule_id:       resq 1
    .src_ip:        resd 1      ; 0 = any
    .dst_ip:        resd 1      ; 0 = any
    .src_port:      resd 1      ; 0 = any
    .dst_port:      resd 1      ; 0 = any
    .protocol:      resd 1      ; 0 = any
    .action:        resd 1      ; IPS_ACTION_*
    .priority:      resd 1      ; higher wins
    .enabled:       resb 1
    .pad:           resb 3
    .hit_count:     resq 1
    .next:          resq 1      ; linked list
endstruc

; -----------------------------------------------------------------------------
; Rate limiter entry (per IP)
; -----------------------------------------------------------------------------
struc ips_rate_limit_entry_t
    .ip:            resd 1
    .request_count: resq 1
    .window_start_ns: resq 1
    .blocked_until_ns: resq 1
    .next:          resq 1
endstruc

; -----------------------------------------------------------------------------
; Connection tracking entry
; -----------------------------------------------------------------------------
struc ips_connection_t
    .conn_id:       resq 1
    .src_ip:        resd 1
    .dst_ip:        resd 1
    .src_port:      resd 1
    .dst_port:      resd 1
    .protocol:      resd 1
    .state:         resd 1      ; IPS_CONN_*
    .bytes_sent:    resq 1
    .bytes_recv:    resq 1
    .created_ns:    resq 1
    .last_seen_ns:  resq 1
    .next:          resq 1
endstruc

; -----------------------------------------------------------------------------
; Statistics snapshot
; -----------------------------------------------------------------------------
struc ips_stats_t
    .packets_total:     resq 1
    .packets_dropped:   resq 1
    .packets_reset:     resq 1
    .packets_throttled: resq 1
    .packets_quarantined: resq 1
    .endpoints_blocked: resq 1
    .endpoints_quarantined: resq 1
    .connections_total: resq 1
    .connections_active: resq 1
    .top_blocked_ips_ptr: resq 1
    .top_blocked_ips_count: resd 1
    .pad:               resd 3
    .sample_interval_ns: resq 1
    .last_sample_ns:    resq 1
endstruc

; -----------------------------------------------------------------------------
; GeoIP country entry
; -----------------------------------------------------------------------------
struc ips_geoip_entry_t
    .ip_start:      resd 1      ; IP range start
    .ip_end:        resd 1      ; IP range end
    .country_code:  resd 1      ; ISO 3166-1 alpha-2 numeric
    .country_name:  resb 64     ; NUL-terminated country name
    .continent:     resd 1      ; continent code
    .is_blocked:    resb 1      ; country is blocked
    .pad:           resb 3
    .next:          resq 1
endstruc

; -----------------------------------------------------------------------------
; Application control entry
; -----------------------------------------------------------------------------
struc ips_app_entry_t
    .app_id:        resd 1
    .app_name:      resb 64     ; NUL-terminated application name
    .app_category:  resd 1      ; category code (web, mail, p2p, etc.)
    .is_allowed:    resb 1
    .pad:           resb 3
    .signature_ptr: resq 1      ; application signature pattern
    .signature_len: resd 1
    .next:          resq 1
endstruc

; -----------------------------------------------------------------------------
; TLS fingerprint entry (JA3/JA3S)
; -----------------------------------------------------------------------------
struc ips_tls_entry_t
    .fingerprint:   resq 1      ; JA3/JA3S hash
    .fingerprint_len: resd 1
    .is_malicious:  resb 1
    .pad:           resb 3
    .threat_score:  resd 1      ; 0-100
    .next:          resq 1
endstruc

; -----------------------------------------------------------------------------
; DNS filter entry
; -----------------------------------------------------------------------------
struc ips_dns_entry_t
    .domain:        resb 256    ; NUL-terminated domain
    .domain_len:    resd 1
    .is_blocked:    resb 1
    .pad:           resb 3
    .category:      resd 1      ; category code
    .threat_score:  resd 1      ; 0-100
    .next:          resq 1
endstruc

; -----------------------------------------------------------------------------
; File reputation entry
; -----------------------------------------------------------------------------
struc ips_file_entry_t
    .hash_sha256:   resb 32     ; SHA-256 hash
    .is_malicious:  resb 1
    .pad:           resb 7
    .threat_name:   resb 64     ; NUL-terminated threat name
    .threat_score:  resd 1      ; 0-100
    .source:        resd 1      ; threat feed source ID
    .next:          resq 1
endstruc

; -----------------------------------------------------------------------------
; URL filter entry
; -----------------------------------------------------------------------------
struc ips_url_entry_t
    .url_pattern:   resb 256    ; NUL-terminated URL pattern
    .pattern_len:   resd 1
    .category:      resd 1      ; category code
    .is_blocked:    resb 1
    .pad:           resb 3
    .next:          resq 1
endstruc

; -----------------------------------------------------------------------------
; Bot detection signature
; -----------------------------------------------------------------------------
struc ips_bot_sig_t
    .sig_id:        resq 1
    .sig_name:      resb 64     ; NUL-terminated signature name
    .pattern_ptr:   resq 1      ; detection pattern
    .pattern_len:   resd 1
    .threat_score:  resd 1      ; 0-100
    .next:          resq 1
endstruc

; -----------------------------------------------------------------------------
; DDoS threshold entry
; -----------------------------------------------------------------------------
struc ips_ddos_threshold_t
    .threshold_id:  resq 1
    .packet_rate:   resq 1      ; packets per second
    .byte_rate:     resq 1      ; bytes per second
    .connection_rate: resq 1    ; connections per second
    .action:        resd 1      ; IPS_ACTION_* when exceeded
    .is_enabled:    resb 1
    .pad:           resb 3
    .next:          resq 1
endstruc

; -----------------------------------------------------------------------------
; Threat feed entry
; -----------------------------------------------------------------------------
struc ips_threat_feed_t
    .feed_id:       resq 1
    .feed_name:     resb 64     ; NUL-terminated feed name
    .feed_url:      resb 256    ; NUL-terminated feed URL
    .last_update:   resq 1
    .entry_count:   resq 1
    .is_authenticated: resb 1
    .pad:           resb 7
    .next:          resq 1
endstruc

; -----------------------------------------------------------------------------
; WAF rule entry
; -----------------------------------------------------------------------------
struc ips_waf_rule_t
    .rule_id:       resq 1
    .rule_name:     resb 64     ; NUL-terminated rule name
    .pattern_ptr:   resq 1      ; detection pattern
    .pattern_len:   resd 1
    .action:        resd 1      ; IPS_ACTION_*
    .severity:      resd 1      ; 0-4
    .is_enabled:    resb 1
    .pad:           resb 3
    .next:          resq 1
endstruc

; -----------------------------------------------------------------------------
; Packet capture entry
; -----------------------------------------------------------------------------
struc ips_pcap_entry_t
    .capture_id:    resq 1
    .src_ip:        resd 1
    .dst_ip:        resd 1
    .src_port:      resd 1
    .dst_port:      resd 1
    .protocol:      resd 1
    .packet_len:    resd 1
    .capture_ns:    resq 1
    .next:          resq 1
endstruc

; -----------------------------------------------------------------------------
; HA cluster node entry
; -----------------------------------------------------------------------------
struc ips_ha_node_t
    .node_id:       resq 1
    .node_ip:       resd 1
    .is_primary:    resb 1
    .is_healthy:    resb 1
    .pad:           resb 2
    .last_heartbeat: resq 1
    .next:          resq 1
endstruc

; -----------------------------------------------------------------------------
; API protection entry
; -----------------------------------------------------------------------------
struc ips_api_entry_t
    .api_key:       resb 64     ; NUL-terminated API key
    .rate_limit:    resq 1      ; requests per second
    .is_authenticated: resb 1
    .pad:           resb 7
    .next:          resq 1
endstruc

; -----------------------------------------------------------------------------
; ML anomaly detection entry
; -----------------------------------------------------------------------------
struc ips_ml_entry_t
    .model_id:      resq 1
    .model_name:    resb 64     ; NUL-terminated model name
    .anomaly_score: resd 1      ; 0-100
    .confidence:    resd 1      ; 0-100
    .next:          resq 1
endstruc

; -----------------------------------------------------------------------------
; Global IPS state
; -----------------------------------------------------------------------------
struc ips_global_state_t
    .magic:             resd 1
    .version:           resd 1
    .enabled:           resb 1
    .fail_mode:         resb 1      ; IPS_FAIL_CLOSED or IPS_FAIL_OPEN
    .pad:               resb 2
    .components:        resd 1      ; bitmask of initialized components
    .spinlock:          resq 1
    .max_connections:   resq 1
    .max_blocklist:     resq 1
    .max_quarantine:    resq 1
    .block_duration_ms: resq 1
    .quarantine_duration_ms: resq 1
    .rate_limit_rps:    resq 1
    .total_packets:     resq 1
    .total_dropped:     resq 1
    .total_blocked:     resq 1
    .total_quarantined: resq 1
    .inspector_state:   resq 1
    .enforcer_state:    resq 1
    .policy_state:      resq 1
    .bypass_state:      resq 1
    .rate_limiter_state: resq 1
    .conn_tracker_state: resq 1
    .quarantine_state:  resq 1
    .blocklist_state:   resq 1
    .siem_state:        resq 1
    .stats_state:       resq 1
    .geoip_state:       resq 1
    .app_control_state: resq 1
    .tls_inspector_state: resq 1
    .dns_filter_state:  resq 1
    .file_analysis_state: resq 1
    .url_filter_state:  resq 1
    .bot_detector_state: resq 1
    .ddos_protector_state: resq 1
    .threat_feed_state: resq 1
    .waf_engine_state:  resq 1
    .packet_capture_state: resq 1
    .ha_cluster_state:  resq 1
    .api_protection_state: resq 1
    .ml_anomaly_state:  resq 1
    .dpi_state:                 resq 1
    .protocol_norm_state:       resq 1
    .stream_reasm_state:        resq 1
    .payload_inspect_state:     resq 1
    .conn_term_state:           resq 1
    .packet_inject_state:       resq 1
    .traffic_shape_state:       resq 1
    .lb_integration_state:      resq 1
    .ssl_termination_state:     resq 1
    .quarantine_mgr_state:      resq 1
    .honeypot_redirect_state:   resq 1
    .slowloris_mitig_state:     resq 1
    .syn_flood_mitig_state:     resq 1
    .udp_flood_mitig_state:     resq 1
    .http_flood_mitig_state:    resq 1
    .dns_amp_mitig_state:       resq 1
    .ntp_amp_mitig_state:       resq 1
    .memcached_amp_mitig_state: resq 1
endstruc

; -----------------------------------------------------------------------------
; Extern declarations (cross-component references)
; -----------------------------------------------------------------------------

%endif ; IPS_INC
%endif ; GUARD_SECURITY_IPS_INC_IPS_INC
