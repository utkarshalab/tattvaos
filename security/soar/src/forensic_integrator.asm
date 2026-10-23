%ifndef GUARD_SECURITY_SOAR_SRC_FORENSIC_INTEGRATOR_ASM
%define GUARD_SECURITY_SOAR_SRC_FORENSIC_INTEGRATOR_ASM

; =============================================================================
; File     : security/soar/src/forensic_integrator.asm
; Project  : Utkarsha OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: SOAR Forensic Integrator - connects to digital_forensics module
;              for deep forensic analysis, evidence preservation, and
;              incident reconstruction during investigations.
; Status   : PREMIUM ENTERPRISE - full API surface, logic bodies marked STUB.
; =============================================================================

bits 64
DEFAULT REL

%include "include/soar.inc"

section .bss
alignb 16
soar_forensic_state:     resb soar_state_base_t_size
soar_forensic_case_head: resq 1
soar_forensic_case_count:resq 1

section .data
alignb 16
soar_forensic_version_str: db SOAR_VERSION_STR, 0

section .text

; =============================================================================
; soar_forensic_init - Initialize forensic integrator
; Input:  none
; Output: rax = 0 on success, negative error code on failure
; =============================================================================
global soar_forensic_init
soar_forensic_init:
    push    rbx
    mov     dword [soar_forensic_state + soar_state_base_t.magic], SOAR_STATE_MAGIC
    mov     dword [soar_forensic_state + soar_state_base_t.version], SOAR_VERSION_MAJOR
    mov     byte [soar_forensic_state + soar_state_base_t.enabled], 1
    mov     qword [soar_forensic_case_head], 0
    mov     qword [soar_forensic_case_count], 0
    xor     eax, eax
    pop     rbx
    ret

; =============================================================================
; soar_forensic_shutdown - Shut down forensic integrator
; Input:  none
; Output: rax = 0 on success
; =============================================================================
global soar_forensic_shutdown
soar_forensic_shutdown:
    push    rbx
    mov     eax, [soar_forensic_state + soar_state_base_t.magic]
    cmp     eax, SOAR_STATE_MAGIC
    jnz     .not_init
    mov     dword [soar_forensic_state + soar_state_base_t.magic], SOAR_STATE_MAGIC_FREED
    mov     byte [soar_forensic_state + soar_state_base_t.enabled], 0
    xor     eax, eax
    pop     rbx
    ret
.not_init:
    mov     eax, -1
    pop     rbx
    ret

; =============================================================================
; soar_forensic_status - Return current forensic integrator status
; Input:  none
; Output: rax = status code
; =============================================================================
global soar_forensic_status
soar_forensic_status:
    mov     eax, [soar_forensic_state + soar_state_base_t.magic]
    cmp     eax, SOAR_STATE_MAGIC
    jnz     .not_init
    mov     al, [soar_forensic_state + soar_state_base_t.enabled]
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
; soar_forensic_version - Return version string pointer
; Input:  none
; Output: rax = pointer to NUL-terminated version string
; =============================================================================
global soar_forensic_version
soar_forensic_version:
    mov     rax, soar_forensic_version_str
    ret

; =============================================================================
; soar_forensic_request_analysis - Request forensic analysis of an incident
; Input:  rdi = incident context pointer, rsi = incident ID,
;         rdx = analysis type, rcx = scope pointer
; Output: rax = analysis request ID on success, negative error code on failure
; =============================================================================
global soar_forensic_request_analysis
soar_forensic_request_analysis:
    push    rbx
    push    r12

    mov     eax, [soar_forensic_state + soar_state_base_t.magic]
    cmp     eax, SOAR_STATE_MAGIC
    jnz     .err_component_down

    test    rdi, rdi
    jz      .err_invalid_arg

    mov     r12, rdi              ; save incident context pointer

    ; STUB: validate incident exists and is assigned
    ; STEP: create forensic case in digital_forensics module
    ; STEP: define analysis scope and evidence collection targets
    ; STEP: schedule forensic examiners and tools
    ; STEP: return analysis request ID

    mov     rax, 1                ; STUB: return request ID 1
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

; STUB: soar_forensic_get_analysis_results - get forensic analysis results
; STUB: soar_forensic_list_cases - list all forensic cases
; STUB: soar_forensic_preserve_evidence - request evidence preservation
; STUB: soar_forensic_get_stats - return integration statistics

%endif