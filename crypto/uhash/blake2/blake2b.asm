%ifndef GUARD_CRYPTO_UHASH_BLAKE2_BLAKE2B_ASM
%define GUARD_CRYPTO_UHASH_BLAKE2_BLAKE2B_ASM
; =============================================================================
; Tattva OS — crypto/uhash/blake2/blake2b.asm
; =============================================================================
; BLAKE2b (RFC 7693) — 64-bit hashing, digests of 1..64 bytes.
;
; Implements:
;   - Streaming API (`blake2b_init`, `blake2b_update`, `blake2b_final`)
;   - One-shot convenience (`blake2b_hash`)
;   - Keyed mode (`blake2b_init_key`), which Argon2 does not use but which the
;     parameter block must encode correctly either way
;
; The compression function is the whole algorithm: twelve rounds of eight G
; operations over a sixteen-word working vector, half seeded from the chaining
; state and half from the IV.
;
; THE LAST BLOCK IS HELD BACK. `update` compresses a full buffer only when it
; has confirmed more input is coming, so the final block is always processed by
; `final` with the finalization flag set. Compressing eagerly on a full buffer
; is the classic BLAKE2 mistake: a message whose length is an exact multiple of
; 128 bytes then gets its last block compressed twice, or compressed without
; the flag, and the digest is wrong for exactly those lengths — which ordinary
; testing on short strings never reaches.
;
; The counter t counts bytes, not blocks, and it is advanced BEFORE compressing
; the block it describes. It counts bytes actually consumed, so the final,
; partial block advances it by its true length rather than by 128.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

[BITS 64]

%define BLAKE2B_BLOCKBYTES   128
%define BLAKE2B_OUTBYTES     64

struc blake2b_ctx_t
    .h:         resq 8                      ; Chaining state
    .t:         resq 2                      ; 128-bit byte counter
    .f:         resq 2                      ; Finalization flags
    .buf:       resb BLAKE2B_BLOCKBYTES     ; Partial block
    .buflen:    resq 1
    .outlen:    resq 1
endstruc

section .data
align 64

blake2b_iv:
    dq 0x6A09E667F3BCC908, 0xBB67AE8584CAA73B
    dq 0x3C6EF372FE94F82B, 0xA54FF53A5F1D36F1
    dq 0x510E527FADE682D1, 0x9B05688C2B3E6C1F
    dq 0x1F83D9ABFB41BD6B, 0x5BE0CD19137E2179

; Message schedule. Rounds 10 and 11 repeat rows 0 and 1 — BLAKE2b runs twelve
; rounds over a ten-row table, so the table is not simply "one row per round".
blake2b_sigma:
    db  0,  1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15
    db 14, 10,  4,  8,  9, 15, 13,  6,  1, 12,  0,  2, 11,  7,  5,  3
    db 11,  8, 12,  0,  5,  2, 15, 13, 10, 14,  3,  6,  7,  1,  9,  4
    db  7,  9,  3,  1, 13, 12, 11, 14,  2,  6,  5, 10,  4,  0, 15,  8
    db  9,  0,  5,  7,  2,  4, 10, 15, 14,  1, 11, 12,  6,  8,  3, 13
    db  2, 12,  6, 10,  0, 11,  8,  3,  4, 13,  7,  5, 15, 14,  1,  9
    db 12,  5,  1, 15, 14, 13,  4, 10,  0,  7,  6,  3,  9,  2,  8, 11
    db 13, 11,  7, 14, 12,  1,  3,  9,  5,  0, 15,  4,  8,  6,  2, 10
    db  6, 15, 14,  9, 11,  3,  0,  8, 12,  2, 13,  7,  1,  4, 10,  5
    db 10,  2,  8,  4,  7,  6,  1,  5, 15, 11,  9, 14,  3, 12, 13,  0
    db  0,  1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15
    db 14, 10,  4,  8,  9, 15, 13,  6,  1, 12,  0,  2, 11,  7,  5,  3

section .text

global blake2b_init
global blake2b_init_key
global blake2b_update
global blake2b_final
global blake2b_hash
global blake2b_compress

; -----------------------------------------------------------------------------
; BLAKE2B_G — one G operation on the working vector.
;
;   a = a + b + x;  d = (d ^ a) >>> 32;  c = c + d;  b = (b ^ c) >>> 24
;   a = a + b + y;  d = (d ^ a) >>> 16;  c = c + d;  b = (b ^ c) >>> 63
;
; %1..%4 are v[] slot indices; %5,%6 are byte offsets into the current sigma
; row, supplying the two message words.
;
; b is kept in RDX across the halves rather than written back and reloaded,
; because the second half must see the value the first half produced.
;
; Clobbers RAX, RDX, R8..R11. Expects RSI = current sigma row, RBP = message
; block, and v[] at [RSP].
; -----------------------------------------------------------------------------
%macro BLAKE2B_G 6
    movzx   r8d, byte [rsi + %5]
    mov     r9,  [rbp + r8*8]               ; x
    mov     rax, [rsp + %1*8]
    add     rax, [rsp + %2*8]
    add     rax, r9                         ; a = a + b + x
    mov     r10, [rsp + %4*8]
    xor     r10, rax
    ror     r10, 32                         ; d
    mov     r11, [rsp + %3*8]
    add     r11, r10                        ; c
    mov     rdx, [rsp + %2*8]
    xor     rdx, r11
    ror     rdx, 24                         ; b

    movzx   r8d, byte [rsi + %6]
    mov     r9,  [rbp + r8*8]               ; y
    add     rax, rdx
    add     rax, r9                         ; a = a + b + y
    mov     [rsp + %1*8], rax
    xor     r10, rax
    ror     r10, 16
    mov     [rsp + %4*8], r10
    add     r11, r10
    mov     [rsp + %3*8], r11
    xor     rdx, r11
    ror     rdx, 63
    mov     [rsp + %2*8], rdx
%endmacro

; -----------------------------------------------------------------------------
; blake2b_compress
;
; Inputs:
;   RDI = Context
;   RSI = 128-byte message block
;   EDX = Nonzero for the final block
;
; The caller advances ctx.t before calling, because only the caller knows how
; many bytes the block actually carries.
; -----------------------------------------------------------------------------
align 32
blake2b_compress:
    push rbp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 128                            ; v[0..15]

    mov r12, rdi                            ; Context
    mov rbp, rsi                            ; Message block
    mov r13d, edx                           ; Final-block flag

    ; v[0..7] = h[0..7]
%assign i 0
%rep 8
    mov rax, [r12 + blake2b_ctx_t.h + i*8]
    mov [rsp + i*8], rax
%assign i i+1
%endrep

    ; v[8..15] = IV[0..7]
    lea r14, [blake2b_iv]
%assign i 0
%rep 8
    mov rax, [r14 + i*8]
    mov [rsp + 64 + i*8], rax
%assign i i+1
%endrep

    ; The counter enters the state here; without it, two different messages
    ; that share a final block would collide.
    mov rax, [r12 + blake2b_ctx_t.t]
    xor [rsp + 12*8], rax
    mov rax, [r12 + blake2b_ctx_t.t + 8]
    xor [rsp + 13*8], rax

    test r13d, r13d
    jz .not_final
    not qword [rsp + 14*8]
.not_final:

    lea rsi, [blake2b_sigma]
    mov r15d, 12
.round:
    BLAKE2B_G 0, 4,  8, 12,  0,  1
    BLAKE2B_G 1, 5,  9, 13,  2,  3
    BLAKE2B_G 2, 6, 10, 14,  4,  5
    BLAKE2B_G 3, 7, 11, 15,  6,  7
    BLAKE2B_G 0, 5, 10, 15,  8,  9
    BLAKE2B_G 1, 6, 11, 12, 10, 11
    BLAKE2B_G 2, 7,  8, 13, 12, 13
    BLAKE2B_G 3, 4,  9, 14, 14, 15
    add rsi, 16
    dec r15d
    jnz .round

    ; h[i] ^= v[i] ^ v[i+8]
%assign i 0
%rep 8
    mov rax, [rsp + i*8]
    xor rax, [rsp + 64 + i*8]
    xor [r12 + blake2b_ctx_t.h + i*8], rax
%assign i i+1
%endrep

    add rsp, 128
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; blake2b_init
;
; Inputs:
;   RDI = Context
;   ESI = Digest length, 1..64
;
; Returns:
;   EAX = 1 on success, 0 if the digest length is out of range
; -----------------------------------------------------------------------------
align 32
blake2b_init:
    xor edx, edx                            ; No key
    xor ecx, ecx
    jmp blake2b_init_key

; -----------------------------------------------------------------------------
; blake2b_init_key
;
; Inputs:
;   RDI = Context
;   ESI = Digest length, 1..64
;   RDX = Key pointer (may be null)
;   ECX = Key length, 0..64
;
; Returns:
;   EAX = 1 on success, 0 on a bad parameter
;
; A key is absorbed as one full zero-padded block BEFORE the message. That
; block counts toward t like any other, which is why it goes through the same
; update path rather than being special-cased.
; -----------------------------------------------------------------------------
align 32
blake2b_init_key:
    push rbx
    push r12
    push r13
    push r14

    mov r12, rdi
    mov r13d, esi                           ; outlen
    mov r14, rdx                            ; key
    mov ebx, ecx                            ; keylen

    test r13d, r13d
    jz .bad
    cmp r13d, BLAKE2B_OUTBYTES
    ja .bad
    cmp ebx, 64
    ja .bad
    test r14, r14
    jnz .key_ok
    test ebx, ebx
    jnz .bad                                ; Nonzero length with a null key
.key_ok:

    ; h = IV
    lea rax, [blake2b_iv]
%assign i 0
%rep 8
    mov rdx, [rax + i*8]
    mov [r12 + blake2b_ctx_t.h + i*8], rdx
%assign i i+1
%endrep

    ; Parameter block, folded into h[0]: digest length, key length, fanout 1,
    ; depth 1. Two contexts differing only in digest length must not produce
    ; one output as a prefix of the other, which is exactly what encoding the
    ; length here prevents.
    mov eax, 0x01010000
    or eax, r13d
    mov edx, ebx
    shl edx, 8
    or eax, edx
    xor [r12 + blake2b_ctx_t.h], rax

    xor eax, eax
    mov [r12 + blake2b_ctx_t.t], rax
    mov [r12 + blake2b_ctx_t.t + 8], rax
    mov [r12 + blake2b_ctx_t.f], rax
    mov [r12 + blake2b_ctx_t.f + 8], rax
    mov [r12 + blake2b_ctx_t.buflen], rax
    mov eax, r13d
    mov [r12 + blake2b_ctx_t.outlen], rax

    test ebx, ebx
    jz .done

    ; Absorb the key as a padded block.
    lea rdi, [r12 + blake2b_ctx_t.buf]
    mov rsi, r14
    mov ecx, ebx
    rep movsb
    lea rdi, [r12 + blake2b_ctx_t.buf]
    add rdi, rbx
    mov ecx, BLAKE2B_BLOCKBYTES
    sub ecx, ebx
    xor eax, eax
    rep stosb
    mov qword [r12 + blake2b_ctx_t.buflen], BLAKE2B_BLOCKBYTES

.done:
    mov eax, 1
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.bad:
    xor eax, eax
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; blake2b_update
;
; Inputs:
;   RDI = Context
;   RSI = Input pointer
;   RDX = Input length
; -----------------------------------------------------------------------------
align 32
blake2b_update:
    push rbx
    push r12
    push r13
    push r14

    mov r12, rdi
    mov r13, rsi
    mov r14, rdx

    test r14, r14
    jz .done
    test r13, r13
    jz .done

.loop:
    mov rax, [r12 + blake2b_ctx_t.buflen]
    cmp rax, BLAKE2B_BLOCKBYTES
    jb .space

    ; The buffer is full AND input remains, so this block is provably not the
    ; last one and may be compressed without the finalization flag.
    add qword [r12 + blake2b_ctx_t.t], BLAKE2B_BLOCKBYTES
    adc qword [r12 + blake2b_ctx_t.t + 8], 0

    mov rdi, r12
    lea rsi, [r12 + blake2b_ctx_t.buf]
    xor edx, edx
    call blake2b_compress

    xor eax, eax
    mov [r12 + blake2b_ctx_t.buflen], rax

.space:
    mov rbx, BLAKE2B_BLOCKBYTES
    sub rbx, rax                            ; Free space in the buffer
    cmp rbx, r14
    jbe .take
    mov rbx, r14
.take:
    lea rdi, [r12 + blake2b_ctx_t.buf]
    add rdi, rax
    mov rsi, r13
    mov rcx, rbx
    rep movsb

    add [r12 + blake2b_ctx_t.buflen], rbx
    add r13, rbx
    sub r14, rbx
    jnz .loop

.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; blake2b_final
;
; Inputs:
;   RDI = Context
;   RSI = Output buffer, at least ctx.outlen bytes
;
; The state is left finalized; calling update afterwards would produce a
; meaningless result, so callers re-init instead.
; -----------------------------------------------------------------------------
align 32
blake2b_final:
    push rbx
    push r12
    push r13

    mov r12, rdi
    mov r13, rsi

    ; Advance by the true length of this block, not by 128.
    mov rbx, [r12 + blake2b_ctx_t.buflen]
    add [r12 + blake2b_ctx_t.t], rbx
    adc qword [r12 + blake2b_ctx_t.t + 8], 0

    ; Zero-pad the tail. Stale bytes here would leak previous input into the
    ; digest and make it depend on what the buffer happened to hold.
    lea rdi, [r12 + blake2b_ctx_t.buf]
    add rdi, rbx
    mov rcx, BLAKE2B_BLOCKBYTES
    sub rcx, rbx
    xor eax, eax
    rep stosb

    mov qword [r12 + blake2b_ctx_t.f], -1

    mov rdi, r12
    lea rsi, [r12 + blake2b_ctx_t.buf]
    mov edx, 1
    call blake2b_compress

    ; h is little-endian on x86, so the digest is a straight byte copy.
    mov rcx, [r12 + blake2b_ctx_t.outlen]
    lea rsi, [r12 + blake2b_ctx_t.h]
    mov rdi, r13
    rep movsb

    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; blake2b_hash — one-shot.
;
; Inputs:
;   RDI = Output buffer
;   ESI = Digest length, 1..64
;   RDX = Input pointer
;   RCX = Input length
;
; Returns:
;   EAX = 1 on success, 0 on a bad digest length
; -----------------------------------------------------------------------------
align 32
blake2b_hash:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, blake2b_ctx_t_size

    mov r12, rdi
    mov r13d, esi
    mov r14, rdx
    mov rbx, rcx

    mov rdi, rsp
    mov esi, r13d
    call blake2b_init
    test eax, eax
    jz .out

    mov rdi, rsp
    mov rsi, r14
    mov rdx, rbx
    call blake2b_update

    mov rdi, rsp
    mov rsi, r12
    call blake2b_final

    mov eax, 1

.out:
    add rsp, blake2b_ctx_t_size
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

%endif ; GUARD_CRYPTO_UHASH_BLAKE2_BLAKE2B_ASM
