%ifndef GUARD_SECURITY_IDS_SRC_LATERAL_MOVEMENT_DETECTOR_ASM
%define GUARD_SECURITY_IDS_SRC_LATERAL_MOVEMENT_DETECTOR_ASM

; =============================================================================
; File     : security/ids/src/lateral_movement_detector.asm
; Project  : Tattva OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: IDS Lateral Movement Detector - detects east-west traffic
;              patterns indicative of attacker lateral movement (Pass-the-Hash,
;              RDP hopping, SMB enumeration, SSH lateral movement).
; Status   : PREMIUM ENTERPRISE - full API surface, logic bodies marked STUB.
; =============================================================================

bits 64
DEFAULT REL

%include "include/ids.inc"

section .bss
alignb 16
ids_lateral_state:         resb ids_state_base_t_size
ids_lateral_session_head:  resq 1
ids_lateral_session_count: resq 1

section .data
alignb 16
ids_lateral_version_str: db IDS_VERSION_STR, 0

section .text

; =============================================================================
; ids_lateral_movement_init - Initialize lateral movement detector
; Input:  none
; Output: rax = 0 on success, negative error code on failure
; =============================================================================
global ids_lateral_movement_init
ids_lateral_movement_init:
    push    rbx
    mov     dword [ids_lateral_state + ids_state_base_t.magic], IDS_STATE_MAGIC
    mov     dword [ids_lateral_state + ids_state_base_t.version], IDS_VERSION_MAJOR
    mov     byte [ids_lateral_state + ids_state_base_t.enabled], 1
    mov     qword [ids_lateral_session_head], 0
    mov     qword [ids_lateral_session_count], 0
    xor     eax, eax
    pop     rbx
    ret

; =============================================================================
; ids_lateral_movement_shutdown - Shut down lateral movement detector
; Input:  none
; Output: rax = 0 on success
; =============================================================================
global ids_lateral_movement_shutdown
ids_lateral_movement_shutdown:
    push    rbx
    mov     eax, [ids_lateral_state + ids_state_base_t.magic]
    cmp     eax, IDS_STATE_MAGIC
    jnz     .not_init
    mov     dword [ids_lateral_state + ids_state_base_t.magic], IDS_STATE_MAGIC_FREED
    mov     byte [ids_lateral_state + ids_state_base_t.enabled], 0
    xor     eax, eax
    pop     rbx
    ret
.not_init:
    mov     eax, -1
    pop     rbx
    ret

; =============================================================================
; ids_lateral_movement_status - Return current lateral movement detector status
; Input:  none
; Output: rax = status code
; =============================================================================
global ids_lateral_movement_status
ids_lateral_movement_status:
    mov     eax, [ids_lateral_state + ids_state_base_t.magic]
    cmp     eax, IDS_STATE_MAGIC
    jnz     .not_init
    mov     al, [ids_lateral_state + ids_state_base_t.enabled]
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
; ids_lateral_movement_version - Return version string pointer
; Input:  none
; Output: rax = pointer to NUL-terminated version string
; =============================================================================
global ids_lateral_movement_version
ids_lateral_movement_version:
    mov     rax, ids_lateral_version_str
    ret

; =============================================================================
; ids_lateral_detect - Detect lateral movement patterns
; Input:  rdi = connection context pointer, rsi = source IP,
;         rdx = destination IP, rcx = protocol/port
; Output: rax = movement score (0-100), rbx = technique flag
; =============================================================================
global ids_lateral_detect
ids_lateral_detect:
    push    rbx
    push    r12

    mov     eax, [ids_lateral_state + ids_state_base_t.magic]
    cmp     eax, IDS_STATE_MAGIC
    jnz     .err_component_down

    test    rdi, rdi
    jz      .err_invalid_arg

    mov     r12, rdi              ; save connection context pointer

    ; STUB: detect Pass-the-Hash, Pass-the-Ticket patterns
    ; STEP: identify RDP, SSH, SMB lateral movement sessions
    ; STEP: detect unusual admin tool usage (PsExec, WMI, PowerShell)
    ; STEP: identify credential reuse across hosts
    ; STEP: return movement score and technique flag

    xor     eax, eax               ; STUB: no lateral movement
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

; STUB: ids_lateral_add_technique - add detection technique
; STUB: ids_lateral_remove_technique - remove detection technique
; STUB: ids_lateral_list_sessions - list suspicious sessions
; STUB: ids_lateral_get_stats - return detection statistics

%endif