%ifndef GUARD_SECURITY_IDS_SRC_PORT_SCAN_DETECTOR_ASM
%define GUARD_SECURITY_IDS_SRC_PORT_SCAN_DETECTOR_ASM

; =============================================================================
; File     : security/ids/src/port_scan_detector.asm
; Project  : Tattva OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: IDS Port Scan Detector - identifies port scanning activity
;              (SYN scans, connect scans, UDP scans, fragmented scans)
;              and tracks scanning source behavior.
; Status   : PREMIUM ENTERPRISE - full API surface, logic bodies marked STUB.
; =============================================================================

bits 64
DEFAULT REL

%include "include/ids.inc"

section .bss
alignb 16
ids_port_scan_state:        resb ids_state_base_t_size
ids_port_scan_attempt_head: resq 1
ids_port_scan_attempt_count: resq 1

section .data
alignb 16
ids_port_scan_version_str: db IDS_VERSION_STR, 0

section .text

; =============================================================================
; ids_port_scan_init - Initialize port scan detector
; Input:  none
; Output: rax = 0 on success, negative error code on failure
; =============================================================================
global ids_port_scan_init
ids_port_scan_init:
    push    rbx
    mov     dword [ids_port_scan_state + ids_state_base_t.magic], IDS_STATE_MAGIC
    mov     dword [ids_port_scan_state + ids_state_base_t.version], IDS_VERSION_MAJOR
    mov     byte [ids_port_scan_state + ids_state_base_t.enabled], 1
    mov     qword [ids_port_scan_attempt_head], 0
    mov     qword [ids_port_scan_attempt_count], 0
    xor     eax, eax
    pop     rbx
    ret

; =============================================================================
; ids_port_scan_shutdown - Shut down port scan detector
; Input:  none
; Output: rax = 0 on success
; =============================================================================
global ids_port_scan_shutdown
ids_port_scan_shutdown:
    push    rbx
    mov     eax, [ids_port_scan_state + ids_state_base_t.magic]
    cmp     eax, IDS_STATE_MAGIC
    jnz     .not_init
    mov     dword [ids_port_scan_state + ids_state_base_t.magic], IDS_STATE_MAGIC_FREED
    mov     byte [ids_port_scan_state + ids_state_base_t.enabled], 0
    xor     eax, eax
    pop     rbx
    ret
.not_init:
    mov     eax, -1
    pop     rbx
    ret

; =============================================================================
; ids_port_scan_status - Return current port scan detector status
; Input:  none
; Output: rax = status code
; =============================================================================
global ids_port_scan_status
ids_port_scan_status:
    mov     eax, [ids_port_scan_state + ids_state_base_t.magic]
    cmp     eax, IDS_STATE_MAGIC
    jnz     .not_init
    mov     al, [ids_port_scan_state + ids_state_base_t.enabled]
    test    al, al
    jz      .disabled
    xor     eax, eax
    ret
.disabled:
    mov     eax, -1
    ret
.not_init:
    mov     eax, -2
    ret

; =============================================================================
; ids_port_scan_version - Return version string pointer
; Input:  none
; Output: rax = pointer to NUL-terminated version string
; =============================================================================
global ids_port_scan_version
ids_port_scan_version:
    mov     rax, ids_port_scan_version_str
    ret

; =============================================================================
; ids_port_scan_detect - Detect port scanning activity
; Input:  rdi = connection context pointer, rsi = source IP,
;         rdx = destination port, rcx = scan type flag
; Output: rax = scan score (0-100), rbx = scan technique flag
; =============================================================================
global ids_port_scan_detect
ids_port_scan_detect:
    push    rbx
    push    r12

    mov     eax, [ids_port_scan_state + ids_state_base_t.magic]
    cmp     eax, IDS_STATE_MAGIC
    jnz     .err_component_down

    test    rdi, rdi
    jz      .err_invalid_arg

    mov     r12, rdi              ; save connection context pointer

    ; STUB: track connection attempts per source IP
    ; STEP: identify SYN, connect, UDP, and fragmented scan patterns
    ; STEP: detect slow/low scans to evade threshold detection
    ; STEP: correlate scans across multiple destination hosts
    ; STEP: return scan score and technique flag

    xor     eax, eax               ; STUB: no scan detected
    xor     rbx, rbx
    jmp     .done

.err_component_down:
    mov     rax, -1
    xor     rbx, rbx
    jmp     .done
.err_invalid_arg:
    mov     rax, -2
    xor     rbx, rbx
    jmp     .done

.done:
    pop     r12
    pop     rbx
    ret

; STUB: ids_port_scan_add_threshold - add scan threshold rule
; STUB: ids_port_scan_remove_threshold - remove scan threshold rule
; STUB: ids_port_scan_list_scans - list detected scans
; STUB: ids_port_scan_get_stats - return detection statistics

%endif