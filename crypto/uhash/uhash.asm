%ifndef GUARD_CRYPTO_UHASH_UHASH_ASM
%define GUARD_CRYPTO_UHASH_UHASH_ASM
; =============================================================================
; Tattva OS — crypto/uhash/uhash.asm
; =============================================================================
; Master Cryptographic Hashing Dispatcher & One-Shot API.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

section .text

; -----------------------------------------------------------------------------
; uhash_sha256 — One-shot SHA-256 computation
; Input:  RDI = Input buffer pointer
;         RSI = Input length in bytes
;         RDX = Output 32-byte digest buffer pointer
; Output: RAX = 1
; -----------------------------------------------------------------------------
uhash_sha256:
    push rbx
    push rsi
    push rdi
    sub rsp, sha256_ctx_t_size

    mov rbx, rdx                    ; RBX = output digest buffer pointer
    mov r8, rdi                     ; R8 = src buffer
    mov r9, rsi                     ; R9 = src len

    ; 1. Init
    mov rdi, rsp
    call sha256_init

    ; 2. Update
    mov rdi, rsp
    mov rsi, r8
    mov rdx, r9
    call sha256_update

    ; 3. Final
    mov rdi, rsp
    mov rsi, rbx
    call sha256_final

    mov rax, 1
    add rsp, sha256_ctx_t_size
    pop rdi
    pop rsi
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uhash_blake3 — One-shot BLAKE3 computation
; Input:  RDI = Input buffer pointer
;         RSI = Input length in bytes
;         RDX = Output 32-byte digest buffer pointer
; Output: RAX = 1
; -----------------------------------------------------------------------------
uhash_blake3:
    push rbx
    push rsi
    push rdi
    sub rsp, blake3_ctx_t_size

    mov rbx, rdx
    mov r8, rdi
    mov r9, rsi

    mov rdi, rsp
    call blake3_init

    mov rdi, rsp
    mov rsi, r8
    mov rdx, r9
    call blake3_update

    mov rdi, rsp
    mov rsi, rbx
    call blake3_final

    mov rax, 1
    add rsp, blake3_ctx_t_size
    pop rdi
    pop rsi
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uhash_sha512 — One-shot SHA-512 computation
; Input:  RDI = Input buffer pointer
;         RSI = Input length in bytes
;         RDX = Output 64-byte digest buffer pointer
; Output: RAX = 1
; -----------------------------------------------------------------------------
uhash_sha512:
    push rbx
    push rsi
    push rdi
    sub rsp, sha512_ctx_t_size

    mov rbx, rdx
    mov r8, rdi
    mov r9, rsi

    mov rdi, rsp
    call sha512_init

    mov rdi, rsp
    mov rsi, r8
    mov rdx, r9
    call sha512_update

    mov rdi, rsp
    mov rsi, rbx
    call sha512_final

    mov rax, 1
    add rsp, sha512_ctx_t_size
    pop rdi
    pop rsi
    pop rbx
    ret

%endif ; GUARD_CRYPTO_UHASH_UHASH_ASM
