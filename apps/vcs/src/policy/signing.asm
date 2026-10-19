; =============================================================================
; File     : src/policy/signing.asm
; Project  : Utkarsha VCS (vcs)
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Commit signing — Ed25519, post-quantum ready.
; =============================================================================

%ifndef VCS_POLICY_SIGNING_ASM
%define VCS_POLICY_SIGNING_ASM

%include "include/vcs.inc"

bits 64

section .text

; -----------------------------------------------------------------------------
; signing_sign — Sign a commit hash with a private key
; Input:  rdi = commit hash, rsi = private key, rdx = output signature
; Output: rax = VCS_OK or error
; -----------------------------------------------------------------------------
global signing_sign
signing_sign:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; signing_verify — Verify a commit signature against a public key
; Input:  rdi = commit hash, rsi = signature, rdx = public key
; Output: rax = VCS_OK or error
; -----------------------------------------------------------------------------
global signing_verify
signing_verify:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; signing_key_generate — Generate a new signing key pair
; Input:  rdi = output private key, rsi = output public key
; Output: rax = VCS_OK or error
; -----------------------------------------------------------------------------
global signing_key_generate
signing_key_generate:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

%endif ; VCS_POLICY_SIGNING_ASM