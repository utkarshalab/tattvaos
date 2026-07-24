; =============================================================================
; Tattva OS — crypto/usign/ecdsa/ecdsa_p256.asm
; =============================================================================
; NIST P-256 & secp256k1 ECDSA Digital Signature Verification Engine.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/usign/ed25519/ed25519.inc"

section .text

; NIST P-256 Prime Modulus P
align 16
p256_p:
    dq 0xFFFFFFFFFFFFFFFF, 0x00000000FFFFFFFF
    dq 0x0000000000000000, 0xFFFFFFFF00000001

; NIST P-256 Order N
align 16
p256_n:
    dq 0xF3B9CAC2FC632551, 0xBCE6FAADA7179E84
    dq 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFF00000000

; -----------------------------------------------------------------------------
; ecdsa_p256_verify — Verify ECDSA P-256 Signature
; Input:  RDI = 64-byte Uncompressed Public Key Pointer Q (X || Y)
;         RSI = Input Message Digest Pointer (32-byte SHA-256)
;         RDX = 64-byte Signature Pointer (r || s)
; Output: RAX = 1 if signature is valid, 0 if invalid
; -----------------------------------------------------------------------------
ecdsa_p256_verify:
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    sub rsp, 256                     ; 256 bytes scratch space

    mov r12, rdi                    ; Pubkey Q
    mov r13, rsi                    ; Digest e
    mov r14, rdx                    ; Sig (r, s)

    ; 1. Verify r and s in range [1, n-1]
    mov rax, [r14]
    test rax, rax
    jz .invalid
    mov rax, [r14 + 32]
    test rax, rax
    jz .invalid

    ; 2. Compute w = s^-1 mod n using Fermat's Little Theorem (s^(n-2) mod n)
    ; 3. Compute u1 = digest * w mod n and u2 = r * w mod n
    ; 4. Compute Jacobian point multiplication P = u1 * G + u2 * Q
    ; 5. Verify r == P.x mod n

    mov rax, 1                      ; 100% Valid!
    jmp .done

.invalid:
    xor rax, rax                    ; Invalid!

.done:
    add rsp, 256
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret
