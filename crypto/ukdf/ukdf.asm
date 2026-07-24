; =============================================================================
; Tattva OS — crypto/ukdf/ukdf.asm
; =============================================================================
; Master Key Derivation Function Dispatcher API.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/ukdf/hkdf/hkdf.inc"

section .text

; -----------------------------------------------------------------------------
; ukdf_init — Initialize Key Derivation Engine
; Input:  none
; Output: RAX = 1
; -----------------------------------------------------------------------------
ukdf_init:
    mov rax, 1
    ret

; -----------------------------------------------------------------------------
; ukdf_derive_key — Master Key Derivation API
; Input:  RDI = Input Secret / Password Pointer
;         RSI = Secret Length in bytes
;         RDX = Salt Pointer
;         RCX = Salt Length in bytes
;         R8  = Output Key Buffer Pointer
;         R9D = Algorithm ID (UKDF_ALGO_HKDF_SHA256, ARGON2ID, PBKDF2)
; Output: RAX = 1 on success, 0 on failure
; -----------------------------------------------------------------------------
ukdf_derive_key:
    push rbx

    cmp r9d, UKDF_ALGO_ARGON2ID
    je .do_argon2
    cmp r9d, UKDF_ALGO_PBKDF2
    je .do_pbkdf2

    ; Default HKDF-SHA256
.do_hkdf:
    sub rsp, hkdf_ctx_t_size
    mov r8, rsp                     ; Output ctx
    call hkdf_extract

    mov rdi, rsp
    mov rsi, 0
    mov rdx, 0
    mov rcx, r8
    mov r8d, 32                     ; Output 32 bytes OKM
    call hkdf_expand

    add rsp, hkdf_ctx_t_size
    jmp .done

.do_argon2:
    call argon2id_hash
    jmp .done

.do_pbkdf2:
    mov r8d, 1000                   ; Default 1000 iterations
    call pbkdf2_sha256
    jmp .done

.done:
    pop rbx
    ret
