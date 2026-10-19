%ifndef GUARD_SECURITY_IDS_SRC_FLOW_ANALYZER_ASM
%define GUARD_SECURITY_IDS_SRC_FLOW_ANALYZER_ASM

; =============================================================================
; File     : security/ids/src/flow_analyzer.asm
; Project  : Tattva OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: IDS Flow Analyzer - NetFlow/sFlow/IPFIX flow collection,
;              flow record analysis, and traffic pattern detection.
; Status   : PREMIUM ENTERPRISE - full API surface, logic bodies marked STUB.
; =============================================================================

bits 64
DEFAULT REL

%include "include/ids.inc"

section .bss
alignb 16
ids_flow_state:        resb ids_state_base_t_size
ids_flow_record_head:  resq 1
ids_flow_record_count: resq 1

section .data
alignb 16
ids_flow_version_str: db IDS_VERSION_STR, 0

section .text

; =============================================================================
; ids_flow_init - Initialize flow analyzer
; Input:  none
; Output: rax = 0 on success, negative error code on failure
; =============================================================================
global ids_flow_init
ids_flow_init:
    push    rbx
    mov     dword [ids_flow_state + ids_state_base_t.magic], IDS_STATE_MAGIC
    mov     dword [ids_flow_state + ids_state_base_t.version], IDS_VERSION_MAJOR
    mov     byte [ids_flow_state + ids_state_base_t.enabled], 1
    mov     qword [ids_flow_record_head], 0
    mov     qword [ids_flow_record_count], 0
    xor     eax, eax
    pop     rbx
    ret

; =============================================================================
; ids_flow_shutdown - Shut down flow analyzer
; Input:  none
; Output: rax = 0 on success
; =============================================================================
global ids_flow_shutdown
ids_flow_shutdown:
    push    rbx
    mov     eax, [ids_flow_state + ids_state_base_t.magic]
    cmp     eax, IDS_STATE_MAGIC
    jnz     .not_init
    mov     dword [ids_flow_state + ids_state_base_t.magic], IDS_STATE_MAGIC_FREED
    mov     byte [ids_flow_state + ids_state_base_t.enabled], 0
    xor     eax, eax
    pop     rbx
    ret
.not_init:
    mov     eax, -1
    pop     rbx
    ret

; =============================================================================
; ids_flow_status - Return current flow analyzer status
; Input:  none
; Output: rax = status code
; =============================================================================
global ids_flow_status
ids_flow_status:
    mov     eax, [ids_flow_state + ids_state_base_t.magic]
    cmp     eax, IDS_STATE_MAGIC
    jnz     .not_init
    mov     al, [ids_flow_state + ids_state_base_t.enabled]
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
; ids_flow_version - Return version string pointer
; Input:  none
; Output: rax = pointer to NUL-terminated version string
; =============================================================================
global ids_flow_version
ids_flow_version:
    mov     rax, ids_flow_version_str
    ret

; =============================================================================
; ids_flow_process - Process a flow record
; Input:  rdi = flow record pointer, rsi = flow length,
;         rdx = exporter IP, rcx = exporter port
; Output: rax = 0 on success, negative error code on failure
; =============================================================================
global ids_flow_process
ids_flow_process:
    push    rbx
    push    r12

    mov     eax, [ids_flow_state + ids_state_base_t.magic]
    cmp     eax, IDS_STATE_MAGIC
    jnz     .err_component_down

    test    rdi, rdi
    jz      .err_invalid_arg

    mov     r12, rdi              ; save flow record pointer

    ; STUB: parse NetFlow/sFlow/IPFIX record
    ; STEP: extract flow fields (src/dst IP, ports, packets, bytes)
    ; STEP: aggregate flows by conversation
    ; STEP: detect flow anomalies (unusual volume, duration)
    ; STEP: store flow record for analysis
    ; STEP: return success

    xor     eax, eax
    jmp     .done

.err_component_down:
    mov     rax, -1
    jmp     .done
.err_invalid_arg:
    mov     rax, -2
    jmp     .done

.done:
    pop     r12
    pop     rbx
    ret

; STUB: ids_flow_get_top_talkers - get top N source IPs by volume
; STUB: ids_flow_get_conversations - list active conversations
; STUB: ids_flow_export - export flow data to SIEM
; STUB: ids_flow_get_stats - return flow statistics

%endif