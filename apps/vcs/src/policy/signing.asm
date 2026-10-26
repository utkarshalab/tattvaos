; =============================================================================
; File     : src/policy/signing.asm
; Project  : Utkarsha VCS (vcs)
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Commit signing through the shared Ed25519 library.
; =============================================================================

%ifndef VCS_POLICY_SIGNING_ASM
%define VCS_POLICY_SIGNING_ASM

%include "include/vcs.inc"

bits 64
default rel

extern ed25519_sign,ed25519_verify,ed25519_public_from_seed

section .text

; -----------------------------------------------------------------------------
; signing_sign — Sign a commit hash with a private key
; Input:  rdi = commit hash, rsi = private key, rdx = output signature
; Output: rax = VCS_OK or error
; -----------------------------------------------------------------------------
global signing_sign
signing_sign:
    push    rbx
    mov     rcx, rdx
    mov     rdx, 32
    xchg    rdi, rsi
    call    ed25519_sign
    cmp     rax, 1
    jne     .failed
    xor     eax, eax
    jmp     .done
.failed:
    mov     eax, VCS_ERR_GENERIC
.done:
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; signing_verify — Verify a commit signature against a public key
; Input:  rdi = commit hash, rsi = signature, rdx = public key
; Output: rax = VCS_OK or error
; -----------------------------------------------------------------------------
global signing_verify
signing_verify:
    push    rbx
    mov     rcx, rsi
    mov     rsi, rdi
    mov     rdi, rdx
    mov     rdx, 32
    call    ed25519_verify
    cmp     rax, 1
    jne     .invalid
    xor     eax, eax
    jmp     .done
.invalid:
    mov     eax, VCS_ERR_CORRUPT
.done:
    pop     rbx
    ret

; RDI = public-key output, RSI = 32-byte private seed.
global signing_public_from_seed
signing_public_from_seed:
    push    rbx
    call    ed25519_public_from_seed
    cmp     rax, 1
    jne     .failed
    xor     eax, eax
    jmp     .done
.failed:
    mov     eax, VCS_ERR_GENERIC
.done:
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; signing_key_generate — Generate a new signing key pair
; Input:  rdi = output private key, rsi = output public key
; Output: rax = VCS_OK or error
; -----------------------------------------------------------------------------
global signing_key_generate
signing_key_generate:
    push    rbx
    mov     eax, VCS_ERR_UNSUPPORTED
    pop     rbx
    ret

%endif ; VCS_POLICY_SIGNING_ASM
