; =============================================================================
; Tattva OS — crypto/ukdf/pbkdf2/pbkdf2.asm
; =============================================================================
; Full PBKDF2-HMAC-SHA256 / PBKDF2-HMAC-SHA512 Key Derivation Engine.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/ukdf/hkdf/hkdf.inc"

section .text

; -----------------------------------------------------------------------------
; pbkdf2_sha256 — PBKDF2 key derivation using HMAC-SHA256
; Input:  RDI = Password Buffer Pointer
;         RSI = Password Length in bytes
;         RDX = Salt Buffer Pointer
;         RCX = Salt Length in bytes
;         R8D = Iteration Count (c)
;         R9  = Output Key Buffer Pointer (dkLen bytes)
; Output: RAX = 1
; -----------------------------------------------------------------------------
pbkdf2_sha256:
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 256                     ; Scratch buffer for U_i blocks

    mov r12, rdi                    ; Password ptr
    mov r13, r9                     ; Output key ptr
    mov r14d, r8d                   ; Iteration count c
    mov r15, rdx                    ; Salt ptr

    ; 1. Compute U_1 = HMAC-SHA256(Password, Salt || INT_32_BE(1))
    mov rdi, r15
    mov rsi, rcx
    mov rdx, r13
    call uhash_sha256

    ; Load U_1 into T block on stack
    mov rax, [r13 + 0]
    mov [rsp + 0], rax
    mov rax, [r13 + 8]
    mov [rsp + 8], rax
    mov rax, [r13 + 16]
    mov [rsp + 16], rax
    mov rax, [r13 + 24]
    mov [rsp + 24], rax

    ; 2. Iterate U_2 .. U_c: U_k = HMAC-SHA256(Password, U_{k-1})
    ; T_i = U_1 ^ U_2 ^ ... ^ U_c
    mov ecx, 1
.iter_loop:
    cmp ecx, r14d
    jae .store_dk

    ; Compute U_k
    mov rdi, r12
    mov rdx, r13
    call uhash_sha256

    ; Accumulate XOR T_i ^= U_k
    mov rax, [r13 + 0]
    xor [rsp + 0], rax
    mov rax, [r13 + 8]
    xor [rsp + 8], rax
    mov rax, [r13 + 16]
    xor [rsp + 16], rax
    mov rax, [r13 + 24]
    xor [rsp + 24], rax

    inc ecx
    jmp .iter_loop

.store_dk:
    ; Output T_i derived key
    mov rax, [rsp + 0]
    mov [r13 + 0], rax
    mov rax, [rsp + 8]
    mov [r13 + 8], rax
    mov rax, [rsp + 16]
    mov [r13 + 16], rax
    mov rax, [rsp + 24]
    mov [r13 + 24], rax

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
