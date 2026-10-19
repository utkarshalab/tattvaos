%ifndef GUARD_SECURITY_USRAUTH_CAPABILITY_ISSUER_ASM
%define GUARD_SECURITY_USRAUTH_CAPABILITY_ISSUER_ASM

; =============================================================================
; File     : security/capability/src/issuer.asm
; Project  : Tattva OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: capability issuer (mints after authz check)
; Status   : SKELETON (stub) - enterprise grade, implementation pending.
; =============================================================================

bits 64

section .bss
alignb 16
issuer_enabled:   resb 1
issuer_state:      resq 1

section .data
alignb 16
issuer_version_str db "1.0.0-skeleton", 0

section .text


; -----------------------------------------------------------------------------
; cap_issuer_init - Initialize capability issuer (mints after authz check)
; Input:  none
; Output: rax = 0 on success
; -----------------------------------------------------------------------------
global cap_issuer_init
cap_issuer_init:
    ret

; -----------------------------------------------------------------------------
; cap_issuer_shutdown - Shut down capability issuer (mints after authz check)
; Input:  none
; Output: rax = 0 on success
; -----------------------------------------------------------------------------
global cap_issuer_shutdown
cap_issuer_shutdown:
    ret

; -----------------------------------------------------------------------------
; cap_issuer_status - Return current capability issuer (mints after authz check) status
; Output: rax = status code
; -----------------------------------------------------------------------------
global cap_issuer_status
cap_issuer_status:
    xor     eax, eax
    ret

; -----------------------------------------------------------------------------
; cap_issuer_version - Return version string pointer
; Output: rax = pointer to NUL-terminated version string
; -----------------------------------------------------------------------------
global cap_issuer_version
cap_issuer_version:
    mov     rax, cap_issuer_version
    ret


%endif
