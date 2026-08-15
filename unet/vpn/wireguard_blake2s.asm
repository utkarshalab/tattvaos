%ifndef GUARD_UNET_VPN_WIREGUARD_BLAKE2S_ASM
%define GUARD_UNET_VPN_WIREGUARD_BLAKE2S_ASM
; =============================================================================
; Tattva OS — unet/vpn/wireguard_blake2s.asm
; =============================================================================
; BLAKE2s (RFC 7693) engine for WireGuard, plus the WireGuard-specific
; constructions built on top of it: HMAC-BLAKE2s, the Kdf1/Kdf2 key
; derivation chain (WireGuard whitepaper section 5.4.3), and the Mac1
; anti-DoS cookie (section 5.4.4).
;
; This file does NOT delegate to crypto/uhash/blake2/blake2s.asm — that file
; was inspected while wiring this one and its update()/final() are no-ops
; (update literally just `ret`s, final does a self-copy that discards state
; rather than serializing it), so it doesn't produce a usable hash. Rather
; than touch crypto/ (out of scope for this pass), this file implements
; BLAKE2s itself, scalar and RFC-correct: init/init_key/update/final all
; maintain real streaming state (64-byte block buffer, 64-bit byte counter,
; correct last-block finalization), and the compression function runs the
; real 10-round G-function schedule over the real SIGMA permutation table
; — not vectorized (the AVX2 in the function's name is legacy from the
; original scaffold; correctness came first), but it is the actual algorithm.
;
; What's still out of scope: this file provides real Mac1 generation
; (keyed-BLAKE2s MAC over the responder's static key, RFC-correct), but not
; Mac2/cookie-reply (which needs a randomized per-source cookie-under-load
; state machine that doesn't exist anywhere in this tree yet) or the full
; Noise_IKpsk2 handshake message framing (there is no wireguard_handshake.asm
; in this tree — this file is the only WireGuard file that exists, and its
; own scope per its header has always been the crypto primitives, not
; session/message assembly). unet/security/noise_protocol.asm has the
; generic Noise SymmetricState this file's key schedule mirrors.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define BLAKE2S_BLOCK_SIZE          64
%define BLAKE2S_OUT_SIZE            32

struc blake2s_ctx_t
    .h:                 resd 8      ; State Vector (8 x 32-bit words)
    .t:                 resd 2      ; Byte Counter (64-bit, split lo/hi)
    .f:                 resd 2      ; Finalization Flags
    .buf:               resb 64     ; Block Buffer
    .buflen:            resd 1
    .outlen:            resd 1
endstruc

section .data
align 32
wg_blake2s_iv:
    dd 0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A
    dd 0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19

; WireGuard whitepaper section 5.4 fixed labels.
wg_label_mac1:      db "mac1----"
wg_label_cookie:    db "cookie--"

section .text

global wireguard_blake2s_init
global wireguard_blake2s_init_key
global wireguard_blake2s_update
global wireguard_blake2s_final
global wireguard_blake2s_compress_avx2
global wireguard_hmac_blake2s
global wireguard_kdf1
global wireguard_kdf2
global wireguard_kdf3
global wireguard_generate_mac1

; -----------------------------------------------------------------------------
; BLAKE2S_G — one quarter-round of the BLAKE2s mixing function, RFC 7693 sec 3.1.
; %1..%4 = byte offsets of v[a],v[b],v[c],v[d] on the stack (rsp-relative)
; %5,%6  = message word indices (0..15) into the current 64-byte block at RBX
; Clobbers EAX, EDX.
; -----------------------------------------------------------------------------
%macro BLAKE2S_G 6
    mov eax, [rsp + %1]
    add eax, [rsp + %2]
    add eax, [rbx + blake2s_ctx_t.buf + (%5*4)]
    mov [rsp + %1], eax
    mov edx, [rsp + %4]
    xor edx, eax
    ror edx, 16
    mov [rsp + %4], edx
    mov eax, [rsp + %3]
    add eax, edx
    mov [rsp + %3], eax
    mov edx, [rsp + %2]
    xor edx, eax
    ror edx, 12
    mov [rsp + %2], edx
    mov eax, [rsp + %1]
    add eax, edx
    add eax, [rbx + blake2s_ctx_t.buf + (%6*4)]
    mov [rsp + %1], eax
    mov edx, [rsp + %4]
    xor edx, eax
    ror edx, 8
    mov [rsp + %4], edx
    mov eax, [rsp + %3]
    add eax, edx
    mov [rsp + %3], eax
    mov edx, [rsp + %2]
    xor edx, eax
    ror edx, 7
    mov [rsp + %2], edx
%endmacro

; v[] stack byte offsets: v0=0 v1=4 v2=8 v3=12 v4=16 v5=20 v6=24 v7=28
;                          v8=32 v9=36 v10=40 v11=44 v12=48 v13=52 v14=56 v15=60
%macro BLAKE2S_ROUND 16
    BLAKE2S_G  0,16,32,48, %1,%2
    BLAKE2S_G  4,20,36,52, %3,%4
    BLAKE2S_G  8,24,40,56, %5,%6
    BLAKE2S_G 12,28,44,60, %7,%8
    BLAKE2S_G  0,20,40,60, %9,%10
    BLAKE2S_G  4,24,44,48, %11,%12
    BLAKE2S_G  8,28,32,52, %13,%14
    BLAKE2S_G 12,16,36,56, %15,%16
%endmacro

; -----------------------------------------------------------------------------
; wireguard_blake2s_compress_avx2 — run one 64-byte block through the 10-round
; BLAKE2s compression function, updating ctx.h in place.
; Input:  RDI = blake2s_ctx_t* (ctx.buf holds the block, ctx.t/ctx.f are set)
; -----------------------------------------------------------------------------
align 64
wireguard_blake2s_compress_avx2:
    push rbx
    push rbp
    mov rbp, rsp
    mov rbx, rdi
    sub rsp, 64                       ; v[0..15]

    ; v[0..7] = h[0..7]
    mov ecx, 0
.load_h:
    mov eax, [rbx + blake2s_ctx_t.h + rcx*4]
    mov [rsp + rcx*4], eax
    inc ecx
    cmp ecx, 8
    jb .load_h

    ; v[8..15] = IV[0..7]
    lea rsi, [wg_blake2s_iv]
    mov ecx, 0
.load_iv:
    mov eax, [rsi + rcx*4]
    mov [rsp + 32 + rcx*4], eax
    inc ecx
    cmp ecx, 8
    jb .load_iv

    mov eax, [rbx + blake2s_ctx_t.t + 0]
    xor [rsp + 48], eax               ; v12 ^= t_low
    mov eax, [rbx + blake2s_ctx_t.t + 4]
    xor [rsp + 52], eax               ; v13 ^= t_high
    mov eax, [rbx + blake2s_ctx_t.f + 0]
    xor [rsp + 56], eax               ; v14 ^= f0
    mov eax, [rbx + blake2s_ctx_t.f + 4]
    xor [rsp + 60], eax               ; v15 ^= f1

    BLAKE2S_ROUND  0, 1, 2, 3, 4, 5, 6, 7, 8, 9,10,11,12,13,14,15
    BLAKE2S_ROUND 14,10, 4, 8, 9,15,13, 6, 1,12, 0, 2,11, 7, 5, 3
    BLAKE2S_ROUND 11, 8,12, 0, 5, 2,15,13,10,14, 3, 6, 7, 1, 9, 4
    BLAKE2S_ROUND  7, 9, 3, 1,13,12,11,14, 2, 6, 5,10, 4, 0,15, 8
    BLAKE2S_ROUND  9, 0, 5, 7, 2, 4,10,15,14, 1,11,12, 6, 8, 3,13
    BLAKE2S_ROUND  2,12, 6,10, 0,11, 8, 3, 4,13, 7, 5,15,14, 1, 9
    BLAKE2S_ROUND 12, 5, 1,15,14,13, 4,10, 0, 7, 6, 3, 9, 2, 8,11
    BLAKE2S_ROUND 13,11, 7,14,12, 1, 3, 9, 5, 0,15, 4, 8, 6, 2,10
    BLAKE2S_ROUND  6,15,14, 9,11, 3, 0, 8,12, 2,13, 7, 1, 4,10, 5
    BLAKE2S_ROUND 10, 2, 8, 4, 7, 6, 1, 5,15,11, 9,14, 3,12,13, 0

    ; h[i] ^= v[i] ^ v[i+8]
    mov ecx, 0
.fold_h:
    mov eax, [rsp + rcx*4]
    xor eax, [rsp + 32 + rcx*4]
    xor [rbx + blake2s_ctx_t.h + rcx*4], eax
    inc ecx
    cmp ecx, 8
    jb .fold_h

    mov rsp, rbp
    pop rbp
    pop rbx
    ret

; -----------------------------------------------------------------------------
; wireguard_blake2s_init — unkeyed init.
; Input:  RDI = ctx, ESI = output length (1..32)
; -----------------------------------------------------------------------------
align 64
wireguard_blake2s_init:
    push rbx
    push r12
    mov rbx, rdi
    mov r12d, esi

    lea rsi, [wg_blake2s_iv]
    lea rdi, [rbx + blake2s_ctx_t.h]
    mov ecx, 8
    rep movsd

    mov eax, 0x01010000
    or eax, r12d                      ; param block: keylen=0, digest_length=outlen
    xor [rbx + blake2s_ctx_t.h], eax

    mov dword [rbx + blake2s_ctx_t.t + 0], 0
    mov dword [rbx + blake2s_ctx_t.t + 4], 0
    mov dword [rbx + blake2s_ctx_t.f + 0], 0
    mov dword [rbx + blake2s_ctx_t.f + 4], 0
    mov dword [rbx + blake2s_ctx_t.buflen], 0
    mov [rbx + blake2s_ctx_t.outlen], r12d

    mov rax, 1
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; wireguard_blake2s_init_key — keyed init (RFC 7693 section 2.9): key becomes
; the zero-padded first block, buffered (not yet compressed).
; Input:  RDI = ctx, ESI = output length (1..32), RDX = key ptr, ECX = key len (1..32)
; -----------------------------------------------------------------------------
align 64
wireguard_blake2s_init_key:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 64

    mov rbx, rdi
    mov r12d, esi                     ; outlen
    mov r13, rdx                      ; key ptr
    mov r14d, ecx                     ; key len

    lea rsi, [wg_blake2s_iv]
    lea rdi, [rbx + blake2s_ctx_t.h]
    mov ecx, 8
    rep movsd

    mov eax, 0x01010000
    mov edx, r14d
    shl edx, 8
    or eax, edx                       ; keylen << 8
    or eax, r12d                      ; | outlen
    xor [rbx + blake2s_ctx_t.h], eax

    mov dword [rbx + blake2s_ctx_t.t + 0], 0
    mov dword [rbx + blake2s_ctx_t.t + 4], 0
    mov dword [rbx + blake2s_ctx_t.f + 0], 0
    mov dword [rbx + blake2s_ctx_t.f + 4], 0
    mov dword [rbx + blake2s_ctx_t.buflen], 0
    mov [rbx + blake2s_ctx_t.outlen], r12d

    ; Zero-pad the key into a 64-byte scratch block and feed it through update
    ; so it becomes the (buffered) first block, per the reference algorithm.
    xor eax, eax
    mov rdi, rsp
    mov rcx, 64
    rep stosb
    mov rdi, rsp
    mov rsi, r13
    mov rcx, r14
    rep movsb

    mov rdi, rbx
    mov rsi, rsp
    mov rdx, 64
    call wireguard_blake2s_update

    mov rax, 1
    add rsp, 64
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; wireguard_blake2s_update — absorb `len` bytes, compressing full blocks and
; buffering the remainder (the final chunk, even if exactly 64 bytes, is kept
; buffered so `final` can apply the last-block flag to it).
; Input: RDI = ctx, RSI = data, RDX = len
; -----------------------------------------------------------------------------
align 64
wireguard_blake2s_update:
    push rbx
    push r12
    push r13
    push r14

    mov rbx, rdi
    mov r12, rsi                      ; data
    mov r13, rdx                      ; len

    test r13, r13
    jz .u_done

    mov r14d, [rbx + blake2s_ctx_t.buflen]
    mov eax, BLAKE2S_BLOCK_SIZE
    sub eax, r14d                     ; fill = 64 - buflen

    cmp r13, rax
    jbe .u_buffer_only                ; len <= fill: nothing to compress yet

    ; Fill the buffer and compress it.
    movzx ecx, ax
    test ecx, ecx
    jz .u_no_fill
    lea rdi, [rbx + blake2s_ctx_t.buf + r14]
    mov rsi, r12
    push rax
    mov rcx, rax
    rep movsb
    pop rax
    add r12, rax
    sub r13, rax
.u_no_fill:
    add dword [rbx + blake2s_ctx_t.t + 0], BLAKE2S_BLOCK_SIZE
    adc dword [rbx + blake2s_ctx_t.t + 4], 0
    mov rdi, rbx
    call wireguard_blake2s_compress_avx2
    mov dword [rbx + blake2s_ctx_t.buflen], 0

    ; Compress remaining full blocks directly, always leaving the last
    ; (possibly full) block buffered rather than compressed.
.u_full_loop:
    cmp r13, BLAKE2S_BLOCK_SIZE
    jbe .u_buffer_only

    lea rdi, [rbx + blake2s_ctx_t.buf]
    mov rsi, r12
    mov rcx, BLAKE2S_BLOCK_SIZE
    rep movsb

    add dword [rbx + blake2s_ctx_t.t + 0], BLAKE2S_BLOCK_SIZE
    adc dword [rbx + blake2s_ctx_t.t + 4], 0
    mov rdi, rbx
    call wireguard_blake2s_compress_avx2

    add r12, BLAKE2S_BLOCK_SIZE
    sub r13, BLAKE2S_BLOCK_SIZE
    jmp .u_full_loop

.u_buffer_only:
    mov r14d, [rbx + blake2s_ctx_t.buflen]
    lea rdi, [rbx + blake2s_ctx_t.buf + r14]
    mov rsi, r12
    mov rcx, r13
    rep movsb
    add r14d, r13d
    mov [rbx + blake2s_ctx_t.buflen], r14d

.u_done:
    mov rax, 1
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; wireguard_blake2s_final — pad the last block, mark it final, compress, and
; copy ctx.outlen bytes of the resulting state out.
; Input:  RDI = ctx, RSI = output buffer (ctx.outlen bytes)
; -----------------------------------------------------------------------------
align 64
wireguard_blake2s_final:
    push rbx
    push r12
    mov rbx, rdi
    mov r12, rsi

    mov eax, [rbx + blake2s_ctx_t.buflen]
    add [rbx + blake2s_ctx_t.t + 0], eax
    adc dword [rbx + blake2s_ctx_t.t + 4], 0

    ; Zero-pad buf[buflen..64)
    mov ecx, [rbx + blake2s_ctx_t.buflen]
    cmp ecx, BLAKE2S_BLOCK_SIZE
    jae .no_pad
    lea rdi, [rbx + blake2s_ctx_t.buf + rcx]
    mov ecx, BLAKE2S_BLOCK_SIZE
    sub ecx, [rbx + blake2s_ctx_t.buflen]
    xor eax, eax
    rep stosb
.no_pad:

    mov dword [rbx + blake2s_ctx_t.f + 0], 0xFFFFFFFF

    mov rdi, rbx
    call wireguard_blake2s_compress_avx2

    mov ecx, [rbx + blake2s_ctx_t.outlen]
    lea rsi, [rbx + blake2s_ctx_t.h]
    mov rdi, r12
    rep movsb

    mov rax, 1
    pop r12
    pop rbx
    ret

; =============================================================================
; WireGuard-specific constructions built on the BLAKE2s engine above.
; =============================================================================

; -----------------------------------------------------------------------------
; wireguard_hmac_blake2s — HMAC construction (RFC 2104) with BLAKE2s as H,
; block size 64 bytes, digest size 32 bytes. This is the "HMAC-BLAKE2s" the
; WireGuard whitepaper's Kdf_n functions are built on (Noise spec sec 4.3).
; Input:  RDI = key ptr, RSI = key len, RDX = msg ptr, RCX = msg len,
;         R8  = 32-byte tag output
; Output: RAX = 1
; -----------------------------------------------------------------------------
align 64
wireguard_hmac_blake2s:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 128 + blake2s_ctx_t_size

    mov rbx, rdi                      ; key
    mov r12, rsi                      ; key len
    mov r13, rdx                      ; msg
    mov r14, rcx                      ; msg len
    mov r15, r8                       ; tag out

    ; Build K' (zero-padded/hashed to 64 bytes) at [rsp+64..127]
    xor eax, eax
    lea rdi, [rsp + 64]
    mov rcx, 64
    rep stosb

    cmp r12, BLAKE2S_BLOCK_SIZE
    jbe .short_key
    ; Long key: K' = BLAKE2s(K)
    lea rdi, [rsp + 192]               ; ctx
    mov esi, BLAKE2S_OUT_SIZE
    call wireguard_blake2s_init
    lea rdi, [rsp + 192]
    mov rsi, rbx
    mov rdx, r12
    call wireguard_blake2s_update
    lea rdi, [rsp + 192]
    lea rsi, [rsp + 64]
    call wireguard_blake2s_final
    jmp .have_kprime
.short_key:
    lea rdi, [rsp + 64]
    mov rsi, rbx
    mov rcx, r12
    rep movsb
.have_kprime:

    ; ipad block at [rsp+0..63]
    xor ecx, ecx
.xor_ipad:
    mov al, byte [rsp + 64 + rcx]
    xor al, 0x36
    mov byte [rsp + rcx], al
    inc ecx
    cmp ecx, BLAKE2S_BLOCK_SIZE
    jb .xor_ipad

    ; inner = BLAKE2s(ipad || msg)
    lea rdi, [rsp + 192]
    mov esi, BLAKE2S_OUT_SIZE
    call wireguard_blake2s_init
    lea rdi, [rsp + 192]
    lea rsi, [rsp]
    mov rdx, BLAKE2S_BLOCK_SIZE
    call wireguard_blake2s_update
    lea rdi, [rsp + 192]
    mov rsi, r13
    mov rdx, r14
    call wireguard_blake2s_update
    lea rdi, [rsp + 192]
    lea rsi, [rsp + 96]                ; inner digest -> [rsp+96..127]
    call wireguard_blake2s_final

    ; opad block, reusing [rsp+0..63]
    xor ecx, ecx
.xor_opad:
    mov al, byte [rsp + 64 + rcx]
    xor al, 0x5C
    mov byte [rsp + rcx], al
    inc ecx
    cmp ecx, BLAKE2S_BLOCK_SIZE
    jb .xor_opad

    lea rdi, [rsp + 192]
    mov esi, BLAKE2S_OUT_SIZE
    call wireguard_blake2s_init
    lea rdi, [rsp + 192]
    lea rsi, [rsp]
    mov rdx, BLAKE2S_BLOCK_SIZE
    call wireguard_blake2s_update
    lea rdi, [rsp + 192]
    lea rsi, [rsp + 96]
    mov rdx, BLAKE2S_OUT_SIZE
    call wireguard_blake2s_update
    lea rdi, [rsp + 192]
    mov rsi, r15
    call wireguard_blake2s_final

    mov rax, 1
    add rsp, 128 + blake2s_ctx_t_size
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; wireguard_kdf1 — WireGuard whitepaper 5.4.3: Kdf1(key, input) -> out1
;   T0 = HMAC-BLAKE2s(key, input); out1 = HMAC-BLAKE2s(T0, 0x1)
; Input:  RDI = key(32), RSI = input ptr, RDX = input len, RCX = out1(32)
; -----------------------------------------------------------------------------
align 64
wireguard_kdf1:
    push rbx
    push r12
    sub rsp, 48

    mov rbx, rcx                      ; out1

    mov rcx, rdx
    mov rdx, rsi
    mov rsi, 32                       ; key len
    lea r8, [rsp]                     ; T0
    call wireguard_hmac_blake2s

    mov byte [rsp + 32], 0x01
    mov rdi, rsp                      ; key = T0
    mov rsi, 32
    lea rdx, [rsp + 32]
    mov rcx, 1
    mov r8, rbx
    call wireguard_hmac_blake2s

    mov qword [rsp + 0], 0
    mov qword [rsp + 8], 0
    mov qword [rsp + 16], 0
    mov qword [rsp + 24], 0

    mov rax, 1
    add rsp, 48
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; wireguard_kdf2 — Kdf2(key, input) -> (out1, out2)
;   T0 = HMAC(key,input); out1 = HMAC(T0,0x1); out2 = HMAC(T0, out1||0x2)
; Input:  RDI = key(32), RSI = input ptr, RDX = input len, RCX = out1(32), R8 = out2(32)
; -----------------------------------------------------------------------------
align 64
wireguard_kdf2:
    push rbx
    push r12
    push r13
    sub rsp, 80                       ; [0..31]=T0 [32..63]=out1||tag scratch

    mov rbx, rcx                      ; out1
    mov r12, r8                       ; out2

    mov rcx, rdx
    mov rdx, rsi
    mov rsi, 32
    lea r8, [rsp]                     ; T0
    mov rdi, rdi                      ; key already in rdi
    call wireguard_hmac_blake2s

    mov byte [rsp + 64], 0x01
    mov rdi, rsp
    mov rsi, 32
    lea rdx, [rsp + 64]
    mov rcx, 1
    mov r8, rbx                       ; out1
    call wireguard_hmac_blake2s

    ; out2 = HMAC(T0, out1 || 0x02)
    mov rax, [rbx + 0]
    mov [rsp + 32], rax
    mov rax, [rbx + 8]
    mov [rsp + 40], rax
    mov rax, [rbx + 16]
    mov [rsp + 48], rax
    mov rax, [rbx + 24]
    mov [rsp + 56], rax
    mov byte [rsp + 64], 0x02

    mov rdi, rsp
    mov rsi, 32
    lea rdx, [rsp + 32]
    mov rcx, 33
    mov r8, r12
    call wireguard_hmac_blake2s

    mov qword [rsp + 0], 0
    mov qword [rsp + 8], 0
    mov qword [rsp + 16], 0
    mov qword [rsp + 24], 0

    mov rax, 1
    add rsp, 80
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; wireguard_kdf3 — Kdf3(key, input) -> (out1, out2, out3), used when mixing
; the optional pre-shared key into the handshake.
;   T0 = HMAC(key,input); out1 = HMAC(T0,0x1); out2 = HMAC(T0,out1||0x2);
;   out3 = HMAC(T0, out2||0x3)
; Input:  RDI = key(32), RSI = input ptr, RDX = input len,
;         RCX = out1(32), R8 = out2(32), R9 = out3(32)
; -----------------------------------------------------------------------------
align 64
wireguard_kdf3:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 96

    mov rbx, rcx                      ; out1
    mov r12, r8                       ; out2
    mov r13, r9                       ; out3

    mov rcx, rdx
    mov rdx, rsi
    mov rsi, 32
    lea r8, [rsp]                     ; T0
    call wireguard_hmac_blake2s

    mov byte [rsp + 64], 0x01
    mov rdi, rsp
    mov rsi, 32
    lea rdx, [rsp + 64]
    mov rcx, 1
    mov r8, rbx
    call wireguard_hmac_blake2s

    mov rax, [rbx + 0]
    mov [rsp + 32], rax
    mov rax, [rbx + 8]
    mov [rsp + 40], rax
    mov rax, [rbx + 16]
    mov [rsp + 48], rax
    mov rax, [rbx + 24]
    mov [rsp + 56], rax
    mov byte [rsp + 64], 0x02

    mov rdi, rsp
    mov rsi, 32
    lea rdx, [rsp + 32]
    mov rcx, 33
    mov r8, r12
    call wireguard_hmac_blake2s

    mov rax, [r12 + 0]
    mov [rsp + 32], rax
    mov rax, [r12 + 8]
    mov [rsp + 40], rax
    mov rax, [r12 + 16]
    mov [rsp + 48], rax
    mov rax, [r12 + 24]
    mov [rsp + 56], rax
    mov byte [rsp + 64], 0x03

    mov rdi, rsp
    mov rsi, 32
    lea rdx, [rsp + 32]
    mov rcx, 33
    mov r8, r13
    call wireguard_hmac_blake2s

    mov qword [rsp + 0], 0
    mov qword [rsp + 8], 0
    mov qword [rsp + 16], 0
    mov qword [rsp + 24], 0

    mov rax, 1
    add rsp, 96
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; wireguard_generate_mac1 — WireGuard whitepaper 5.4.4:
;   msg.mac1 = MAC(HASH(LABEL_MAC1 || responder_static_pubkey), msg[0:mac1_off])
; where MAC(key,input) is keyed-BLAKE2s truncated to 16 bytes.
; Input:  RDI = message pointer, RSI = length of message up to (not including) mac1,
;         RDX = responder static public key (32 bytes), RCX = 16-byte mac1 output
; Output: RAX = 1
; -----------------------------------------------------------------------------
align 64
wireguard_generate_mac1:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 96 + blake2s_ctx_t_size

    mov rbx, rdi                      ; msg
    mov r12, rsi                      ; msg len
    mov r13, rdx                      ; responder pubkey
    mov r14, rcx                      ; mac1 out

    ; keyhash = BLAKE2s(LABEL_MAC1 || pubkey), 32 bytes
    lea rdi, [rsp + 128]               ; ctx
    mov esi, BLAKE2S_OUT_SIZE
    call wireguard_blake2s_init
    lea rdi, [rsp + 128]
    lea rsi, [wg_label_mac1]
    mov rdx, 8
    call wireguard_blake2s_update
    lea rdi, [rsp + 128]
    mov rsi, r13
    mov rdx, 32
    call wireguard_blake2s_update
    lea rdi, [rsp + 128]
    lea rsi, [rsp]                    ; keyhash -> [rsp..31]
    call wireguard_blake2s_final

    ; mac1 = Keyed-BLAKE2s(key=keyhash, outlen=16)(msg)
    lea rdi, [rsp + 128]
    mov esi, 16
    lea rdx, [rsp]
    mov ecx, 32
    call wireguard_blake2s_init_key
    lea rdi, [rsp + 128]
    mov rsi, rbx
    mov rdx, r12
    call wireguard_blake2s_update
    lea rdi, [rsp + 128]
    mov rsi, r14
    call wireguard_blake2s_final

    mov rax, 1
    add rsp, 96 + blake2s_ctx_t_size
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

%endif ; GUARD_UNET_VPN_WIREGUARD_BLAKE2S_ASM
