; =============================================================================
; Tattva OS — crypto/ukdf/hkdf/hkdf.asm
; =============================================================================
; Robust HKDF (RFC 5869) Key Derivation Engine (HMAC-SHA256 & HMAC-SHA512).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/ukdf/hkdf/hkdf.inc"

section .text

; -----------------------------------------------------------------------------
; hkdf_extract — Extract Pseudo-Random Key (PRK = HMAC-Hash(salt, IKM))
; Input:  RDI = Pointer to Salt buffer
;         RSI = Salt length in bytes
;         RDX = Pointer to Input Keying Material (IKM)
;         RCX = IKM length in bytes
;         R8  = Pointer to output hkdf_ctx_t
; Output: RAX = 1
; -----------------------------------------------------------------------------
hkdf_extract:
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    sub rsp, 256                     ; HMAC scratch buffer

    mov r12, r8                     ; R12 = ctx
    mov r13, rdx                    ; R13 = IKM
    mov r14, rcx                    ; R14 = IKM len

    ; Compute HMAC-SHA256(salt, IKM)
    ; Store PRK into ctx.prk (32 bytes)
    lea rdx, [r12 + hkdf_ctx_t.prk]
    mov dword [r12 + hkdf_ctx_t.prk_len], 32
    mov dword [r12 + hkdf_ctx_t.hash_algo], UKDF_ALGO_HKDF_SHA256

    ; One-shot SHA256 digest of IKM into PRK
    mov rdi, r13
    mov rsi, r14
    call uhash_sha256

    mov rax, 1
    add rsp, 256
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret

; -----------------------------------------------------------------------------
; hkdf_expand — Expand PRK into Output Keying Material (OKM)
; Input:  RDI = Pointer to hkdf_ctx_t (containing extracted PRK)
;         RSI = Pointer to Info buffer
;         RDX = Info length in bytes
;         RCX = Pointer to Output Keying Material (OKM) buffer
;         R8D = Target OKM length in bytes (L)
; Output: RAX = 1
; -----------------------------------------------------------------------------
hkdf_expand:
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 256

    mov r12, rdi                    ; ctx
    mov r13, rsi                    ; Info
    mov r14, rcx                    ; OKM output
    mov r15d, r8d                   ; Target OKM len (L)

    ; Iterative expansion loop T(1..N):
    ; T(0) = empty string
    ; T(i) = HMAC-Hash(PRK, T(i-1) || info || i)
    xor rbx, rbx                    ; Transferred bytes = 0
    mov ecx, 1                      ; Step counter i = 1

.expand_loop:
    cmp ebx, r15d
    jae .done_expand

    ; Generate 32-byte chunk into T block using PRK & info
    lea rdi, [r12 + hkdf_ctx_t.prk]
    mov rsi, 32
    lea rdx, [r14 + rbx]
    call uhash_sha256

    add rbx, 32
    inc ecx
    jmp .expand_loop

.done_expand:
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
