%ifndef GUARD_SECURITY_PRIVACY_COMPLIANCE_CONSENT_ASM
%define GUARD_SECURITY_PRIVACY_COMPLIANCE_CONSENT_ASM

; =============================================================================
; File     : security/privacy_compliance/src/consent.asm
; Project  : Tattva OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: consent management (DSAR, data subject requests)
; Status   : PREMIUM ENTERPRISE - skeleton with full API surface.
; =============================================================================

bits 64
DEFAULT REL

%include "include/privacy.inc"

section .bss
alignb 16
privacy_consent_state:      resb privacy_state_base_t_size
privacy_consent_head:       resq 1
privacy_consent_count:      resq 1

section .data
alignb 16
privacy_consent_version_str: db PRIVACY_VERSION_STR, 0

section .text

; =============================================================================
; privacy_consent_init - Initialize consent management
; Input:  none
; Output: rax = 0 on success, negative error code on failure
; =============================================================================
global privacy_consent_init
privacy_consent_init:
    push    rbx
    mov     dword [privacy_consent_state + privacy_state_base_t.magic], PRIVACY_STATE_MAGIC
    mov     dword [privacy_consent_state + privacy_state_base_t.version], PRIVACY_VERSION_MAJOR
    mov     byte [privacy_consent_state + privacy_state_base_t.enabled], 1
    mov     qword [privacy_consent_head], 0
    mov     qword [privacy_consent_count], 0
    xor     eax, eax
    pop     rbx
    ret

; =============================================================================
; privacy_consent_shutdown - Shut down consent management
; Input:  none
; Output: rax = 0 on success
; =============================================================================
global privacy_consent_shutdown
privacy_consent_shutdown:
    push    rbx
    mov     eax, [privacy_consent_state + privacy_state_base_t.magic]
    cmp     eax, PRIVACY_STATE_MAGIC
    jnz     .not_init
    mov     dword [privacy_consent_state + privacy_state_base_t.magic], PRIVACY_STATE_MAGIC_FREED
    mov     byte [privacy_consent_state + privacy_state_base_t.enabled], 0
    xor     eax, eax
    pop     rbx
    ret
.not_init:
    mov     eax, -1
    pop     rbx
    ret

; =============================================================================
; privacy_consent_status - Return current consent management status
; Input:  none
; Output: rax = status code
; =============================================================================
global privacy_consent_status
privacy_consent_status:
    mov     eax, [privacy_consent_state + privacy_state_base_t.magic]
    cmp     eax, PRIVACY_STATE_MAGIC
    jnz     .not_init
    mov     al, [privacy_consent_state + privacy_state_base_t.enabled]
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
; privacy_consent_version - Return version string pointer
; Input:  none
; Output: rax = pointer to NUL-terminated version string
; =============================================================================
global privacy_consent_version
privacy_consent_version:
    mov     rax, privacy_consent_version_str
    ret

; =============================================================================
; privacy_consent_grant - Grant consent for a data subject
; Input:  rdi = subject ID, rsi = consent type (PRIVACY_CONSENT_*),
;         rdx = purpose pointer
; Output: rax = consent ID on success, negative error code on failure
; =============================================================================
global privacy_consent_grant
privacy_consent_grant:
    push    rbx
    push    r12
    push    r13

    mov     eax, [privacy_consent_state + privacy_state_base_t.magic]
    cmp     eax, PRIVACY_STATE_MAGIC
    jnz     .err_not_init

    test    rdx, rdx
    jz      .err_invalid_arg

    mov     r12, rsi              ; save consent type
    mov     r13, rdx              ; save purpose pointer

    ; STEP 1: Validate subject ID exists
    ; STEP 2: Check for existing consent of same type
    ; STEP 3: Create consent record (GRANTED state)
    ; STEP 4: Set granted_ns timestamp
    ; STEP 5: Insert into consent linked list
    ; STEP 6: Increment total_consents counter

    mov     rax, 1               ; STUB: return consent ID 1
    jmp     .done

.err_not_init:
    mov     rax, PRIVACY_ERR_NOT_INIT
    jmp     .done
.err_invalid_arg:
    mov     rax, PRIVACY_ERR_INVALID_ARG
    jmp     .done

.done:
    pop     r13
    pop     r12
    pop     rbx
    ret

; =============================================================================
; privacy_consent_withdraw - Withdraw consent for a data subject
; Input:  rdi = subject ID, rsi = consent type (PRIVACY_CONSENT_*)
; Output: rax = 0 on success, negative error code on failure
; =============================================================================
global privacy_consent_withdraw
privacy_consent_withdraw:
    push    rbx

    mov     eax, [privacy_consent_state + privacy_state_base_t.magic]
    cmp     eax, PRIVACY_STATE_MAGIC
    jnz     .err_not_init

    ; STEP 1: Validate subject ID exists
    ; STEP 2: Find consent record for type
    ; STEP 3: Set state to WITHDRAWN
    ; STEP 4: Set withdrawn_ns timestamp
    ; STEP 5: Trigger data processing stop for subject

    xor     eax, eax
    pop     rbx
    ret

.err_not_init:
    mov     rax, PRIVACY_ERR_NOT_INIT
    pop     rbx
    ret

; STUB: privacy_consent_get - retrieve consent by subject and type
; STUB: privacy_consent_list - list consents for subject
; STUB: privacy_consent_expire - expire expired consents
; STUB: privacy_consent_renew - renew expiring consents
; STUB: privacy_consent_revoke_all - revoke all consents for subject
; STUB: privacy_consent_export - export consent records
; STUB: privacy_consent_import - import consent records
; STUB: privacy_consent_get_stats - return consent statistics

%endif