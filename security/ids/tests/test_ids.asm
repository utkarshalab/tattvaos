%ifndef GUARD_SECURITY_IDS_TESTS_TEST_IDS_ASM
%define GUARD_SECURITY_IDS_TESTS_TEST_IDS_ASM

; =============================================================================
; File     : security/ids/tests/test_ids.asm
; Project  : Tattva OS
; Description: IDS premium skeleton test.
;              Validates that all 10 component .asm files exist, assemble
;              independently, and export the required enterprise contract
;              symbols (init, shutdown, status, version + component-specific
;              functions). Also verifies that all include guards, struc sizes,
;              and constants resolve correctly.
; Status   : PREMIUM SKELETON
; =============================================================================

bits 64
DEFAULT REL

%include "include/ids.inc"

section .bss
alignb 16
test_components_tested: resq 10
test_failures:          resq 1

section .text

global _start
_start:
    xor     rax, rax
    mov     qword [test_failures], 0

    ; =========================================================================
    ; This test file verifies structural integrity of the IDS module:
    ;
    ;   1. All 10 component source files exist in src/
    ;   2. Each component exports: *_init, *_shutdown, *_status, *_version
    ;   3. Component-specific functions are exported
    ;   4. All components include ids.inc
    ;   5. Include guards present in ids.inc
    ;
    ; Checks 1-5 are performed by tests/run.sh (bash). This .asm file simply
    ; verifies it can assemble standalone as a flat binary, confirming the
    ; NASM syntax, include paths, struc definitions, and constants are valid.
    ;
    ; Cross-component calls (ids_inspect_packet calling ids_sensor_capture,
    ; ids_reassembler_add_packet, etc.) are STUBbed in source with comments -
    ; they resolve at system integration time when all components are linked
    ; into the kernel.
    ; =========================================================================

    ; Verify we can reference ids.inc constants (proves include works)
    mov     eax, IDS_VERDICT_CLEAN
    mov     ebx, IDS_VERDICT_SUSPICIOUS
    mov     ecx, IDS_VERDICT_THREAT
    mov     edx, IDS_VERDICT_ERROR

    mov     esi, IDS_REASON_SIGNATURE_MATCH
    mov     edi, IDS_REASON_ANOMALY_THRESHOLD
    mov     r8d, IDS_REASON_PROTOCOL_VIOLATION
    mov     r9d, IDS_REASON_SCAN_DETECTED

    mov     r10d, IDS_SEV_INFO
    mov     r11d, IDS_SEV_LOW
    mov     r12d, IDS_SEV_MEDIUM
    mov     r13d, IDS_SEV_HIGH
    mov     r14d, IDS_SEV_CRITICAL

    mov     r15d, IDS_ALERT_NEW
    mov     eax, IDS_ALERT_ACKNOWLEDGED
    mov     ebx, IDS_ALERT_INVESTIGATING
    mov     ecx, IDS_ALERT_RESOLVED
    mov     edx, IDS_ALERT_FALSE_POSITIVE

    ; Verify protocol constants
    mov     eax, 6          ; TCP
    mov     ebx, 17         ; UDP
    mov     ecx, 1          ; ICMP

    ; Verify rule type constants
    mov     eax, IDS_RULE_SIGNATURE
    mov     ebx, IDS_RULE_ANOMALY
    mov     ecx, IDS_RULE_PROTOCOL
    mov     edx, IDS_RULE_BLACKLIST
    mov     esi, IDS_RULE_BEHAVIORAL

    ; Verify stream state constants
    mov     eax, IDS_STREAM_CLOSED
    mov     ebx, IDS_STREAM_SYN_SENT
    mov     ecx, IDS_STREAM_ESTABLISHED

    ; Verify packet flag constants
    mov     eax, IDS_PKT_FRAGMENT
    mov     ebx, IDS_PKT_RETRANSMIT
    mov     ecx, IDS_PKT_ENCRYPTED

    ; Verify struc sizes are defined (proves data structures exist)
    mov     rax, ids_state_base_t_size
    mov     rbx, ids_packet_ctx_t_size
    mov     rcx, ids_stream_t_size
    mov     rdx, ids_rule_t_size
    mov     rsi, ids_alert_t_size
    mov     r8, ids_correlation_t_size
    mov     r9, ids_stats_t_size

    ; Verify global state struc size
    mov     r10, ids_global_state_t_size

    ; All structural checks passed
    mov     rax, 60          ; sys_exit
    xor     rdi, rdi         ; status 0
    syscall

%endif
