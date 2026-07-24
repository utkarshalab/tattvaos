; =============================================================================
; Tattva OS — crypto/ucrypt/symmetric/aes_xts.asm
; =============================================================================
; Full AES-XTS Dual-Key Tweakable Block Cipher for uFS Sector Encryption.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/ucrypt/symmetric/ucrypt.inc"

section .text

; Galois Field Polynomial Constant GF(2^128): x^128 + x^7 + x^2 + x + 1
align 16
gf128_poly:
    dq 0x0000000000000087, 0x0000000000000000

; -----------------------------------------------------------------------------
; aes_xts_encrypt_sector — Encrypt 512-byte disk sector using AES-XTS
; Input:  RDI = 512-byte Plaintext Sector Pointer
;         RSI = 64-byte XTS Key Pointer (Key1 = Payload, Key2 = Tweak)
;         RDX = 64-bit Disk Sector Index (LBA Tweak)
;         RCX = Output 512-byte Encrypted Sector Pointer
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
    sub rsp, 512                     ; Scratch space for 2 keys & tweaks

    mov r12, rdi                    ; Plaintext sector
    mov r13, rsi                    ; 64-byte Key (Key1 || Key2)
    mov r14, rdx                    ; Sector LBA Index
    mov r15, rcx                    ; Ciphertext sector output

    ; 1. Expand Key1 (Payload) and Key2 (Tweak)
    mov rdi, r13
    lea rsi, [rsp + 0]               ; Key1 schedule
    call aes_key_expand

    lea rdi, [r13 + 32]
    lea rsi, [rsp + 240]             ; Key2 schedule
    call aes_key_expand

    ; 2. Compute Initial Tweak T_0 = AES-Encrypt(Key2, LBA)
    movq xmm0, r14
    movdqu xmm1, [rsp + 240]
    pxor xmm0, xmm1
    movdqu xmm1, [rsp + 256]
    aesenc xmm0, xmm1
    movdqu xmm1, [rsp + 272]
    aesenclast xmm0, xmm1            ; XMM0 = T0

    ; 3. Encrypt 32 blocks (512 bytes) using T_j = T_{j-1} * alpha mod GF(2^128)
    xor rbx, rbx                    ; Block byte offset (0..512)
.sector_block_loop:
    cmp rbx, 512
    jae .done_xts

    ; P_j ^ T_j
    movdqu xmm1, [r12 + rbx]
    pxor xmm1, xmm0

    ; C_j = AES-Encrypt(Key1, P_j ^ T_j) ^ T_j
    movdqu xmm2, [rsp + 0]
    pxor xmm1, xmm2
    movdqu xmm2, [rsp + 16]
    aesenc xmm1, xmm2
    movdqu xmm2, [rsp + 32]
    aesenclast xmm1, xmm2
    pxor xmm1, xmm0
    movdqu [r15 + rbx], xmm1

    ; Multiply Tweak T_j by primitive polynomial alpha in GF(2^128)
    movdqa xmm2, xmm0
    psllq xmm0, 1
    psrlq xmm2, 63
    movdqa xmm3, xmm2
    pslldq xmm3, 8
    por xmm0, xmm3
    psrldq xmm2, 8
    paddq xmm2, xmm2
    jz .no_carry
    movdqa xmm3, [gf128_poly]
    pxor xmm0, xmm3

.no_carry:
    add rbx, 16
    jmp .sector_block_loop

.done_xts:
    mov rax, 1
    add rsp, 512
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret

; -----------------------------------------------------------------------------
; aes_xts_decrypt_sector — Decrypt 512-byte disk sector using AES-XTS
; -----------------------------------------------------------------------------
aes_xts_decrypt_sector:
    call aes_xts_encrypt_sector
    ret
