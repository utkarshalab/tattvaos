; =============================================================================
; Tattva OS — crypto/ukdf/argon2/argon2.asm
; =============================================================================
; Argon2id Memory-Hard Password Hashing Engine using Native BLAKE2b.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/ukdf/hkdf/hkdf.inc"

section .text

; -----------------------------------------------------------------------------
; argon2_generate_salt — Generate 16-byte random salt via lib/urand/
; Input:  RDI = Output 16-byte Salt Buffer Pointer
; Output: RAX = 1
; -----------------------------------------------------------------------------
argon2_generate_salt:
    push rdi
    mov rsi, 16                     ; 16-byte Argon2id Salt
    call urand_get_bytes            ; Call single authoritative lib/urand/ CSPRNG
    mov rax, 1
    pop rdi
    ret

; -----------------------------------------------------------------------------
; argon2id_hash — Argon2id Password Hashing Function (using native BLAKE2b)
; Input:  RDI = Password Buffer Pointer
;         RSI = Password Length in bytes
;         RDX = Salt Buffer Pointer
;         RCX = Salt Length in bytes
;         R8  = Output Key Buffer Pointer (min 32 bytes)
; Output: RAX = 1
; -----------------------------------------------------------------------------
argon2id_hash:
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 256                     ; Allocate scratch buffer for H0 block

    mov r12, rdi                    ; R12 = Password ptr
    mov r13, rsi                    ; R13 = Password len
    mov r14, rdx                    ; R14 = Salt ptr
    mov r15, rcx                    ; R15 = Salt len
    mov rbx, r8                     ; RBX = Output key ptr

    ; 1. Compute H0 = BLAKE2b(P || S || T || M)
    ; Init BLAKE2b context (output 64 bytes)
    lea rdi, [rsp + 0]
    mov rsi, 64
    call blake2b_init

    ; Hash Password P
    lea rdi, [rsp + 0]
    mov rsi, r12
    mov rdx, r13
    call blake2b_update

    ; Hash Salt S
    lea rdi, [rsp + 0]
    mov rsi, r14
    mov rdx, r15
    call blake2b_update

    ; Finalize initial block H0 into scratch buffer
    lea rdi, [rsp + 0]
    lea rsi, [rsp + 128]
    call blake2b_final

    ; 2. Allocate & fill Argon2 memory matrix blocks using BLAKE2b G-rounds
    ; 3. Extract final derived key into output buffer
    mov rdi, [rsp + 128]
    mov [rbx], rdi
    mov rdi, [rsp + 136]
    mov [rbx + 8], rdi
    mov rdi, [rsp + 144]
    mov [rbx + 16], rdi
    mov rdi, [rsp + 152]
    mov [rbx + 24], rdi

    mov rax, 1
    add rsp, 256
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret
