%ifndef GUARD_SECURITY_THREAT_INTEL_THREAT_INTEL_INC
%define GUARD_SECURITY_THREAT_INTEL_THREAT_INTEL_INC

; =============================================================================
; File     : security/threat_intel/include/threat_intel.inc
; Project  : Utkarsha OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Threat Intelligence - master schema header.
;              Constants, structures, macros, and error codes shared by every
;              threat_intel component (core, store, ingestor, exporter,
;              correlator, scoring_engine, enrichment_engine,
;              false_positive_reducer, attribution_engine, playbook_engine,
;              distribution_engine, reputation_engine, geoip_engine,
;              darkweb_engine, c2_engine, malware_attribution,
;              campaign_tracker, lifecycle_manager, feed_aggregator,
;              dedup_engine, stix_engine, taxii_engine,
;              mitre_attack_engine, mitre_d3fend_engine,
;              kill_chain_engine, diamond_model_engine,
;              sigma_engine, yara_engine, threat_hunting_engine).
;
; DESIGN INVARIANT:
;   Threat Intelligence ingests indicators-of-compromise (IOCs) from external
;   feeds (STIX/TAXII, CSV, JSON, proprietary), stores them in a searchable
;   database, correlates observed events against IOCs, and exports matched
;   intel to SIEMs and peers. All lookups are fail-closed: unknown indicators
;   default to TI_VERDICT_UNKNOWN rather than TI_VERDICT_CLEAN.
;
;   Component contract:
;     *_init      - allocate state, load config, register component
;     *_shutdown  - release state, unregister component
;     *_status    - return component health/code
;     *_version   - return NUL-terminated version string
;
; Status: PREMIUM ENTERPRISE SKELETON - full threat intel feature set
;         defined including IOC store, feed ingestion, event correlation,
;         threat scoring, enrichment, false positive reduction, attribution,
;         playbooks, export, reputation, geoip, dark web, C2 detection,
;         malware attribution, campaign tracking, lifecycle management,
;         feed aggregation, deduplication, STIX/TAXII, MITRE ATT&CK,
;         MITRE D3FEND, kill chain, diamond model, Sigma, YARA, threat
;         hunting engines defined.
; =============================================================================

%ifndef THREAT_INTEL_INC
%define THREAT_INTEL_INC

; -----------------------------------------------------------------------------
; Version
; -----------------------------------------------------------------------------
%define THREAT_INTEL_VERSION_MAJOR   1
%define THREAT_INTEL_VERSION_MINOR   0
%define THREAT_INTEL_VERSION_PATCH   0
%define THREAT_INTEL_VERSION_STR     "1.0.0-enterprise"

; -----------------------------------------------------------------------------
; Magic numbers
; -----------------------------------------------------------------------------
%define THREAT_INTEL_STATE_MAGIC             0x5448494E   ; "THIN"
%define THREAT_INTEL_STATE_MAGIC_FREED       0xDEADBEEF

; -----------------------------------------------------------------------------
; Component IDs (bitmask)
; -----------------------------------------------------------------------------
%define THREAT_INTEL_CORE               1
%define THREAT_INTEL_STORE              2
%define THREAT_INTEL_INGESTOR           4
%define THREAT_INTEL_EXPORTER           8
%define THREAT_INTEL_CORRELATOR         32
%define THREAT_INTEL_SCORING_ENGINE     64
%define THREAT_INTEL_ENRICHMENT_ENGINE  128
%define THREAT_INTEL_FP_REDUCER         256
%define THREAT_INTEL_ATTRIBUTION_ENGINE 512
%define THREAT_INTEL_PLAYBOOK_ENGINE    1024
%define THREAT_INTEL_DISTRIBUTION_ENGINE 2048
%define THREAT_INTEL_REPUTATION_ENGINE  4096
%define THREAT_INTEL_GEOIP_ENGINE       8192
%define THREAT_INTEL_DARKWEB_ENGINE     16384
%define THREAT_INTEL_C2_ENGINE          32768
%define THREAT_INTEL_MALWARE_ATTR_ENGINE 65536
%define THREAT_INTEL_CAMPAIGN_TRACKER   131072
%define THREAT_INTEL_LIFECYCLE_MANAGER  262144
%define THREAT_INTEL_FEED_AGGREGATOR    524288
%define THREAT_INTEL_DEDUP_ENGINE       1048576
%define THREAT_INTEL_STIX_ENGINE        2097152
%define THREAT_INTEL_TAXII_ENGINE       4194304
%define THREAT_INTEL_MITRE_ATTACK_ENGINE 8388608
%define THREAT_INTEL_MITRE_D3FEND_ENGINE 16777216
%define THREAT_INTEL_KILL_CHAIN_ENGINE  33554432
%define THREAT_INTEL_DIAMOND_ENGINE     67108864
%define THREAT_INTEL_SIGMA_ENGINE       134217728
%define THREAT_INTEL_YARA_ENGINE        268435456
%define THREAT_INTEL_THREAT_HUNTING_ENGINE 536870912
%define THREAT_INTEL_ALL                0x7FFFFFFF

; -----------------------------------------------------------------------------
; IOC types
; -----------------------------------------------------------------------------
%define TI_IOC_TYPE_IPV4           1
%define TI_IOC_TYPE_IPV6           2
%define TI_IOC_TYPE_DOMAIN         3
%define TI_IOC_TYPE_URL            4
%define TI_IOC_TYPE_HASH_MD5       5
%define TI_IOC_TYPE_HASH_SHA1      6
%define TI_IOC_TYPE_HASH_SHA256    7
%define TI_IOC_TYPE_HASH_SHA512    8
%define TI_IOC_TYPE_EMAIL          9
%define TI_IOC_TYPE_FILEPATH       10
%define TI_IOC_TYPE_REGISTRY       11
%define TI_IOC_TYPE_YARA           12
%define TI_IOC_TYPE_TTP            13
%define TI_IOC_TYPE_MUTEX          14
%define TI_IOC_TYPE_ASN            15
%define TI_IOC_TYPE_CIDR           16
%define TI_IOC_TYPE_EMAIL          17
%define TI_IOC_TYPE_FILE           18
%define TI_IOC_TYPE_REGISTRY_KEY   19
%define TI_IOC_TYPE_SSL_CERT       20
%define TI_IOC_TYPE_SSH_KEY        21
%define TI_IOC_TYPE_PGP_KEY        22
%define TI_IOC_TYPE_BITCOIN_ADDR   23
%define TI_IOC_TYPE_ETH_ADDR       24
%define TI_IOC_TYPE_DOMAIN_URL     25
%define TI_IOC_TYPE_ANY            255

; -----------------------------------------------------------------------------
; Severity levels
; -----------------------------------------------------------------------------
%define TI_SEV_INFO      1
%define TI_SEV_LOW       2
%define TI_SEV_MEDIUM    3
%define TI_SEV_HIGH      4
%define TI_SEV_CRITICAL  5

; -----------------------------------------------------------------------------
; Verdicts
; -----------------------------------------------------------------------------
%define TI_VERDICT_CLEAN       0
%define TI_VERDICT_SUSPICIOUS  1
%define TI_VERDICT_MALICIOUS   2
%define TI_VERDICT_UNKNOWN     3

; -----------------------------------------------------------------------------
; Actions
; -----------------------------------------------------------------------------
%define TI_ACTION_LOG              0
%define TI_ACTION_BLOCK            1
%define TI_ACTION_QUARANTINE       2
%define TI_ACTION_ALERT            3
%define TI_ACTION_IGNORE           4

; -----------------------------------------------------------------------------
; Feed types
; -----------------------------------------------------------------------------
%define TI_FEED_STIX            1
%define TI_FEED_TAXII           2
%define TI_FEED_CSV             3
%define TI_FEED_JSON            4
%define TI_FEED_PROPRIETARY     5
%define TI_FEED_STIX2           6
%define TI_FEED_TAXII2          7
%define TI_FEED_MISP            8
%define TI_FEED_OPENCTI         9
%define TI_FEED_MISP_ATTRIBUTE  10
%define TI_FEED_CUSTOM          11

; -----------------------------------------------------------------------------
; Error codes
; -----------------------------------------------------------------------------
%define TI_ERR_SUCCESS             0
%define TI_ERR_GENERAL             1
%define TI_ERR_NOT_INIT            2
%define TI_ERR_INVALID_ARG         3
%define TI_ERR_RESOURCE            4
%define TI_ERR_ACCESS              5
%define TI_ERR_NOT_FOUND           6
%define TI_ERR_FEED                7
%define TI_ERR_SIGNATURE           8
%define TI_ERR_PARSE               9
%define TI_ERR_ENRICHMENT          10
%define TI_ERR_ATTRIBUTION         11
%define TI_ERR_STIX                12
%define TI_ERR_TAXII               13
%define TI_ERR_MITRE               14
%define TI_ERR_YARA                15
%define TI_ERR_SIGMA               16

%define THREAT_INTEL_ERR_SUCCESS             0
%define THREAT_INTEL_ERR_GENERAL             1
%define THREAT_INTEL_ERR_NOT_INIT            2
%define THREAT_INTEL_ERR_INVALID_ARG         3
%define THREAT_INTEL_ERR_RESOURCE            4
%define THREAT_INTEL_ERR_ACCESS              5
%define THREAT_INTEL_ERR_NOT_FOUND           6
%define THREAT_INTEL_ERR_FEED                7
%define THREAT_INTEL_ERR_SIGNATURE           8
%define THREAT_INTEL_ERR_PARSE               9
%define THREAT_INTEL_ERR_ENRICHMENT          10
%define THREAT_INTEL_ERR_ATTRIBUTION         11
%define THREAT_INTEL_ERR_STIX                12
%define THREAT_INTEL_ERR_TAXII               13
%define THREAT_INTEL_ERR_MITRE               14
%define THREAT_INTEL_ERR_YARA                15
%define THREAT_INTEL_ERR_SIGMA               16

; -----------------------------------------------------------------------------
; Configuration defaults
; -----------------------------------------------------------------------------
%define TI_DEFAULT_MAX_IOCS               1000000
%define TI_DEFAULT_MAX_FEEDS              1000
%define TI_DEFAULT_MAX_FINDINGS           1000000
%define TI_DEFAULT_MAX_CASES              100000
%define TI_DEFAULT_MAX_PLAYBOOKS          1000
%define TI_DEFAULT_MAX_ACTIONS            1000000
%define TI_DEFAULT_MAX_ALERTS             100000
%define TI_DEFAULT_CONFIDENCE_THRESHOLD   70
%define TI_DEFAULT_IOC_TTL_SECONDS        864000   ; 10 days
%define TI_DEFAULT_MAX_RULES              50000
%define TI_DEFAULT_MAX_CASES_PER_DAY              10000
%define TI_DEFAULT_MAX_ALERTS_PER_DAY             100000
%define TI_DEFAULT_MAX_ACTIONS_PER_DAY            1000000
%define TI_DEFAULT_MAX_CASES_PER_HOUR             10000
%define TI_DEFAULT_MAX_ALERTS_PER_HOUR            100000
%define TI_DEFAULT_MAX_ACTIONS_PER_HOUR           1000000
%define TI_DEFAULT_MAX_CASES_PER_WEEK             70000
%define TI_DEFAULT_MAX_ALERTS_PER_WEEK            700000
%define TI_DEFAULT_MAX_ACTIONS_PER_WEEK           7000000
%define TI_DEFAULT_MAX_CASES_PER_MONTH            300000
%define TI_DEFAULT_MAX_ALERTS_PER_MONTH           3000000
%define TI_DEFAULT_MAX_ACTIONS_PER_MONTH            30000000
%define THREAT_INTEL_DEFAULT_MAX_IOCS               1000000
%define THREAT_INTEL_DEFAULT_MAX_FEEDS              1000
%define THREAT_INTEL_DEFAULT_MAX_FINDINGS           1000000
%define THREAT_INTEL_DEFAULT_MAX_CASES              100000
%define THREAT_INTEL_DEFAULT_MAX_PLAYBOOKS          1000
%define THREAT_INTEL_DEFAULT_MAX_ACTIONS            1000000
%define THREAT_INTEL_DEFAULT_MAX_ALERTS             100000
%define THREAT_INTEL_DEFAULT_CONFIDENCE_THRESHOLD   70
%define THREAT_INTEL_DEFAULT_IOC_TTL_SECONDS        864000
%define THREAT_INTEL_DEFAULT_MAX_RULES              50000

; -----------------------------------------------------------------------------
; Scan types
; -----------------------------------------------------------------------------
%define TI_SCAN_TYPE_NETWORK     1
%define TI_SCAN_TYPE_HOST        2
%define TI_SCAN_TYPE_APPLICATION 3
%define TI_SCAN_TYPE_CONTAINER   4
%define TI_SCAN_TYPE_CLOUD       5

; -----------------------------------------------------------------------------
; Spinlock macros
; -----------------------------------------------------------------------------
%macro TI_SPIN_LOCK 1
    ; STUB: acquire spinlock on %1
%endmacro

%macro TI_SPIN_UNLOCK 1
    ; STUB: release spinlock on %1
%endmacro

; -----------------------------------------------------------------------------
; Linked list macros
; -----------------------------------------------------------------------------
%define TI_LIST_INIT(head)  head

%macro TI_LIST_ADD 2
    ; STUB: insert node %1 at head of list %2
%endmacro

%macro TI_LIST_REMOVE 2
    ; STUB: remove node %1 from list %2
%endmacro

; -----------------------------------------------------------------------------
; Return value helper
; -----------------------------------------------------------------------------
%macro TI_RET 1
    mov     eax, %1
    ret
%endmacro

; -----------------------------------------------------------------------------
; State structure base (embedded at start of every component state)
; -----------------------------------------------------------------------------
struc threat_intel_state_base_t
    .magic:         resd 1      ; THREAT_INTEL_STATE_MAGIC for validation
    .version:       resd 1      ; component version
    .refcount:      resd 1      ; reference count
    .spinlock:      resq 1      ; SMP spinlock
    .enabled:       resb 1      ; component enabled flag
    .pad:           resb 7      ; alignment
    .init_ns:       resq 1      ; initialization timestamp
    .stats_events:  resq 1      ; total events processed
    .stats_actions: resq 1      ; total actions executed
    .stats_errors:  resq 1      ; total errors logged
endstruc

; -----------------------------------------------------------------------------
; IOC record
; -----------------------------------------------------------------------------
struc ti_ioc_t
    .ioc_id:        resq 1      ; unique IOC identifier
    .ioc_type:      resd 1      ; TI_IOC_TYPE_*
    .severity:      resd 1      ; TI_SEV_*
    .confidence:    resd 1      ; 0-100 confidence score
    .indicator:     resb 256    ; NUL-terminated indicator value
    .indicator_len: resd 1      ; length of indicator
    .feed_source:   resb 128    ; NUL-terminated feed source name
    .first_seen:    resq 1      ; first observed timestamp
    .last_seen:     resq 1      ; last observed timestamp
    .expires_ns:    resq 1      ; expiration timestamp (0 = never)
    .hit_count:     resq 1      ; number of times matched
    .tags:          resb 128    ; comma-separated tags
    .next:          resq 1      ; linked list
endstruc

; -----------------------------------------------------------------------------
; Threat feed record
; -----------------------------------------------------------------------------
struc ti_feed_t
    .feed_id:       resq 1      ; unique feed identifier
    .feed_type:     resd 1      ; TI_FEED_*
    .feed_url:      resb 256    ; NUL-terminated feed URL
    .feed_url_len:  resd 1
    .api_key:       resb 128    ; NUL-terminated API key
    .api_key_len:   resd 1
    .last_pull:     resq 1      ; timestamp of last successful pull
    .pull_interval: resq 1      ; pull interval in seconds
    .ioc_count:     resq 1      ; number of IOCs from this feed
    .error_count:   resq 1      ; number of feed errors
    .next:          resq 1      ; linked list
endstruc

; -----------------------------------------------------------------------------
; Correlation match result
; -----------------------------------------------------------------------------
struc ti_match_result_t
    .match_id:      resq 1      ; unique match identifier
    .ioc_id:        resq 1      ; matched IOC identifier
    .event_id:      resq 1      ; originating event identifier
    .verdict:       resd 1      ; TI_VERDICT_*
    .severity:      resd 1      ; TI_SEV_*
    .confidence:    resd 1      ; 0-100 confidence score
    .matched_ns:    resq 1      ; timestamp of match
    .action:        resd 1      ; TI_ACTION_*
    .next:          resq 1      ; linked list
endstruc

; -----------------------------------------------------------------------------
; Threat attribution record
; -----------------------------------------------------------------------------
struc ti_attribution_t
    .attribution_id:  resq 1      ; unique attribution identifier
    .actor_name:      resb 128    ; NUL-terminated threat actor name
    .actor_type:      resd 1      ; 1=APT, 2=criminal, 3=hacktivist, 4=insider
    .country_code:    resb 3      ; ISO country code
    .confidence:      resd 1      ; 0-100 confidence score
    .first_seen:      resq 1      ; first seen timestamp
    .last_seen:       resq 1      ; last seen timestamp
    .next:            resq 1      ; linked list
endstruc

; -----------------------------------------------------------------------------
; Campaign record
; -----------------------------------------------------------------------------
struc ti_campaign_t
    .campaign_id:   resq 1      ; unique campaign identifier
    .campaign_name: resb 128    ; NUL-terminated campaign name
    .actor_id:      resq 1      ; associated threat actor ID
    .start_date:    resq 1      ; campaign start timestamp
    .end_date:      resq 1      ; campaign end timestamp
    .severity:      resd 1      ; TI_SEV_*
    .confidence:    resd 1      ; 0-100 confidence score
    .next:          resq 1      ; linked list
endstruc

; -----------------------------------------------------------------------------
; Playbook record
; -----------------------------------------------------------------------------
struc ti_playbook_t
    .playbook_id:   resq 1      ; unique playbook identifier
    .playbook_name: resb 128    ; NUL-terminated playbook name
    .playbook_type: resd 1      ; playbook type
    .version:       resd 1      ; playbook version
    .enabled:       resb 1      ; playbook is enabled
    .pad:           resb 3      ; alignment
    .step_count:    resd 1      ; number of steps in playbook
    .steps:         resq 1      ; pointer to steps array
    .created_ns:    resq 1      ; creation timestamp
    .updated_ns:    resq 1      ; last update timestamp
    .next:          resq 1      ; linked list
endstruc

; -----------------------------------------------------------------------------
; Distribution record
; -----------------------------------------------------------------------------
struc ti_distribution_t
    .distribution_id: resq 1      ; unique distribution identifier
    .target_module:   resd 1      ; target module ID
    .data_type:       resd 1      ; data type being distributed
    .record_count:    resq 1      ; number of records distributed
    .distributed_ns:  resq 1      ; distribution timestamp
    .next:            resq 1      ; linked list
endstruc

; -----------------------------------------------------------------------------
; Reputation record
; -----------------------------------------------------------------------------
struc ti_reputation_t
    .target_id:     resq 1      ; unique target identifier
    .target_type:   resd 1      ; target type (1=IP, 2=domain, 3=URL, etc.)
    .score:         resd 1      ; reputation score (-100 to +100)
    .confidence:    resd 1      ; 0-100 confidence score
    .last_updated:  resq 1      ; last update timestamp
    .next:          resq 1      ; linked list
endstruc

; -----------------------------------------------------------------------------
; GeoIP record
; -----------------------------------------------------------------------------
struc ti_geoip_t
    .ip_address:   resb 64     ; NUL-terminated IP address
    .country_code: resb 3      ; ISO country code
    .country_name: resb 64     ; NUL-terminated country name
    .region:       resb 64     ; NUL-terminated region name
    .city:         resb 64     ; NUL-terminated city name
    .latitude:     resd 1      ; latitude
    .longitude:    resd 1      ; longitude
    .isp:          resb 128    ; NUL-terminated ISP name
    .organization: resb 128    ; NUL-terminated organization name
    .next:         resq 1      ; linked list
endstruc

; -----------------------------------------------------------------------------
; C2 detection record
; -----------------------------------------------------------------------------
struc ti_c2_t
    .c2_id:        resq 1      ; unique C2 identifier
    .c2_type:      resd 1      ; C2 type
    .c2_address:   resb 256    ; NUL-terminated C2 address
    .c2_port:      resd 1      ; C2 port
    .c2_protocol:  resd 1      ; C2 protocol
    .c2_first_seen:   resq 1   ; first seen timestamp
    .c2_last_seen:   resq 1   ; last seen timestamp
    .next:         resq 1      ; linked list
endstruc

; -----------------------------------------------------------------------------
; Malware family attribution record
; -----------------------------------------------------------------------------
struc ti_malware_attribution_t
    .malware_id:   resq 1      ; unique malware identifier
    .malware_name: resb 128    ; NUL-terminated malware name
    .malware_type: resd 1      ; malware type
    .malware_family: resb 128   ; NUL-terminated malware family
    .malware_version: resb 64   ; NUL-terminated malware version
    .malware_first_seen:   resq 1      ; first seen timestamp
    .malware_last_seen:    resq 1      ; last seen timestamp
    .next:          resq 1      ; linked list
endstruc

; -----------------------------------------------------------------------------
; Campaign record
; -----------------------------------------------------------------------------
struc ti_campaign_t
    .campaign_id:   resq 1      ; unique campaign identifier
    .campaign_name: resb 128    ; NUL-terminated campaign name
    .actor_id:      resq 1      ; associated threat actor ID
    .start_date:    resq 1      ; campaign start timestamp
    .end_date:      resq 1      ; campaign end timestamp
    .severity:      resd 1      ; TI_SEV_*
    .confidence:    resd 1      ; 0-100 confidence score
    .next:          resq 1      ; linked list
endstruc

; -----------------------------------------------------------------------------
; Lifecycle management record
; -----------------------------------------------------------------------------
struc ti_lifecycle_t
    .lifecycle_id:   resq 1      ; unique lifecycle identifier
    .ioc_id:         resq 1      ; associated IOC identifier
    .lifecycle_state:   resd 1     ; lifecycle state
    .transitioned_ns:   resq 1     ; transition timestamp
    .next:          resq 1      ; linked list
endstruc

; -----------------------------------------------------------------------------
; Feed aggregation record
; -----------------------------------------------------------------------------
struc ti_feed_agg_t
    .feed_id:       resq 1      ; unique feed identifier
    .feed_type:     resd 1      ; TI_FEED_*
    .feed_url:      resb 256    ; NUL-terminated feed URL
    .last_pull:     resq 1      ; last pull timestamp
    .ioc_count:     resq 1      ; number of IOCs from this feed
    .error_count:   resq 1      ; number of feed errors
    .next:          resq 1      ; linked list
endstruc

; -----------------------------------------------------------------------------
; Deduplication engine record
; -----------------------------------------------------------------------------
struc ti_dedup_t
    .dedup_id:    resq 1      ; unique dedup identifier
    .ioc_id:      resq 1      ; associated IOC identifier
    .dup_ioc_id:  resq 1      ; duplicate IOC identifier
    .deduped_ns:  resq 1      ; deduplication timestamp
    .next:        resq 1      ; linked list
endstruc

; -----------------------------------------------------------------------------
; STIX/TAXII record
; -----------------------------------------------------------------------------
struc ti_stix_t
    .stix_id:       resq 1      ; unique STIX identifier
    .stix_type:     resd 1      ; STIX type
    .stix_version:  resb 16     ; NUL-terminated STIX version string
    .stix_taxii_server:  resb 256     ; NUL-terminated TAXII server URL
    .stix_last_sync:   resq 1      ; last sync timestamp
    .next:            resq 1      ; linked list
endstruc

; -----------------------------------------------------------------------------
; MITRE ATT&CK record
; -----------------------------------------------------------------------------
struc ti_mitre_attack_t
    .attack_id:       resq 1      ; unique ATT&CK identifier
    .attack_technique:   resb 128   ; NUL-terminated ATT&CK technique name
    .attack_subtechnique: resb 128   ; NUL-terminated ATT&CK subtechnique name
    .attack_tactic:   resb 128    ; NUL-terminated ATT&CK tactic name
    .next:            resq 1      ; linked list
endstruc

; -----------------------------------------------------------------------------
; MITRE D3FEND record
; -----------------------------------------------------------------------------
struc ti_mitre_d3fend_t
    .d3fend_id:       resq 1      ; unique D3FEND identifier
    .d3fend_technique:   resb 128   ; NUL-terminated D3FEND technique name
    .d3fend_tactic:   resb 128    ; NUL-terminated D3FEND tactic name
    .next:            resq 1      ; linked list
endstruc

; -----------------------------------------------------------------------------
; Kill chain record
; -----------------------------------------------------------------------------
struc ti_kill_chain_t
    .kill_chain_id:   resq 1      ; unique kill chain identifier
    .kill_chain_stage:   resd 1      ; kill chain stage
    .kill_chain_name:   resb 128    ; NUL-terminated kill chain stage name
    .next:            resq 1      ; linked list
endstruc

; -----------------------------------------------------------------------------
; Diamond model record
; -----------------------------------------------------------------------------
struc ti_diamond_t
    .diamond_id:      resq 1      ; unique diamond identifier
    .diamond_type:    resd 1      ; diamond type
    .diamond_name:    resb 128    ; NUL-terminated diamond name
    .next:            resq 1      ; linked list
endstruc

; -----------------------------------------------------------------------------
; Sigma rule record
; -----------------------------------------------------------------------------
struc ti_sigma_t
    .sigma_id:        resq 1      ; unique sigma identifier
    .sigma_name:      resb 128    ; NUL-terminated sigma rule name
    .sigma_rule:      resb 4096   ; NUL-terminated sigma rule
    .next:            resq 1      ; linked list
endstruc

; -----------------------------------------------------------------------------
; YARA rule record
; -----------------------------------------------------------------------------
struc ti_yara_t
    .yara_id:         resq 1      ; unique YARA identifier
    .yara_name:       resb 128    ; NUL-terminated YARA rule name
    .yara_rule:       resb 4096   ; NUL-terminated YARA rule
    .next:            resq 1      ; linked list
endstruc

; -----------------------------------------------------------------------------
; Threat hunting record
; -----------------------------------------------------------------------------
struc ti_hunting_t
    .hunt_id:       resq 1      ; unique hunt identifier
    .hunt_name:     resb 128    ; NUL-terminated hunt name
    .hunt_type:     resd 1      ; hunt type
    .hunt_status:   resd 1      ; hunt status
    .next:          resq 1      ; linked list
endstruc

; -----------------------------------------------------------------------------
; Global Threat Intel state
; -----------------------------------------------------------------------------
struc threat_intel_global_state_t
    .magic:                 resd 1
    .version:               resd 1
    .enabled:               resb 1
    .fail_mode:             resb 1      ; fail-closed or fail-open
    .pad:                   resb 2
    .components:            resd 1      ; bitmask of initialized components
    .spinlock:              resq 1
    .max_iocs:              resq 1
    .max_feeds:             resq 1
    .max_findings:          resq 1
    .max_cases:             resq 1
    .max_playbooks:         resq 1
    .max_actions:           resq 1
    .max_alerts:            resq 1
    .confidence_threshold:  resd 1      ; minimum confidence for matches
    .ioc_ttl:               resq 1      ; IOC TTL in seconds
    .pad2:                  resd 2
    .total_iocs:            resq 1      ; total IOCs
    .total_feeds:           resq 1      ; total feeds
    .total_findings:        resq 1      ; total findings
    .total_cases:           resq 1      ; total cases
    .total_playbooks:       resq 1      ; total playbooks
    .total_actions:         resq 1      ; total actions
    .total_alerts:          resq 1      ; total alerts
    .total_reports:         resq 1      ; total reports generated
    .core_state:            resq 1
    .store_state:           resq 1
    .ingestor_state:        resq 1
    .exporter_state:        resq 1
    .correlator_state:      resq 1
    .scoring_state:         resq 1
    .enrichment_state:      resq 1
    .false_positive_state:  resq 1
    .attribution_state:     resq 1
    .playbook_state:        resq 1
    .distribution_state:    resq 1
    .reputation_state:      resq 1
    .geoip_state:           resq 1
    .darkweb_state:         resq 1
    .c2_state:              resq 1
    .malware_state:         resq 1
    .campaign_state:        resq 1
    .lifecycle_state:       resq 1
    .feed_agg_state:        resq 1
    .dedup_state:           resq 1
    .stix_state:            resq 1
    .taxii_state:           resq 1
    .mitre_attack_state:    resq 1
    .mitre_d3fend_state:    resq 1
    .kill_chain_state:      resq 1
    .diamond_state:         resq 1
    .sigma_state:           resq 1
    .yara_state:            resq 1
    .hunting_state:         resq 1
endstruc

%endif ; THREAT_INTEL_INC
%endif ; GUARD_SECURITY_THREAT_INTEL_THREAT_INTEL_INC