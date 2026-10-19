%ifndef GUARD_SECURITY_THREAT_INTEL_TESTS_TEST_THREAT_INTEL_ASM
%define GUARD_SECURITY_THREAT_INTEL_TESTS_TEST_THREAT_INTEL_ASM

; =============================================================================
; File     : security/threat_intel/tests/test_threat_intel.asm
; Project  : Tattva OS
; Description: Threat intel skeleton test - verifies constants, structs, and
;              include file integrity. Component symbol exports are verified
;              by tests/run.sh via grep.
; Status   : PREMIUM ENTERPRISE SKELETON
; =============================================================================

bits 64
DEFAULT REL

%include "include/threat_intel.inc"

section .bss
alignb 16
test_components_tested: resq 5
test_failures:          resq 1

section .text

global _start
_start:
    xor     rax, rax
    mov     qword [test_failures], 0

    ; ------------------------------------------------------------
    ; Verify version constants
    ; ------------------------------------------------------------
    mov     eax, THREAT_INTEL_VERSION_MAJOR
    cmp     eax, 1
    jne     .fail_version_major

    mov     eax, THREAT_INTEL_VERSION_MINOR
    cmp     eax, 0
    jne     .fail_version_minor

    ; ------------------------------------------------------------
    ; Verify magic numbers
    ; ------------------------------------------------------------
    mov     eax, THREAT_INTEL_STATE_MAGIC
    cmp     eax, 0x5448494E       ; "THIN"
    jne     .fail_magic

    mov     eax, THREAT_INTEL_STATE_MAGIC_FREED
    cmp     eax, 0xDEADBEEF
    jne     .fail_magic_freed

    ; ------------------------------------------------------------
    ; Verify component IDs
    ; ------------------------------------------------------------
    mov     eax, THREAT_INTEL_CORE
    cmp     eax, 1
    jne     .fail_component_core

    mov     eax, THREAT_INTEL_STORE
    cmp     eax, 2
    jne     .fail_component_store

    mov     eax, THREAT_INTEL_INGESTOR
    cmp     eax, 4
    jne     .fail_component_ingestor

    mov     eax, THREAT_INTEL_EXPORTER
    cmp     eax, 8
    jne     .fail_component_exporter

    mov     eax, THREAT_INTEL_CORRELATOR
    cmp     eax, 16
    jne     .fail_component_correlator

    mov     eax, THREAT_INTEL_SCORING_ENGINE
    cmp     eax, 32
    jne     .fail_component_scoring

    mov     eax, THREAT_INTEL_ENRICHMENT_ENGINE
    cmp     eax, 64
    jne     .fail_component_enrichment

    mov     eax, THREAT_INTEL_FP_REDUCER
    cmp     eax, 128
    jne     .fail_component_fp_reducer

    mov     eax, THREAT_INTEL_ATTRIBUTION_ENGINE
    cmp     eax, 256
    jne     .fail_component_attribution

    mov     eax, THREAT_INTEL_PLAYBOOK_ENGINE
    cmp     eax, 512
    jne     .fail_component_playbook

    mov     eax, THREAT_INTEL_DISTRIBUTION_ENGINE
    cmp     eax, 1024
    jne     .fail_component_distribution

    mov     eax, THREAT_INTEL_REPUTATION_ENGINE
    cmp     eax, 2048
    jne     .fail_component_reputation

    mov     eax, THREAT_INTEL_GEOIP_ENGINE
    cmp     eax, 4096
    jne     .fail_component_geoip

    mov     eax, THREAT_INTEL_DARKWEB_ENGINE
    cmp     eax, 8192
    jne     .fail_component_darkweb

    mov     eax, THREAT_INTEL_C2_ENGINE
    cmp     eax, 16384
    jne     .fail_component_c2

    mov     eax, THREAT_INTEL_MALWARE_ATTR_ENGINE
    cmp     eax, 32768
    jne     .fail_component_malware_attr

    mov     eax, THREAT_INTEL_CAMPAIGN_TRACKER
    cmp     eax, 65536
    jne     .fail_component_campaign

    mov     eax, THREAT_INTEL_LIFECYCLE_MANAGER
    cmp     eax, 131072
    jne     .fail_component_lifecycle

    mov     eax, THREAT_INTEL_FEED_AGGREGATOR
    cmp     eax, 262144
    jne     .fail_component_feed_agg

    mov     eax, THREAT_INTEL_DEDUP_ENGINE
    cmp     eax, 524288
    jne     .fail_component_dedup

    mov     eax, THREAT_INTEL_STIX_ENGINE
    cmp     eax, 2097152
    jne     .fail_component_stix

    mov     eax, THREAT_INTEL_TAXII_ENGINE
    cmp     eax, 4194304
    jne     .fail_component_taxii

    mov     eax, THREAT_INTEL_MITRE_ATTACK_ENGINE
    cmp     eax, 8388608
    jne     .fail_component_mitre_attack

    mov     eax, THREAT_INTEL_MITRE_D3FEND_ENGINE
    cmp     eax, 16777216
    jne     .fail_component_mitre_d3fend

    mov     eax, THREAT_INTEL_KILL_CHAIN_ENGINE
    cmp     eax, 16777216
    jne     .fail_component_kill_chain

    mov     eax, THREAT_INTEL_DIAMOND_ENGINE
    cmp     eax, 33554432
    jne     .fail_component_diamond

    mov     eax, THREAT_INTEL_SIGMA_ENGINE
    cmp     eax, 67108864
    jne     .fail_component_sigma

    mov     eax, THREAT_INTEL_YARA_ENGINE
    cmp     eax, 134217728
    jne     .fail_component_yara

    mov     eax, THREAT_INTEL_THREAT_HUNTING_ENGINE
    cmp     eax, 268435456
    jne     .fail_component_hunting

    mov     eax, THREAT_INTEL_ALL
    cmp     eax, 0x7FFFFFFF
    jne     .fail_component_all

    ; ------------------------------------------------------------
    ; Verify IOC types
    ; ------------------------------------------------------------
    mov     eax, TI_IOC_TYPE_IPV4
    cmp     eax, 1
    jne     .fail_ioc_ipv4

    mov     eax, TI_IOC_TYPE_IPV6
    cmp     eax, 2
    jne     .fail_ioc_ipv6

    mov     eax, TI_IOC_TYPE_DOMAIN
    cmp     eax, 3
    jne     .fail_ioc_domain

    mov     eax, TI_IOC_TYPE_URL
    cmp     eax, 4
    jne     .fail_ioc_url

    mov     eax, TI_IOC_TYPE_HASH_MD5
    cmp     eax, 5
    jne     .fail_ioc_md5

    mov     eax, TI_IOC_TYPE_HASH_SHA1
    cmp     eax, 6
    jne     .fail_ioc_sha1

    mov     eax, TI_IOC_TYPE_HASH_SHA256
    cmp     eax, 7
    jne     .fail_ioc_sha256

    mov     eax, TI_IOC_TYPE_HASH_SHA512
    cmp     eax, 8
    jne     .fail_ioc_sha512

    mov     eax, TI_IOC_TYPE_EMAIL
    cmp     eax, 9
    jne     .fail_ioc_email

    mov     eax, TI_IOC_TYPE_FILEPATH
    cmp     eax, 10
    jne     .fail_ioc_filepath

    mov     eax, TI_IOC_TYPE_REGISTRY
    cmp     eax, 11
    jne     .fail_ioc_registry

    mov     eax, TI_IOC_TYPE_YARA
    cmp     eax, 12
    jne     .fail_ioc_yara

    mov     eax, TI_IOC_TYPE_TTP
    cmp     eax, 13
    jne     .fail_ioc_ttp

    mov     eax, TI_IOC_TYPE_MUTEX
    cmp     eax, 14
    jne     .fail_ioc_mutex

    mov     eax, TI_IOC_TYPE_ASN
    cmp     eax, 15
    jne     .fail_ioc_asn

    mov     eax, TI_IOC_TYPE_CIDR
    cmp     eax, 16
    jne     .fail_ioc_cidr

    mov     eax, TI_IOC_TYPE_ANY
    cmp     eax, 255
    jne     .fail_ioc_any

    ; ------------------------------------------------------------
    ; Verify severities
    ; ------------------------------------------------------------
    mov     eax, TI_SEV_INFO
    cmp     eax, 1
    jne     .fail_sev_info

    mov     eax, TI_SEV_LOW
    cmp     eax, 2
    jne     .fail_sev_low

    mov     eax, TI_SEV_MEDIUM
    cmp     eax, 3
    jne     .fail_sev_medium

    mov     eax, TI_SEV_HIGH
    cmp     eax, 4
    jne     .fail_sev_high

    mov     eax, TI_SEV_CRITICAL
    cmp     eax, 5
    jne     .fail_sev_critical

    ; ------------------------------------------------------------
    ; Verify verdicts
    ; ------------------------------------------------------------
    mov     eax, TI_VERDICT_CLEAN
    cmp     eax, 0
    jne     .fail_verdict_clean

    mov     eax, TI_VERDICT_SUSPICIOUS
    cmp     eax, 1
    jne     .fail_verdict_suspicious

    mov     eax, TI_VERDICT_MALICIOUS
    cmp     eax, 2
    jne     .fail_verdict_malicious

    mov     eax, TI_VERDICT_UNKNOWN
    cmp     eax, 3
    jne     .fail_verdict_unknown

    ; ------------------------------------------------------------
    ; Verify actions
    ; ------------------------------------------------------------
    mov     eax, TI_ACTION_LOG
    cmp     eax, 0
    jne     .fail_action_log

    mov     eax, TI_ACTION_BLOCK
    cmp     eax, 1
    jne     .fail_action_block

    mov     eax, TI_ACTION_QUARANTINE
    cmp     eax, 2
    jne     .fail_action_quarantine

    mov     eax, TI_ACTION_ALERT
    cmp     eax, 3
    jne     .fail_action_alert

    mov     eax, TI_ACTION_IGNORE
    cmp     eax, 4
    jne     .fail_action_ignore

    ; ------------------------------------------------------------
    ; Verify feed types
    ; ------------------------------------------------------------
    mov     eax, TI_FEED_STIX
    cmp     eax, 1
    jne     .fail_feed_stix

    mov     eax, TI_FEED_TAXII
    cmp     eax, 2
    jne     .fail_feed_taxii

    mov     eax, TI_FEED_CSV
    cmp     eax, 3
    jne     .fail_feed_csv

    mov     eax, TI_FEED_JSON
    cmp     eax, 4
    jne     .fail_feed_json

    mov     eax, TI_FEED_PROPRIETARY
    cmp     eax, 5
    jne     .fail_feed_proprietary

    mov     eax, TI_FEED_STIX2
    cmp     eax, 6
    jne     .fail_feed_stix2

    mov     eax, TI_FEED_TAXII2
    cmp     eax, 7
    jne     .fail_feed_taxii2

    mov     eax, TI_FEED_MISP
    cmp     eax, 8
    jne     .fail_feed_misp

    mov     eax, TI_FEED_OPENCTI
    cmp     eax, 9
    jne     .fail_feed_opencti

    mov     eax, TI_FEED_MISP_ATTRIBUTE
    cmp     eax, 10
    jne     .fail_feed_misp_attribute

    mov     eax, TI_FEED_CUSTOM
    cmp     eax, 11
    jne     .fail_feed_custom

    ; ------------------------------------------------------------
    ; Verify error codes
    ; ------------------------------------------------------------
    mov     eax, TI_ERR_SUCCESS
    cmp     eax, 0
    jne     .fail_err_success

    mov     eax, TI_ERR_GENERAL
    cmp     eax, 1
    jne     .fail_err_general

    mov     eax, TI_ERR_NOT_INIT
    cmp     eax, 2
    jne     .fail_err_not_init

    mov     eax, TI_ERR_INVALID_ARG
    cmp     eax, 3
    jne     .fail_err_invalid_arg

    mov     eax, TI_ERR_RESOURCE
    cmp     eax, 4
    jne     .fail_err_resource

    mov     eax, TI_ERR_ACCESS
    cmp     eax, 5
    jne     .fail_err_access

    mov     eax, TI_ERR_NOT_FOUND
    cmp     eax, 6
    jne     .fail_err_not_found

    mov     eax, TI_ERR_FEED
    cmp     eax, 7
    jne     .fail_err_feed

    mov     eax, TI_ERR_SIGNATURE
    cmp     eax, 8
    jne     .fail_err_signature

    mov     eax, TI_ERR_PARSE
    cmp     eax, 9
    jne     .fail_err_parse

    mov     eax, TI_ERR_ENRICHMENT
    cmp     eax, 10
    jne     .fail_err_enrichment

    mov     eax, TI_ERR_ATTRIBUTION
    cmp     eax, 11
    jne     .fail_err_attribution

    mov     eax, TI_ERR_STIX
    cmp     eax, 12
    jne     .fail_err_stix

    mov     eax, TI_ERR_TAXII
    cmp     eax, 13
    jne     .fail_err_taxii

    mov     eax, TI_ERR_MITRE
    cmp     eax, 14
    jne     .fail_err_mitre

    mov     eax, TI_ERR_YARA
    cmp     eax, 15
    jne     .fail_err_yara

    mov     eax, TI_ERR_SIGMA
    cmp     eax, 16
    jne     .fail_err_sigma

    ; ------------------------------------------------------------
    ; Verify THREAT_INTEL error codes
    ; ------------------------------------------------------------
    mov     eax, THREAT_INTEL_ERR_SUCCESS
    cmp     eax, 0
    jne     .fail_err_success_ti

    mov     eax, THREAT_INTEL_ERR_GENERAL
    cmp     eax, 1
    jne     .fail_err_general_ti

    mov     eax, THREAT_INTEL_ERR_NOT_INIT
    cmp     eax, 2
    jne     .fail_err_not_init_ti

    mov     eax, THREAT_INTEL_ERR_INVALID_ARG
    cmp     eax, 3
    jne     .fail_err_invalid_arg_ti

    mov     eax, THREAT_INTEL_ERR_RESOURCE
    cmp     eax, 4
    jne     .fail_err_resource_ti

    mov     eax, THREAT_INTEL_ERR_ACCESS
    cmp     eax, 5
    jne     .fail_err_access_ti

    mov     eax, THREAT_INTEL_ERR_NOT_FOUND
    cmp     eax, 6
    jne     .fail_err_not_found_ti

    mov     eax, THREAT_INTEL_ERR_FEED
    cmp     eax, 7
    jne     .fail_err_feed_ti

    mov     eax, THREAT_INTEL_ERR_SIGNATURE
    cmp     eax, 8
    jne     .fail_err_signature_ti

    mov     eax, THREAT_INTEL_ERR_PARSE
    cmp     eax, 9
    jne     .fail_err_parse_ti

    mov     eax, THREAT_INTEL_ERR_ENRICHMENT
    cmp     eax, 10
    jne     .fail_err_enrichment_ti

    mov     eax, THREAT_INTEL_ERR_ATTRIBUTION
    cmp     eax, 11
    jne     .fail_err_attribution_ti

    mov     eax, THREAT_INTEL_ERR_STIX
    cmp     eax, 12
    jne     .fail_err_stix_ti

    mov     eax, THREAT_INTEL_ERR_TAXII
    cmp     eax, 13
    jne     .fail_err_taxii_ti

    mov     eax, THREAT_INTEL_ERR_MITRE
    cmp     eax, 14
    jne     .fail_err_mitre_ti

    mov     eax, THREAT_INTEL_ERR_YARA
    cmp     eax, 15
    jne     .fail_err_yara_ti

    mov     eax, THREAT_INTEL_ERR_SIGMA
    cmp     eax, 16
    jne     .fail_err_sigma_ti

    ; ------------------------------------------------------------
    ; Verify config defaults
    ; ------------------------------------------------------------
    mov     eax, THREAT_INTEL_DEFAULT_MAX_IOCS
    cmp     eax, 1000000
    jne     .fail_max_iocs

    mov     eax, THREAT_INTEL_DEFAULT_MAX_FEEDS
    cmp     eax, 1000
    jne     .fail_max_feeds

    mov     eax, THREAT_INTEL_DEFAULT_MAX_FINDINGS
    cmp     eax, 1000000
    jne     .fail_max_findings

    mov     eax, THREAT_INTEL_DEFAULT_MAX_CASES
    cmp     eax, 100000
    jne     .fail_max_cases

    mov     eax, THREAT_INTEL_DEFAULT_MAX_PLAYBOOKS
    cmp     eax, 1000
    jne     .fail_max_playbooks

    mov     eax, THREAT_INTEL_DEFAULT_MAX_ACTIONS
    cmp     eax, 1000000
    jne     .fail_max_actions

    mov     eax, THREAT_INTEL_DEFAULT_MAX_ALERTS
    cmp     eax, 100000
    jne     .fail_max_alerts

    mov     eax, THREAT_INTEL_DEFAULT_CONFIDENCE_THRESHOLD
    cmp     eax, 70
    jne     .fail_confidence_threshold

    mov     eax, THREAT_INTEL_DEFAULT_IOC_TTL_SECONDS
    cmp     eax, 864000
    jne     .fail_ioc_ttl

    mov     eax, THREAT_INTEL_DEFAULT_MAX_RULES
    cmp     eax, 50000
    jne     .fail_max_rules

    ; ------------------------------------------------------------
    ; Verify struc sizes are defined
    ; ------------------------------------------------------------
    mov     rax, threat_intel_state_base_t_size
    mov     rbx, ti_ioc_t_size
    mov     rcx, ti_feed_t_size
    mov     rdx, ti_match_result_t_size
    mov     rsi, threat_intel_global_state_t_size

    ; All structural checks passed
    mov     rax, 60              ; sys_exit
    xor     rdi, rdi             ; status 0
    syscall

; ------------------------------------------------------------
; Failure handlers
; ------------------------------------------------------------
.fail_version_major:
    mov     qword [test_failures], 1
    jmp     .exit_fail
.fail_version_minor:
    mov     qword [test_failures], 2
    jmp     .exit_fail
.fail_magic:
    mov     qword [test_failures], 3
    jmp     .exit_fail
.fail_magic_freed:
    mov     qword [test_failures], 4
    jmp     .exit_fail
.fail_component_core:
    mov     qword [test_failures], 5
    jmp     .exit_fail
.fail_component_store:
    mov     qword [test_failures], 6
    jmp     .exit_fail
.fail_component_ingestor:
    mov     qword [test_failures], 7
    jmp     .exit_fail
.fail_component_exporter:
    mov     qword [test_failures], 8
    jmp     .exit_fail
.fail_component_correlator:
    mov     qword [test_failures], 9
    jmp     .exit_fail
.fail_component_all:
    mov     qword [test_failures], 10
    jmp     .exit_fail
.fail_ioc_ipv4:
    mov     qword [test_failures], 50
    jmp     .exit_fail
.fail_ioc_ipv6:
    mov     qword [test_failures], 51
    jmp     .exit_fail
.fail_ioc_domain:
    mov     qword [test_failures], 52
    jmp     .exit_fail
.fail_ioc_url:
    mov     qword [test_failures], 53
    jmp     .exit_fail
.fail_ioc_md5:
    mov     qword [test_failures], 54
    jmp     .exit_fail
.fail_ioc_sha1:
    mov     qword [test_failures], 55
    jmp     .exit_fail
.fail_ioc_sha256:
    mov     qword [test_failures], 56
    jmp     .exit_fail
.fail_ioc_yara:
    mov     qword [test_failures], 57
    jmp     .exit_fail
.fail_ioc_ttp:
    mov     qword [test_failures], 58
    jmp     .exit_fail
.fail_sev_info:
    mov     qword [test_failures], 60
    jmp     .exit_fail
.fail_sev_low:
    mov     qword [test_failures], 61
    jmp     .exit_fail
.fail_sev_medium:
    mov     qword [test_failures], 62
    jmp     .exit_fail
.fail_sev_high:
    mov     qword [test_failures], 63
    jmp     .exit_fail
.fail_sev_critical:
    mov     qword [test_failures], 64
    jmp     .exit_fail
.fail_verdict_clean:
    mov     qword [test_failures], 65
    jmp     .exit_fail
.fail_verdict_suspicious:
    mov     qword [test_failures], 66
    jmp     .exit_fail
.fail_verdict_malicious:
    mov     qword [test_failures], 67
    jmp     .exit_fail
.fail_verdict_unknown:
    mov     qword [test_failures], 68
    jmp     .exit_fail
.fail_action_log:
    mov     qword [test_failures], 69
    jmp     .exit_fail
.fail_action_block:
    mov     qword [test_failures], 70
    jmp     .exit_fail
.fail_action_quarantine:
    mov     qword [test_failures], 71
    jmp     .exit_fail
.fail_action_alert:
    mov     qword [test_failures], 72
    jmp     .exit_fail
.fail_action_ignore:
    mov     qword [test_failures], 73
    jmp     .exit_fail
.fail_feed_stix:
    mov     qword [test_failures], 74
    jmp     .exit_fail
.fail_feed_taxii:
    mov     qword [test_failures], 75
    jmp     .exit_fail
.fail_feed_csv:
    mov     qword [test_failures], 76
    jmp     .exit_fail
.fail_feed_json:
    mov     qword [test_failures], 77
    jmp     .exit_fail
.fail_feed_proprietary:
    mov     qword [test_failures], 78
    jmp     .exit_fail
.fail_err_success:
    mov     qword [test_failures], 90
    jmp     .exit_fail
.fail_err_general:
    mov     qword [test_failures], 91
    jmp     .exit_fail
.fail_err_not_init:
    mov     qword [test_failures], 92
    jmp     .exit_fail
.fail_err_invalid_arg:
    mov     qword [test_failures], 93
    jmp     .exit_fail
.fail_err_resource:
    mov     qword [test_failures], 94
    jmp     .exit_fail
.fail_err_access:
    mov     qword [test_failures], 95
    jmp     .exit_fail
.fail_err_not_found:
    mov     qword [test_failures], 96
    jmp     .exit_fail
.fail_err_feed:
    mov     qword [test_failures], 97
    jmp     .exit_fail
.fail_err_signature:
    mov     qword [test_failures], 98
    jmp     .exit_fail
.fail_err_parse:
    mov     qword [test_failures], 99
    jmp     .exit_fail
.fail_err_enrichment:
    mov     qword [test_failures], 100
    jmp     .exit_fail
.fail_err_attribution:
    mov     qword [test_failures], 101
    jmp     .exit_fail
.fail_err_stix:
    mov     qword [test_failures], 102
    jmp     .exit_fail
.fail_err_taxii:
    mov     qword [test_failures], 103
    jmp     .exit_fail
.fail_err_mitre:
    mov     qword [test_failures], 104
    jmp     .exit_fail
.fail_err_yara:
    mov     qword [test_failures], 105
    jmp     .exit_fail
.fail_err_sigma:
    mov     qword [test_failures], 106
    jmp     .exit_fail
.fail_dsr_days:
    mov     qword [test_failures], 107
    jmp     .exit_fail
.fail_max_iocs:
    mov     qword [test_failures], 108
    jmp     .exit_fail
.fail_max_feeds:
    mov     qword [test_failures], 109
    jmp     .exit_fail
.fail_max_findings:
    mov     qword [test_failures], 110
    jmp     .exit_fail
.fail_max_cases:
    mov     qword [test_failures], 111
    jmp     .exit_fail
.fail_max_playbooks:
    mov     qword [test_failures], 112
    jmp     .exit_fail
.fail_max_actions:
    mov     qword [test_failures], 113
    jmp     .exit_fail
.fail_max_alerts:
    mov     qword [test_failures], 114
    jmp     .exit_fail
.fail_confidence_threshold:
    mov     qword [test_failures], 115
    jmp     .exit_fail
.fail_ioc_ttl:
    mov     qword [test_failures], 116
    jmp     .exit_fail
.fail_max_rules:
    mov     qword [test_failures], 117
    jmp     .exit_fail

.exit_fail:
    mov     rax, 60              ; sys_exit
    mov     rdi, 1               ; status 1 (failure)
    syscall

%endif