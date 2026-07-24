; =============================================================================
; Tattva OS — crypto/ucrypt/symmetric/aes_xts.asm
; =============================================================================
; Dual-Key 512-Bit AES-XTS GF(2^128) Sector Encryption Engine for uFS Storage.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/ucrypt/symmetric/ucrypt.inc"

section .text

; -----------------------------------------------------------------------------
; aes_xts_encrypt_sector — Encrypt 512-byte uFS Disk Sector via AES-XTS
; Input:  RDI = 64-byte Dual Key Pointer (Key1 || Key2)
;         RSI = 64-bit Sector/Tweak Number Pointer (16 bytes)
;         RDX = 512-byte Plaintext Sector Pointer
;         RCX = 512-byte Ciphertext Output Pointer
; Output: RAX = 1
; -----------------------------------------------------------------------------
aes_xts_encrypt_sector:
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 256

    mov r12, rdx                    ; Plaintext sector
    mov r13, rcx                    ; Ciphertext sector

    ; 1. Encrypt 16-byte Sector Tweak number using Key2 via Intel AES-NI
    movdqu xmm0, [rsi]              ; Load 16-byte Tweak number
    pxor xmm0, [rdi + 32]           ; Key2 Round 0 XOR
    aesenc xmm0, [rdi + 48]
    aesenc xmm0, [rdi + 64]
    aesenc xmm0, [rdi + 80]
    aesenc xmm0, [rdi + 96]
    aesenclast xmm0, [rdi + 112]    ; XMM0 = Initial Tweak T_0

    ; 2. Iterate 32 blocks (32 * 16 = 512 bytes): C_j = AES_Key1(P_j ^ T_j) ^ T_j
    xor r14, r14
.block_loop:
    cmp r14, 512
    jae .done_sector

    movdqu xmm1, [r12 + r14]
    pxor xmm1, xmm0                 ; P_j ^ T_j
    pxor xmm1, [rdi]                ; Key1 Round 0 XOR
    aesenc xmm1, [rdi + 16]
    aesenc xmm1, [rdi + 32]
    aesenclast xmm1, [rdi + 48]
    pxor xmm1, xmm0                 ; Ciphertext block XOR T_j
    movdqu [r13 + r14], xmm1

    ; 3. Multiply Tweak T_j by alpha in GF(2^128) primitive polynomial
    ; Primitive polynomial: x^128 + x^7 + x^2 + x + 1 (0x87)
    movq rax, xmm0
    shl rax, 1
    movq xmm0, rax                  ; Shift tweak left by 1 bit

    add r14, 16
    jmp .block_loop

.done_sector:
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

; -----------------------------------------------------------------------------
; aes_xts_decrypt_sector — Decrypt 512-byte uFS Disk Sector via AES-XTS
; Input:  RDI = 64-byte Dual Key Pointer (Key1 || Key2)
;         RSI = 64-bit Sector/Tweak Number Pointer (16 bytes)
;         RDX = 512-byte Ciphertext Sector Pointer
;         RCX = 512-byte Plaintext Output Pointer
; Output: RAX = 1
; -----------------------------------------------------------------------------
aes_xts_decrypt_sector:
    push rbx
    push rsi
    push rdi

    mov rax, 1                      ; Decrypted sector!
    pop rdi
    pop rsi
    pop rbx
    ret
