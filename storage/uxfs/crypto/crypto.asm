%ifndef GUARD_STORAGE_UXFS_CRYPTO_CRYPTO_ASM
%define GUARD_STORAGE_UXFS_CRYPTO_CRYPTO_ASM
; =============================================================================
; Tattva OS — storage/uxfs/crypto/crypto.asm
; =============================================================================
; AES-256-XTS Storage Block Encryption via AES-NI.
;
; Implements:
;   - AES-256 key schedule expansion (`uxfs_aes256_expand_key`)
;   - Inverse schedule for decryption (`uxfs_aes256_expand_key_dec`)
;   - Single-block AES-256 ECB primitives (`uxfs_aes256_encrypt/decrypt_block`)
;   - XTS context setup and sector encryption (`uxfs_xts_init`,
;     `uxfs_crypto_encrypt_block`, `uxfs_crypto_decrypt_block`)
;
; XTS is the mode disk encryption needs because a sector must encrypt in place,
; with no room for an IV or a MAC. It gets its per-block uniqueness from a
; tweak instead:
;
;   T  = AES-Enc(K2, sector_number)          ; once per sector
;   Cj = AES-Enc(K1, Pj XOR T) XOR T         ; per 16-byte block
;   T  = T * alpha                           ; advance in GF(2^128)
;
; Two independent keys are mandatory. K1 encrypts data, K2 derives the tweak.
; Reusing one key for both breaks the security proof, which is why an
; "AES-256-XTS" key is 64 bytes, not 32.
;
; The tweak advance is a multiply by alpha in GF(2^128) modulo
; x^128 + x^7 + x^2 + x + 1: shift the whole 128-bit value left one bit and,
; if a bit carried out the top, XOR 0x87 into the low byte.
;
; NOTE: this file previously alternated two XMM registers as though they were
; a key schedule, applied no tweak at all, and XORed the wrong key first when
; decrypting. It produced output, but it was not AES, not XTS, and not
; reversible by any other implementation.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM, AES-NI + SSE2)
; =============================================================================

%include "storage/uxfs/uxfs.inc"

%define UXFS_AES256_ROUNDS           14
%define UXFS_AES256_RK_BYTES         240     ; 15 round keys x 16 bytes
%define UXFS_XTS_KEY_BYTES           64      ; K1 (32) + K2 (32)
%define UXFS_XTS_BLOCK               16
%define UXFS_XTS_BLOCKS_PER_SECTOR   (UXFS_BLOCK_SIZE / UXFS_XTS_BLOCK)

; -----------------------------------------------------------------------------
; Expanded key material for one volume. Built once at mount, not per block.
; -----------------------------------------------------------------------------
struc uxfs_xts_ctx_t
    .rk_data_enc:       resb UXFS_AES256_RK_BYTES   ; K1 forward schedule
    .rk_data_dec:       resb UXFS_AES256_RK_BYTES   ; K1 inverse schedule
    .rk_tweak_enc:      resb UXFS_AES256_RK_BYTES   ; K2 forward schedule
    .valid:             resq 1
endstruc

; -----------------------------------------------------------------------------
; AES-256 key expansion helpers.
;
; AESKEYGENASSIST computes SubWord/RotWord/Rcon; the shift-and-xor chain below
; is the w[i] = w[i-8] XOR temp recurrence. AES-256 alternates two variants:
; every 8th word applies RotWord and an Rcon, every 4th applies SubWord alone.
; -----------------------------------------------------------------------------
%macro AES256_KEY_A 0
    pshufd  xmm2, xmm2, 0xFF        ; Broadcast the Rcon-bearing word
    movdqa  xmm4, xmm0
    pslldq  xmm4, 4
    pxor    xmm0, xmm4
    pslldq  xmm4, 4
    pxor    xmm0, xmm4
    pslldq  xmm4, 4
    pxor    xmm0, xmm4
    pxor    xmm0, xmm2
%endmacro

%macro AES256_KEY_B 0
    pshufd  xmm2, xmm2, 0xAA        ; SubWord-only variant: no Rcon
    movdqa  xmm4, xmm1
    pslldq  xmm4, 4
    pxor    xmm1, xmm4
    pslldq  xmm4, 4
    pxor    xmm1, xmm4
    pslldq  xmm4, 4
    pxor    xmm1, xmm4
    pxor    xmm1, xmm2
%endmacro

section .rodata
align 16

; Reduction constant for GF(2^128): x^128 + x^7 + x^2 + x + 1.
uxfs_xts_poly:      dq 0x0000000000000087, 0x0000000000000000
uxfs_xts_mask_hi:   dq 0x0000000000000000, 0xFFFFFFFFFFFFFFFF
uxfs_xts_mask_lo:   dq 0xFFFFFFFFFFFFFFFF, 0x0000000000000000

section .text

global uxfs_aes256_expand_key
global uxfs_aes256_expand_key_dec
global uxfs_aes256_encrypt_block
global uxfs_aes256_decrypt_block
global uxfs_xts_init
global uxfs_crypto_encrypt_block
global uxfs_crypto_decrypt_block
global uxfs_crypto_has_aesni

; -----------------------------------------------------------------------------
; uxfs_crypto_has_aesni
;
; Returns:
;   EAX = 1 when AES-NI is available, 0 otherwise
; -----------------------------------------------------------------------------
align 32
uxfs_crypto_has_aesni:
    push rbx
    mov eax, 1
    cpuid
    bt ecx, 25                      ; CPUID.01H:ECX[25] = AESNI
    jnc .na_no
    mov eax, 1
    pop rbx
    ret
.na_no:
    xor eax, eax
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_aes256_expand_key
;
; Expands a 256-bit key into 15 round keys.
;
; Inputs:
;   RDI = Pointer to the 32-byte key
;   RSI = Pointer to a 240-byte round key buffer
;
; Returns:
;   EAX = 0
; -----------------------------------------------------------------------------
align 32
uxfs_aes256_expand_key:
    movdqu  xmm0, [rdi]             ; w0..w3
    movdqu  xmm1, [rdi + 16]        ; w4..w7
    movdqu  [rsi], xmm0             ; Round key 0
    movdqu  [rsi + 16], xmm1        ; Round key 1

    aeskeygenassist xmm2, xmm1, 0x01
    AES256_KEY_A
    movdqu  [rsi + 32], xmm0
    aeskeygenassist xmm2, xmm0, 0x00
    AES256_KEY_B
    movdqu  [rsi + 48], xmm1

    aeskeygenassist xmm2, xmm1, 0x02
    AES256_KEY_A
    movdqu  [rsi + 64], xmm0
    aeskeygenassist xmm2, xmm0, 0x00
    AES256_KEY_B
    movdqu  [rsi + 80], xmm1

    aeskeygenassist xmm2, xmm1, 0x04
    AES256_KEY_A
    movdqu  [rsi + 96], xmm0
    aeskeygenassist xmm2, xmm0, 0x00
    AES256_KEY_B
    movdqu  [rsi + 112], xmm1

    aeskeygenassist xmm2, xmm1, 0x08
    AES256_KEY_A
    movdqu  [rsi + 128], xmm0
    aeskeygenassist xmm2, xmm0, 0x00
    AES256_KEY_B
    movdqu  [rsi + 144], xmm1

    aeskeygenassist xmm2, xmm1, 0x10
    AES256_KEY_A
    movdqu  [rsi + 160], xmm0
    aeskeygenassist xmm2, xmm0, 0x00
    AES256_KEY_B
    movdqu  [rsi + 176], xmm1

    aeskeygenassist xmm2, xmm1, 0x20
    AES256_KEY_A
    movdqu  [rsi + 192], xmm0
    aeskeygenassist xmm2, xmm0, 0x00
    AES256_KEY_B
    movdqu  [rsi + 208], xmm1

    aeskeygenassist xmm2, xmm1, 0x40
    AES256_KEY_A
    movdqu  [rsi + 224], xmm0       ; Round key 14, the final one

    xor eax, eax
    ret

; -----------------------------------------------------------------------------
; uxfs_aes256_expand_key_dec
;
; Builds the inverse schedule for equivalent-inverse-cipher decryption: the
; round keys in reverse order, with the middle ones passed through AESIMC.
; The first and last are used as-is — AESDEC/AESDECLAST expect exactly that.
;
; Inputs:
;   RDI = Pointer to the 240-byte forward schedule
;   RSI = Pointer to a 240-byte inverse schedule buffer
;
; Returns:
;   EAX = 0
; -----------------------------------------------------------------------------
align 32
uxfs_aes256_expand_key_dec:
    push rbx
    push r12

    ; dec[0] = enc[14]
    movdqu  xmm0, [rdi + 224]
    movdqu  [rsi], xmm0

    ; dec[i] = AESIMC(enc[14 - i]) for i = 1..13
    mov     rbx, 1

.ed_loop:
    cmp     rbx, 14
    jae     .ed_last

    mov     rax, 14
    sub     rax, rbx
    shl     rax, 4                  ; * 16 bytes
    movdqu  xmm0, [rdi + rax]
    aesimc  xmm0, xmm0

    mov     rax, rbx
    shl     rax, 4
    movdqu  [rsi + rax], xmm0

    inc     rbx
    jmp     .ed_loop

.ed_last:
    ; dec[14] = enc[0]
    movdqu  xmm0, [rdi]
    movdqu  [rsi + 224], xmm0

    xor eax, eax
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_aes256_encrypt_block
;
; One 16-byte AES-256 ECB encryption: 13 AESENC rounds plus AESENCLAST.
;
; Inputs:
;   RDI = Pointer to the 240-byte forward schedule
;   RSI = Pointer to 16 bytes of plaintext
;   RDX = Pointer to a 16-byte ciphertext buffer
;
; Returns:
;   EAX = 0
; -----------------------------------------------------------------------------
align 32
uxfs_aes256_encrypt_block:
    movdqu  xmm0, [rsi]
    movdqu  xmm1, [rdi]
    pxor    xmm0, xmm1              ; Round 0: whitening

    movdqu  xmm1, [rdi + 16]
    aesenc  xmm0, xmm1
    movdqu  xmm1, [rdi + 32]
    aesenc  xmm0, xmm1
    movdqu  xmm1, [rdi + 48]
    aesenc  xmm0, xmm1
    movdqu  xmm1, [rdi + 64]
    aesenc  xmm0, xmm1
    movdqu  xmm1, [rdi + 80]
    aesenc  xmm0, xmm1
    movdqu  xmm1, [rdi + 96]
    aesenc  xmm0, xmm1
    movdqu  xmm1, [rdi + 112]
    aesenc  xmm0, xmm1
    movdqu  xmm1, [rdi + 128]
    aesenc  xmm0, xmm1
    movdqu  xmm1, [rdi + 144]
    aesenc  xmm0, xmm1
    movdqu  xmm1, [rdi + 160]
    aesenc  xmm0, xmm1
    movdqu  xmm1, [rdi + 176]
    aesenc  xmm0, xmm1
    movdqu  xmm1, [rdi + 192]
    aesenc  xmm0, xmm1
    movdqu  xmm1, [rdi + 208]
    aesenc  xmm0, xmm1

    movdqu  xmm1, [rdi + 224]
    aesenclast xmm0, xmm1           ; Final round omits MixColumns

    movdqu  [rdx], xmm0
    xor eax, eax
    ret

; -----------------------------------------------------------------------------
; uxfs_aes256_decrypt_block
;
; One 16-byte AES-256 decryption using the inverse schedule.
;
; Inputs:
;   RDI = Pointer to the 240-byte INVERSE schedule
;   RSI = Pointer to 16 bytes of ciphertext
;   RDX = Pointer to a 16-byte plaintext buffer
;
; Returns:
;   EAX = 0
; -----------------------------------------------------------------------------
align 32
uxfs_aes256_decrypt_block:
    movdqu  xmm0, [rsi]
    movdqu  xmm1, [rdi]
    pxor    xmm0, xmm1

    movdqu  xmm1, [rdi + 16]
    aesdec  xmm0, xmm1
    movdqu  xmm1, [rdi + 32]
    aesdec  xmm0, xmm1
    movdqu  xmm1, [rdi + 48]
    aesdec  xmm0, xmm1
    movdqu  xmm1, [rdi + 64]
    aesdec  xmm0, xmm1
    movdqu  xmm1, [rdi + 80]
    aesdec  xmm0, xmm1
    movdqu  xmm1, [rdi + 96]
    aesdec  xmm0, xmm1
    movdqu  xmm1, [rdi + 112]
    aesdec  xmm0, xmm1
    movdqu  xmm1, [rdi + 128]
    aesdec  xmm0, xmm1
    movdqu  xmm1, [rdi + 144]
    aesdec  xmm0, xmm1
    movdqu  xmm1, [rdi + 160]
    aesdec  xmm0, xmm1
    movdqu  xmm1, [rdi + 176]
    aesdec  xmm0, xmm1
    movdqu  xmm1, [rdi + 192]
    aesdec  xmm0, xmm1
    movdqu  xmm1, [rdi + 208]
    aesdec  xmm0, xmm1

    movdqu  xmm1, [rdi + 224]
    aesdeclast xmm0, xmm1

    movdqu  [rdx], xmm0
    xor eax, eax
    ret

; -----------------------------------------------------------------------------
; uxfs_xts_init
;
; Expands a 64-byte XTS key into a reusable context. Do this once per volume at
; mount; expanding per block would dominate the cost of encryption entirely.
;
; Inputs:
;   RDI = Pointer to the 64-byte XTS key (K1 then K2)
;   RSI = Pointer to a uxfs_xts_ctx_t
;
; Returns:
;   EAX = 0 on success, POSIX_EINVAL on a null argument,
;         POSIX_ENODEV when AES-NI is absent
; -----------------------------------------------------------------------------
align 32
uxfs_xts_init:
    push rbx
    push r12

    mov rbx, rdi                    ; Key
    mov r12, rsi                    ; Context

    test rbx, rbx
    jz .xi_inval
    test r12, r12
    jz .xi_inval

    call uxfs_crypto_has_aesni
    test eax, eax
    jz .xi_nodev

    ; K1 forward schedule.
    mov rdi, rbx
    lea rsi, [r12 + uxfs_xts_ctx_t.rk_data_enc]
    call uxfs_aes256_expand_key

    ; K1 inverse schedule for decryption.
    lea rdi, [r12 + uxfs_xts_ctx_t.rk_data_enc]
    lea rsi, [r12 + uxfs_xts_ctx_t.rk_data_dec]
    call uxfs_aes256_expand_key_dec

    ; K2 forward schedule. The tweak is only ever encrypted, so no inverse.
    lea rdi, [rbx + 32]
    lea rsi, [r12 + uxfs_xts_ctx_t.rk_tweak_enc]
    call uxfs_aes256_expand_key

    mov qword [r12 + uxfs_xts_ctx_t.valid], 1

    xor eax, eax
    pop r12
    pop rbx
    ret

.xi_nodev:
    mov eax, POSIX_ENODEV
    pop r12
    pop rbx
    ret

.xi_inval:
    mov eax, POSIX_EINVAL
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; Advance the tweak in XMM3 by one multiplication by alpha.
;
; Shift the full 128-bit value left one bit; if a bit carried out of the top,
; fold in the reduction constant 0x87. The two qword halves shift
; independently, so the low half's carry has to be moved into the high half by
; hand.
; -----------------------------------------------------------------------------
%macro XTS_ADVANCE_TWEAK 0
    movdqa  xmm4, xmm3
    psllq   xmm3, 1                 ; Independent per-qword shift
    psrlq   xmm4, 63                ; Carry bit out of each qword
    pshufd  xmm5, xmm4, 0x4E        ; Swap halves: low carry lines up with high

    movdqa  xmm6, xmm5
    pand    xmm6, [uxfs_xts_mask_hi]
    por     xmm3, xmm6              ; Propagate low -> high

    pand    xmm5, [uxfs_xts_mask_lo]
    movq    rax, xmm5               ; 0 or 1: did bit 127 carry out
    imul    rax, 0x87               ; Scale to the reduction constant
    movq    xmm6, rax
    pxor    xmm3, xmm6
%endmacro

; -----------------------------------------------------------------------------
; uxfs_crypto_encrypt_block
;
; Encrypts one 4KB sector with AES-256-XTS.
;
; Inputs:
;   RDI = Pointer to the 4KB plaintext sector
;   RSI = Pointer to the 4KB ciphertext output buffer
;   RDX = Pointer to an initialised uxfs_xts_ctx_t
;   RCX = Sector number, the XTS tweak input
;
; Returns:
;   EAX = 0 on success, POSIX_EINVAL when the context is not initialised
; -----------------------------------------------------------------------------
align 32
uxfs_crypto_encrypt_block:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 32                     ; Scratch for the tweak block

    mov rbx, rdi                    ; Plaintext
    mov r12, rsi                    ; Ciphertext
    mov r13, rdx                    ; Context
    mov r14, rcx                    ; Sector number

    test r13, r13
    jz .ce_inval
    cmp qword [r13 + uxfs_xts_ctx_t.valid], 0
    je .ce_inval

    ; T = AES-Enc(K2, sector_number as a little-endian 128-bit value)
    mov [rsp], r14
    mov qword [rsp + 8], 0

    lea rdi, [r13 + uxfs_xts_ctx_t.rk_tweak_enc]
    mov rsi, rsp
    mov rdx, rsp
    call uxfs_aes256_encrypt_block

    movdqu xmm3, [rsp]              ; Running tweak

    ; Counter lives in a callee-saved register: the AES helper is free to
    ; clobber RCX, and the tweak in XMM3 must survive the whole sector.
    mov r15, UXFS_XTS_BLOCKS_PER_SECTOR

.ce_loop:
    movdqu  xmm0, [rbx]
    pxor    xmm0, xmm3              ; PP = P XOR T
    movdqu  [rsp + 16], xmm0

    lea rdi, [r13 + uxfs_xts_ctx_t.rk_data_enc]
    lea rsi, [rsp + 16]
    lea rdx, [rsp + 16]
    call uxfs_aes256_encrypt_block

    movdqu  xmm0, [rsp + 16]
    pxor    xmm0, xmm3              ; C = CC XOR T
    movdqu  [r12], xmm0

    XTS_ADVANCE_TWEAK

    add rbx, UXFS_XTS_BLOCK
    add r12, UXFS_XTS_BLOCK
    dec r15
    jnz .ce_loop

    xor eax, eax
    jmp .ce_return

.ce_inval:
    mov eax, POSIX_EINVAL

.ce_return:
    add rsp, 32
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_crypto_decrypt_block
;
; Decrypts one 4KB sector with AES-256-XTS.
;
; The tweak sequence is identical to encryption — it depends only on the sector
; number, not on the data — so it is regenerated the same way and applied
; around AESDEC instead of AESENC.
;
; Inputs:
;   RDI = Pointer to the 4KB ciphertext sector
;   RSI = Pointer to the 4KB plaintext output buffer
;   RDX = Pointer to an initialised uxfs_xts_ctx_t
;   RCX = Sector number
;
; Returns:
;   EAX = 0 on success, POSIX_EINVAL when the context is not initialised
; -----------------------------------------------------------------------------
align 32
uxfs_crypto_decrypt_block:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 32

    mov rbx, rdi                    ; Ciphertext
    mov r12, rsi                    ; Plaintext
    mov r13, rdx                    ; Context
    mov r14, rcx                    ; Sector number

    test r13, r13
    jz .cd_inval
    cmp qword [r13 + uxfs_xts_ctx_t.valid], 0
    je .cd_inval

    ; Same tweak derivation as the encrypt path.
    mov [rsp], r14
    mov qword [rsp + 8], 0

    lea rdi, [r13 + uxfs_xts_ctx_t.rk_tweak_enc]
    mov rsi, rsp
    mov rdx, rsp
    call uxfs_aes256_encrypt_block

    movdqu xmm3, [rsp]

    mov r15, UXFS_XTS_BLOCKS_PER_SECTOR

.cd_loop:
    movdqu  xmm0, [rbx]
    pxor    xmm0, xmm3              ; CC = C XOR T
    movdqu  [rsp + 16], xmm0

    lea rdi, [r13 + uxfs_xts_ctx_t.rk_data_dec]
    lea rsi, [rsp + 16]
    lea rdx, [rsp + 16]
    call uxfs_aes256_decrypt_block

    movdqu  xmm0, [rsp + 16]
    pxor    xmm0, xmm3              ; P = PP XOR T
    movdqu  [r12], xmm0

    XTS_ADVANCE_TWEAK

    add rbx, UXFS_XTS_BLOCK
    add r12, UXFS_XTS_BLOCK
    dec r15
    jnz .cd_loop

    xor eax, eax
    jmp .cd_return

.cd_inval:
    mov eax, POSIX_EINVAL

.cd_return:
    add rsp, 32
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

%endif ; GUARD_STORAGE_UXFS_CRYPTO_CRYPTO_ASM
