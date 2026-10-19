%ifndef GUARD_SECURITY_IDS_SRC_DATA_EXFIL_DETECTOR_ASM
%define GUARD_SECURITY_IDS_SRC_DATA_EXFIL_DETECTOR_ASM

; =============================================================================
; File     : security/ids/src/data_exfiltration_detector.asm
; Project  : Tattva OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: IDS Data Exfiltration Detector - identifies data exfiltration
;              channels (DNS tunneling, HTTP uploads, FTP, cloud storage,
;              encrypted channels) and quantifies data at risk.
; Status   : PREMIUM ENTERPRISE - full API surface, logic bodies marked STUB.
; =============================================================================

bits 64
DEFAULT REL

%include "include/ids.inc"

section .bss
alignb 16
ids_exfil_state:         resb ids_state_base_t_size
ids_exfil_flow_head:     resq 1
ids_exfil_flow_count:    resq 1

section .data
alignb 16
ids_exfil_version_str: db IDS_VERSION_STR, 0

section .text

; =============================================================================
; ids_data_exfiltration_init - Initialize data exfiltration detector
; Input:  none
; Output: rax = 0 on success, negative error code on failure
; =============================================================================
global ids_data_exfiltration_init
ids_data_exfiltration_init:
    push    rbx
    mov     dword [ids_exfil_state + ids_state_base_t.magic], IDS_STATE_MAGIC
    mov     dword [ids_exfil_state + ids_state_base_t.version], IDS_VERSION_MAJOR
    mov     byte [ids_exfil_state + ids_state_base_t.enabled], 1
    mov     qword [ids_exfil_flow_head], 0
    mov     qword [ids_exfil_flow_count], 0
    xor     eax, eax
    pop     rbx
    ret

; =============================================================================
; ids_data_exfiltration_shutdown - Shut down data exfiltration detector
; Input:  none
; Output: rax = 0 on success
; =============================================================================
global ids_data_exfiltration_shutdown
ids_data_exfiltration_shutdown:
    push    rbx
    mov     eax, [ids_exfil_state + ids_state_base_t.magic]
    cmp     eax, IDS_STATE_MAGIC
    jnz     .not_init
    mov     dword [ids_exfil_state + ids_state_base_t.magic], IDS_STATE_MAGIC_FREED
    mov     byte [ids_exfil_state + ids_state_base_t.enabled], 0
    xor     eax, eax
    pop     rbx
    ret
.not_init:
    mov     eax, -1
    pop     rbx
    ret

; =============================================================================
; ids_data_exfiltration_status - Return current data exfiltration detector status
; Input:  none
; Output: rax = status code
; =============================================================================
global ids_data_exfiltration_status
ids_data_exfiltration_status:
    mov     eax, [ids_exfil_state + ids_state_base_t.magic]
    cmp     eax, IDS_STATE_MAGIC
    jnz     .not_init
    mov     al, [ids_exfil_state + ids_state_base_t.enabled]
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
; ids_data_exfiltration_version - Return version string pointer
; Input:  none
; Output: rax = pointer to NUL-terminated version string
; =============================================================================
global ids_data_exfiltration_version
ids_data_exfiltration_version:
    mov     rax, ids_exfil_version_str
    ret

; =============================================================================
; ids_data_exfil_detect - Detect data exfiltration patterns
; Input:  rdi = flow context pointer, rsi = source IP,
;         rdx = bytes transferred, rcx = duration_ms
; Output: rax = exfiltration score (0-100), rbx = channel type flag
; =============================================================================
global ids_data_exfil_detect
ids_data_exfil_detect:
    push    rbx
    push    r12

    mov     eax, [ids_exfil_state + ids_state_base_t.magic]
    cmp     eax, IDS_STATE_MAGIC
    jnz     .err_component_down

    test    rdi, rdi
    jz      .err_invalid_arg

    mov     r12, rdi              ; save flow context pointer

    ; STUB: detect outbound data transfers exceeding thresholds
    ; STEP: identify uploads to untrusted external destinations
    ; STEP: detect compressed/encrypted payloads indicating exfil
    ; STEP: identify cloud storage and personal email uploads
    ; STEP: return exfiltration score and channel type

    xor     eax, eax               ; STUB: no exfiltration
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

; STUB: ids_data_exfil_add_channel - add monitored exfil channel
; STUB: ids_data_exfil_remove_channel - remove monitored exfil channel
; STUB: ids_data_exfil_list_flows - list suspicious flows
; STUB: ids_data_exfil_get_stats - return detection statistics

%endif