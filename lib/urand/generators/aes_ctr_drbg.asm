%ifndef GUARD_LIB_URAND_GENERATORS_AES_CTR_DRBG_ASM
%define GUARD_LIB_URAND_GENERATORS_AES_CTR_DRBG_ASM
; =============================================================================
; Tattva OS — lib/urand/generators/aes_ctr_drbg.asm
; =============================================================================
; CTR_DRBG (NIST SP 800-90A) over AES-256, using AES-NI.
;
; Implements:
;   - AES-256 key expansion and single-block encryption (`aes256_*`)
;   - The DRBG update step (`aes_ctr_drbg_update`)
;   - Block generation (`aes_ctr_drbg_generate`)
;
; The AES core is written here rather than pulled from crypto/ucrypt on
; purpose: lib/ must not depend upward on crypto/, and the entropy source is
; needed early. It is one key schedule and one encrypt — small enough that
; duplicating it costs less than the layering inversion would.
;
; WHY A SECOND GENERATOR AT ALL. ChaCha20 is the default and is what
; urand_get_bytes uses. CTR_DRBG exists because some deployments are required
; to run a NIST-approved DRBG, and because a structural break in one
; construction should not leave the system with no randomness at all. The
; generator is selected by urand_ctx_t.generator_id.
;
; THE UPDATE STEP IS NOT OPTIONAL. After every generate, the key and V are
; replaced with fresh keystream. That is what makes the DRBG forward-secure: an
; attacker who captures the state cannot roll it backwards to reproduce output
; already delivered. A CTR_DRBG that skips the update is a plain AES-CTR
; keystream with a fixed key, and everything it ever produced is recoverable
; from one state disclosure.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM), requires AES-NI
; =============================================================================

[BITS 64]

%include "lib/urand/urand.inc"

section .bss
alignb 64

; Expanded AES-256 round keys: 15 x 128 bits.
aes_drbg_roundkeys: resb 15 * 16

section .text

global aes256_expand_key
global aes256_encrypt_block
global aes_ctr_drbg_update
global aes_ctr_drbg_generate

; -----------------------------------------------------------------------------
; aes256_expand_key — expand a 256-bit key into 15 round keys.
;
; Inputs:
;   RDI = 32-byte key
;   RSI = Output, 15 * 16 bytes
;
; AES-256 alternates two derivations: even round keys apply RCON and a rotated
; SubWord, odd ones apply SubWord without rotation. AESKEYGENASSIST returns the
; word already substituted; the shuffle selects which of its four output words
; the schedule actually calls for, and the two cases need different ones —
; 0xFF for the rotated form, 0xAA for the unrotated.
; -----------------------------------------------------------------------------
align 32
aes256_expand_key:
    movdqu xmm1, [rdi]              ; K0
    movdqu xmm3, [rdi + 16]         ; K1
    movdqu [rsi], xmm1
    movdqu [rsi + 16], xmm3
    add rsi, 32

%macro AES256_EXPAND_EVEN 1
    aeskeygenassist xmm2, xmm3, %1
    pshufd xmm2, xmm2, 0xFF
    vpslldq xmm4, xmm1, 4
    pxor xmm1, xmm4
    vpslldq xmm4, xmm1, 4
    pxor xmm1, xmm4
    vpslldq xmm4, xmm1, 4
    pxor xmm1, xmm4
    pxor xmm1, xmm2
    movdqu [rsi], xmm1
    add rsi, 16
%endmacro

%macro AES256_EXPAND_ODD 0
    aeskeygenassist xmm2, xmm1, 0
    pshufd xmm2, xmm2, 0xAA
    vpslldq xmm4, xmm3, 4
    pxor xmm3, xmm4
    vpslldq xmm4, xmm3, 4
    pxor xmm3, xmm4
    vpslldq xmm4, xmm3, 4
    pxor xmm3, xmm4
    pxor xmm3, xmm2
    movdqu [rsi], xmm3
    add rsi, 16
%endmacro

    AES256_EXPAND_EVEN 0x01
    AES256_EXPAND_ODD
    AES256_EXPAND_EVEN 0x02
    AES256_EXPAND_ODD
    AES256_EXPAND_EVEN 0x04
    AES256_EXPAND_ODD
    AES256_EXPAND_EVEN 0x08
    AES256_EXPAND_ODD
    AES256_EXPAND_EVEN 0x10
    AES256_EXPAND_ODD
    AES256_EXPAND_EVEN 0x20
    AES256_EXPAND_ODD
    AES256_EXPAND_EVEN 0x40         ; Round key 14; the schedule stops here
    ret

; -----------------------------------------------------------------------------
; aes256_encrypt_block — one 16-byte block.
;
; Inputs:
;   RDI = 16-byte input
;   RSI = 16-byte output
;   RDX = 15 expanded round keys
;
; Fourteen rounds: thirteen AESENC and a final AESENCLAST, which omits
; MixColumns. Using AESENC for the last round produces ciphertext that no other
; AES implementation agrees with.
; -----------------------------------------------------------------------------
align 32
aes256_encrypt_block:
    movdqu xmm0, [rdi]
    movdqu xmm1, [rdx]
    pxor xmm0, xmm1

%assign r 1
%rep 13
    movdqu xmm1, [rdx + r*16]
    aesenc xmm0, xmm1
%assign r r+1
%endrep

    movdqu xmm1, [rdx + 14*16]
    aesenclast xmm0, xmm1
    movdqu [rsi], xmm0
    ret

; -----------------------------------------------------------------------------
; aes_ctr_drbg_update — replace Key and V with fresh keystream.
;
; Inputs:
;   RDI = urand_ctx_t
;   RSI = 48 bytes of provided data, or 0 for none
;
; Produces 48 bytes by encrypting successive counter values, XORs in the
; provided data, and takes the result as the new (Key, V).
; -----------------------------------------------------------------------------
align 32
aes_ctr_drbg_update:
    push rbx
    push r12
    push r13
    sub rsp, 64                     ; 48 bytes of temp, rounded up

    mov rbx, rdi                    ; ctx
    mov r12, rsi                    ; provided data or 0

    lea rdi, [rbx + urand_ctx_t.key]
    lea rsi, [aes_drbg_roundkeys]
    call aes256_expand_key

    xor r13d, r13d
.blocks:
    cmp r13d, 3
    jae .have_temp

    ; V is incremented BEFORE each encryption, per SP 800-90A.
    call aes_ctr_drbg_inc_v

    lea rdi, [rbx + urand_ctx_t.drbg_v]
    mov rsi, rsp
    mov eax, r13d
    shl eax, 4
    add rsi, rax
    lea rdx, [aes_drbg_roundkeys]
    call aes256_encrypt_block

    inc r13d
    jmp .blocks

.have_temp:
    test r12, r12
    jz .no_provided
%assign i 0
%rep 6
    mov rax, [r12 + i*8]
    xor [rsp + i*8], rax
%assign i i+1
%endrep
.no_provided:

%assign i 0
%rep 4
    mov rax, [rsp + i*8]
    mov [rbx + urand_ctx_t.key + i*8], rax
%assign i i+1
%endrep
    mov rax, [rsp + 32]
    mov [rbx + urand_ctx_t.drbg_v], rax
    mov rax, [rsp + 40]
    mov [rbx + urand_ctx_t.drbg_v + 8], rax

    mov rdi, rsp
    mov rsi, 64
    call urand_wipe_buffer

    add rsp, 64
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; aes_ctr_drbg_inc_v — V += 1, as a 128-bit big-endian counter.
;
; Big-endian because SP 800-90A treats V as a big-endian integer. Incrementing
; it little-endian still produces distinct blocks, so nothing looks broken —
; it just is not CTR_DRBG and will not match any test vector.
;
; Inputs:
;   RBX = urand_ctx_t
; -----------------------------------------------------------------------------
align 32
aes_ctr_drbg_inc_v:
    push rcx
    mov ecx, 15
.loop:
    inc byte [rbx + urand_ctx_t.drbg_v + rcx]
    jnz .done
    dec ecx
    jns .loop
.done:
    pop rcx
    ret

; -----------------------------------------------------------------------------
; aes_ctr_drbg_generate — one 64-byte output block group.
;
; Inputs:
;   RDI = urand_ctx_t
;   RSI = 64-byte output
;
; Returns:
;   RAX = 1
; -----------------------------------------------------------------------------
align 32
aes_ctr_drbg_generate:
    push rbx
    push r12
    push r13

    mov rbx, rdi                    ; ctx
    mov r12, rsi                    ; out

    lea rdi, [rbx + urand_ctx_t.key]
    lea rsi, [aes_drbg_roundkeys]
    call aes256_expand_key

    xor r13d, r13d
.blocks:
    cmp r13d, 4
    jae .done

    call aes_ctr_drbg_inc_v

    lea rdi, [rbx + urand_ctx_t.drbg_v]
    mov rsi, r12
    mov eax, r13d
    shl eax, 4
    add rsi, rax
    lea rdx, [aes_drbg_roundkeys]
    call aes256_encrypt_block

    inc r13d
    jmp .blocks

.done:
    ; Rotate the state forward so this output cannot be recomputed later.
    mov rdi, rbx
    xor esi, esi
    call aes_ctr_drbg_update

    inc qword [rbx + urand_ctx_t.blocks_out]

    mov rax, 1
    pop r13
    pop r12
    pop rbx
    ret

%endif ; GUARD_LIB_URAND_GENERATORS_AES_CTR_DRBG_ASM
