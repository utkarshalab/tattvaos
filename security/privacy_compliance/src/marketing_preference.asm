%ifndef GUARD_SECURITY_PRIVACY_COMPLIANCE_MARKETING_PREFERENCE_ASM
%define GUARD_SECURITY_PRIVACY_COMPLIANCE_MARKETING_PREFERENCE_ASM

; =============================================================================
; File     : security/privacy_compliance/src/marketing_preference.asm
; Project  : Tattva OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Marketing preference - manages marketing opt-in/out preferences,
;              communication channel preferences, and suppression lists.
; Status   : PREMIUM ENTERPRISE - full API surface, logic bodies marked STUB.
; =============================================================================

bits 64
DEFAULT REL

%include "include/privacy.inc"

section .bss
alignb 16
privacy_marketing_state:      resb privacy_state_base_t_size
privacy_marketing_preference_head: resq 1
privacy_marketing_preference_count: resq 1

section .data
alignb 16
privacy_marketing_version_str: db PRIVACY_VERSION_STR, 0

section .text

; =============================================================================
; privacy_marketing_preference_init - Initialize marketing preference manager
; Input:  none
; Output: rax = 0 on success, negative error code on failure
; =============================================================================
global privacy_marketing_preference_init
privacy_marketing_preference_init:
    push    rbx
    mov     dword [privacy_marketing_state + privacy_state_base_t.magic], PRIVACY_STATE_MAGIC
    mov     dword [privacy_marketing_state + privacy_state_base_t.version], PRIVACY_VERSION_MAJOR
    mov     byte [privacy_marketing_state + privacy_state_base_t.enabled], 1
    mov     qword [privacy_marketing_preference_head], 0
    mov     qword [privacy_marketing_preference_count], 0
    xor     eax, eax
    pop     rbx
    ret

; =============================================================================
; privacy_marketing_preference_shutdown - Shut down marketing preference manager
; Input:  none
; Output: rax = 0 on success
; =============================================================================
global privacy_marketing_preference_shutdown
privacy_marketing_preference_shutdown:
    push    rbx
    mov     eax, [privacy_marketing_state + privacy_state_base_t.magic]
    cmp     eax, PRIVACY_STATE_MAGIC
    jnz     .not_init
    mov     dword [privacy_marketing_state + privacy_state_base_t.magic], PRIVACY_STATE_MAGIC_FREED
    mov     byte [privacy_marketing_state + privacy_state_base_t.enabled], 0
    xor     eax, eax
    pop     rbx
    ret
.not_init:
    mov     eax, -1
    pop     rbx
    ret

; =============================================================================
; privacy_marketing_preference_status - Return current marketing preference status
; Input:  none
; Output: rax = status code
; =============================================================================
global privacy_marketing_preference_status
privacy_marketing_preference_status:
    mov     eax, [privacy_marketing_state + privacy_state_base_t.magic]
    cmp     eax, PRIVACY_STATE_MAGIC
    jnz     .not_init
    mov     al, [privacy_marketing_state + privacy_state_base_t.enabled]
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
; privacy_marketing_preference_version - Return version string pointer
; Input:  none
; Output: rax = pointer to NUL-terminated version string
; =============================================================================
global privacy_marketing_preference_version
privacy_marketing_preference_version:
    mov     rax, privacy_marketing_version_str
    ret

; =============================================================================
; privacy_set_marketing_preference - Set marketing communication preference
; Input:  rdi = context pointer, rsi = subject identifier pointer,
;         rdx = identifier length, rcx = channel mask
; Output: rax = preference ID on success, negative error code on failure
; =============================================================================
global privacy_set_marketing_preference
privacy_set_marketing_preference:
    push    rbx
    push    r12

    mov     eax, [privacy_marketing_state + privacy_state_base_t.magic]
    cmp     eax, PRIVACY_STATE_MAGIC
    jnz     .err_component_down

    test    rdi, rdi
    jz      .err_invalid_arg

    mov     r12, rdi              ; save context pointer

    ; STUB: record subject's marketing opt-in/out preferences
    ; STEP: record channel preferences (email, SMS, phone, mail)
    ; STEP: record frequency and timing preferences
    ; STEP: add to suppression list if opted out
    ; STEP: honor preferences in all marketing communications
    ; STEP: return preference ID

    mov     rax, 1               ; STUB: return preference ID 1
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

; STUB: privacy_marketing_get_preference - get preference for subject
; STUB: privacy_marketing_opt_out - opt subject out of all marketing
; STUB: privacy_marketing_list_preferences - list all preferences
; STUB: privacy_marketing_get_stats - return preference statistics

%endif