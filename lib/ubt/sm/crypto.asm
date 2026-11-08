; =============================================================================
; Utkarsha OS — lib/ubt/sm/crypto.asm — the Security Manager's functions
; =============================================================================
;   ubt_aes_expand(key, schedule) / ubt_aes_enc(schedule, in, out)
;   ubt_aes128(key, in, out)                 e()
;   ubt_cmac(key, msg, len, out)             AES-CMAC (RFC 4493)
;   ubt_ah(irk, r3, out3)                    random address hash
;   ubt_c1(k, r, preq, pres, addrs, out)     legacy confirm
;   ubt_s1(k, r1, r2, out)                   legacy STK
;   ubt_f4(u, v, x, z, out)                  Secure Connections confirm
;   ubt_f5(w, n1, n2, a1, a2, out32)         MacKey || LTK
;   ubt_f6(w, n1, n2, r, iocap, a1a2, out)   DHKey check
;   ubt_g2(u, v, x, y) → EAX                 numeric comparison value
;   ubt_h6(w, key_id, out), ubt_h7(salt, w, out)   key derivation
;   ubt_p256_public(priv, pub) / ubt_p256_dh(priv, peer, out) → EAX
;
; Values are as the Core specification writes them, most significant octet
; first (and so in the byte order AES itself uses); SMP turns the octets it
; gets least significant first around before and after. P-256 is usign's,
; keys and points big-endian, x || y.
; =============================================================================

%ifndef LIB_UBT_SM_CRYPTO_ASM
%define LIB_UBT_SM_CRYPTO_ASM

; usign writes [label] for its tables. Where it is first included here (the
; host tests' shared object) those must be RIP-relative, so it goes in under
; DEFAULT REL and NASM's own default is put back after. The kernel includes
; it long before (and sets DEFAULT REL for itself): nothing changes there.
%ifndef GUARD_CRYPTO_USIGN_ECDSA_ECDSA_P256_ASM
default rel
%include "lib/crypto/usign/ecdsa/ecdsa_p256.asm"
default abs
%endif

; one round key from the one before: XMM1 = it, %1 = round constant;
; the new one is stored at [RSI + %2]
%macro UBT_KEYEXP 2
    aeskeygenassist xmm2, xmm1, %1
    pshufd xmm2, xmm2, 0xFF
    movdqa xmm3, xmm1
    pslldq xmm3, 4
    pxor xmm1, xmm3
    pslldq xmm3, 4
    pxor xmm1, xmm3
    pslldq xmm3, 4
    pxor xmm1, xmm3
    pxor xmm1, xmm2
    movdqu [rsi + %2], xmm1
%endmacro

section .rodata
align 16
ubt_f5_salt:    db 0x6C, 0x88, 0x83, 0x91, 0xAA, 0xF5, 0xA5, 0x38
                db 0x60, 0x37, 0x0B, 0xDB, 0x5A, 0x60, 0x83, 0xBE

section .text

; -----------------------------------------------------------------------------
; ubt_aes_expand — RDI = 16-byte key, RSI = 176-byte schedule out
; ubt_aes_enc    — RDI = schedule, RSI = 16 bytes in, RDX = 16 bytes out
; ubt_aes128     — RDI = key, RSI = in, RDX = out (the specification's e())
; -----------------------------------------------------------------------------
global ubt_aes_expand
ubt_aes_expand:
    movdqu xmm1, [rdi]
    movdqu [rsi], xmm1
    UBT_KEYEXP 0x01, 16
    UBT_KEYEXP 0x02, 32
    UBT_KEYEXP 0x04, 48
    UBT_KEYEXP 0x08, 64
    UBT_KEYEXP 0x10, 80
    UBT_KEYEXP 0x20, 96
    UBT_KEYEXP 0x40, 112
    UBT_KEYEXP 0x80, 128
    UBT_KEYEXP 0x1B, 144
    UBT_KEYEXP 0x36, 160
    ret

global ubt_aes_enc
ubt_aes_enc:
    movdqu xmm0, [rsi]
    movdqu xmm1, [rdi]
    pxor xmm0, xmm1
%assign r 1
%rep 9
    movdqu xmm1, [rdi + r * 16]
    aesenc xmm0, xmm1
%assign r r + 1
%endrep
    movdqu xmm1, [rdi + 160]
    aesenclast xmm0, xmm1
    movdqu [rdx], xmm0
    ret

global ubt_aes128
ubt_aes128:
    push rsi
    push rdx
    sub rsp, 184
    mov rsi, rsp
    call ubt_aes_expand
    mov rdi, rsp
    mov rsi, [rsp + 192]
    mov rdx, [rsp + 184]
    call ubt_aes_enc
    pxor xmm0, xmm0                     ; no round keys left behind
%assign r 0
%rep 11
    movdqu [rsp + r * 16], xmm0
%assign r r + 1
%endrep
    add rsp, 200
    ret

; ubt_shl128 — RDI = 16 bytes, most significant first: shifted left one bit;
; 0x87 folded in when a bit falls off (the CMAC subkey step)
ubt_shl128:
    mov rax, [rdi]
    mov rdx, [rdi + 8]
    bswap rax
    bswap rdx
    xor ecx, ecx
    bt rax, 63
    setc cl
    shld rax, rdx, 1
    shl rdx, 1
    neg rcx
    and ecx, 0x87
    xor rdx, rcx
    bswap rax
    bswap rdx
    mov [rdi], rax
    mov [rdi + 8], rdx
    ret

; -----------------------------------------------------------------------------
; ubt_cmac — RDI = 16-byte key, RSI = message, EDX = its length, RCX = 16-byte
;            tag out
; -----------------------------------------------------------------------------
global ubt_cmac
ubt_cmac:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 240                        ; [rsp] schedule (176), [+176] subkey,
                                        ; [+192] X, [+208] last block
    mov r12, rsi
    mov r13d, edx
    mov r14, rcx
    mov rsi, rsp
    call ubt_aes_expand
    ; L = e(K, 0), K1 = L << 1, K2 = K1 << 1
    pxor xmm0, xmm0
    movdqu [rsp + 192], xmm0
    mov rdi, rsp
    lea rsi, [rsp + 192]
    lea rdx, [rsp + 176]
    call ubt_aes_enc
    lea rdi, [rsp + 176]
    call ubt_shl128
    ; blocks: all but the last straight through
    mov r15d, r13d
    add r15d, 15
    shr r15d, 4                         ; how many
    xor ebx, ebx                        ; 1: the last one is whole
    test r13d, r13d
    jz .empty
    test r13d, 15
    jnz .partial
    mov ebx, 1
    jmp .count
.empty:
    mov r15d, 1
.partial:
    lea rdi, [rsp + 176]
    call ubt_shl128                     ; K2
.count:
    pxor xmm0, xmm0
    movdqu [rsp + 192], xmm0
.block:
    cmp r15d, 1
    jbe .last
    movdqu xmm0, [rsp + 192]
    movdqu xmm1, [r12]
    pxor xmm0, xmm1
    movdqu [rsp + 192], xmm0
    mov rdi, rsp
    lea rsi, [rsp + 192]
    lea rdx, [rsp + 192]
    call ubt_aes_enc
    add r12, 16
    sub r13d, 16
    dec r15d
    jmp .block
.last:
    ; the last block, whole or padded with 0x80 then zeros
    pxor xmm0, xmm0
    movdqu [rsp + 208], xmm0
    lea rdi, [rsp + 208]
    mov rsi, r12
    mov ecx, r13d
    rep movsb
    test ebx, ebx
    jnz .mix
    mov byte [rsp + 208 + r13], 0x80
.mix:
    movdqu xmm0, [rsp + 208]
    movdqu xmm1, [rsp + 176]
    pxor xmm0, xmm1
    movdqu xmm1, [rsp + 192]
    pxor xmm0, xmm1
    movdqu [rsp + 208], xmm0
    mov rdi, rsp
    lea rsi, [rsp + 208]
    mov rdx, r14
    call ubt_aes_enc
    ; nothing of the key left on the stack
    pxor xmm0, xmm0
%assign r 0
%rep 15
    movdqu [rsp + r * 16], xmm0
%assign r r + 1
%endrep
    add rsp, 240
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ubt_cmac_parts — RDI = key, RSI = list of (pointer, length) pairs ending
; with a 0 pointer, RDX = tag out: CMAC of the parts one after another
; (96 bytes at most)
ubt_cmac_parts:
    push rbx
    push r12
    sub rsp, 120                        ; the message
    mov rbx, rdi
    mov r12, rdx
    mov rdi, rsp
.part:
    mov rax, [rsi]
    test rax, rax
    jz .whole
    mov ecx, [rsi + 8]
    push rsi
    mov rsi, rax
    rep movsb
    pop rsi
    add rsi, 16
    jmp .part
.whole:
    mov rdx, rdi
    sub rdx, rsp                        ; length
    mov rdi, rbx
    mov rsi, rsp
    mov rcx, r12
    call ubt_cmac
    add rsp, 120
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubt_f4 — RDI = U (32), RSI = V (32), RDX = X (16), ECX = Z, R8 = out (16)
;          AES-CMAC_X(U || V || Z)
; -----------------------------------------------------------------------------
global ubt_f4
ubt_f4:
    sub rsp, 72
    mov [rsp + 64], cl
    mov [rsp], rdi
    mov qword [rsp + 8], 32
    mov [rsp + 16], rsi
    mov qword [rsp + 24], 32
    lea rax, [rsp + 64]
    mov [rsp + 32], rax
    mov qword [rsp + 40], 1
    mov qword [rsp + 48], 0
    mov rdi, rdx
    mov rsi, rsp
    mov rdx, r8
    call ubt_cmac_parts
    add rsp, 72
    ret

; -----------------------------------------------------------------------------
; ubt_f5 — RDI = W (32), RSI = N1 (16), RDX = N2 (16), RCX = A1 (7: type,
;          address), R8 = A2 (7), R9 = out (32: MacKey, then LTK)
; -----------------------------------------------------------------------------
global ubt_f5
ubt_f5:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 160                        ; [rsp] parts, [+112] T, [+128] counter
                                        ; and key ID, [+136] length
    mov rbx, rsi
    mov r12, rdx
    mov r13, rcx
    mov r14, r8
    mov r15, r9
    ; T = AES-CMAC_SALT(W)
    mov rsi, rdi
    lea rdi, [rel ubt_f5_salt]
    mov edx, 32
    lea rcx, [rsp + 112]
    call ubt_cmac
    ; Counter || "btle" || N1 || N2 || A1 || A2 || 256, counter 0 then 1
    mov byte [rsp + 128], 0
    mov dword [rsp + 129], 0x656C7462           ; "btle" in memory order
    mov word [rsp + 136], 0x0001                ; 0x0100, most significant first
    lea rax, [rsp + 128]
    mov [rsp], rax
    mov qword [rsp + 8], 5
    mov [rsp + 16], rbx
    mov qword [rsp + 24], 16
    mov [rsp + 32], r12
    mov qword [rsp + 40], 16
    mov [rsp + 48], r13
    mov qword [rsp + 56], 7
    mov [rsp + 64], r14
    mov qword [rsp + 72], 7
    lea rax, [rsp + 136]
    mov [rsp + 80], rax
    mov qword [rsp + 88], 2
    mov qword [rsp + 96], 0
    lea rdi, [rsp + 112]
    mov rsi, rsp
    mov rdx, r15
    call ubt_cmac_parts
    mov byte [rsp + 128], 1
    lea rdi, [rsp + 112]
    mov rsi, rsp
    lea rdx, [r15 + 16]
    call ubt_cmac_parts
    pxor xmm0, xmm0
    movdqu [rsp + 112], xmm0
    add rsp, 160
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubt_f6 — RDI = W (16), RSI = N1, RDX = N2, RCX = R (16 each), R8 = IOcap
;          (3), R9 = A1 || A2 (14), [RSP + 8] = out (16)
;          AES-CMAC_W(N1 || N2 || R || IOcap || A1 || A2)
; -----------------------------------------------------------------------------
global ubt_f6
ubt_f6:
    mov rax, [rsp + 8]
    sub rsp, 120
    mov [rsp], rsi
    mov qword [rsp + 8], 16
    mov [rsp + 16], rdx
    mov qword [rsp + 24], 16
    mov [rsp + 32], rcx
    mov qword [rsp + 40], 16
    mov [rsp + 48], r8
    mov qword [rsp + 56], 3
    mov [rsp + 64], r9
    mov qword [rsp + 72], 14
    mov qword [rsp + 80], 0
    mov rsi, rsp
    mov rdx, rax
    call ubt_cmac_parts
    add rsp, 120
    ret

; -----------------------------------------------------------------------------
; ubt_g2 — RDI = U (32), RSI = V (32), RDX = X (16), RCX = Y (16)
; Output: EAX = AES-CMAC_X(U || V || Y) mod 2^32 (the six digits are EAX
;         mod 1 000 000)
; -----------------------------------------------------------------------------
global ubt_g2
ubt_g2:
    sub rsp, 88
    mov [rsp], rdi
    mov qword [rsp + 8], 32
    mov [rsp + 16], rsi
    mov qword [rsp + 24], 32
    mov [rsp + 32], rcx
    mov qword [rsp + 40], 16
    mov qword [rsp + 48], 0
    mov rdi, rdx
    mov rsi, rsp
    lea rdx, [rsp + 64]
    call ubt_cmac_parts
    mov eax, [rsp + 64 + 12]
    bswap eax
    add rsp, 88
    ret

; ubt_h6 — RDI = W (16), ESI = key ID (four characters as a number, e.g.
;          0x6C656272 for "lebr"), RDX = out: AES-CMAC_W(keyID)
global ubt_h6
ubt_h6:
    sub rsp, 24
    bswap esi
    mov [rsp], esi
    mov rcx, rdx
    mov rsi, rsp
    mov edx, 4
    call ubt_cmac
    add rsp, 24
    ret

; ubt_h7 — RDI = SALT (16), RSI = W (16), RDX = out: AES-CMAC_SALT(W)
global ubt_h7
ubt_h7:
    mov rcx, rdx
    mov edx, 16
    jmp ubt_cmac

; ubt_ah — RDI = IRK (16), RSI = r (3), RDX = out (3): e(k, 0 || r) mod 2^24
global ubt_ah
ubt_ah:
    push rdx
    sub rsp, 32
    pxor xmm0, xmm0
    movdqu [rsp], xmm0
    mov ax, [rsi]
    mov [rsp + 13], ax
    mov al, [rsi + 2]
    mov [rsp + 15], al
    mov rsi, rsp
    lea rdx, [rsp + 16]
    call ubt_aes128
    mov rdx, [rsp + 32]
    mov ax, [rsp + 16 + 13]
    mov [rdx], ax
    mov al, [rsp + 16 + 15]
    mov [rdx + 2], al
    add rsp, 40
    ret

; -----------------------------------------------------------------------------
; ubt_c1 — RDI = k, RSI = r (16 each), RDX = preq (7), RCX = pres (7),
;          R8 = iat, rat, ia (6), ra (6) (14 bytes), R9 = out (16)
;          e(k, e(k, r ^ p1) ^ p2), p1 = pres || preq || rat || iat,
;          p2 = 0 (4) || ia || ra
; -----------------------------------------------------------------------------
global ubt_c1
ubt_c1:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 232                        ; [rsp] schedule, [+176] p1, [+192] p2
    mov rbx, rsi
    mov r12, rdx
    mov r13, rcx
    mov r14, r8
    push r9
    sub rsp, 8
    lea rsi, [rsp + 16]
    call ubt_aes_expand
    add rsp, 8
    pop r9
    ; p1
    mov rsi, r13
    lea rdi, [rsp + 176]
    mov ecx, 7
    rep movsb
    mov rsi, r12
    mov ecx, 7
    rep movsb
    mov al, [r14 + 1]
    mov [rdi], al
    mov al, [r14]
    mov [rdi + 1], al
    ; p2
    mov dword [rsp + 192], 0
    lea rsi, [r14 + 2]
    lea rdi, [rsp + 196]
    mov ecx, 12
    rep movsb
    ; e(k, r ^ p1) ^ p2, then e(k, that)
    movdqu xmm0, [rbx]
    movdqu xmm1, [rsp + 176]
    pxor xmm0, xmm1
    movdqu [rsp + 176], xmm0
    push r9
    sub rsp, 8
    lea rdi, [rsp + 16]
    lea rsi, [rsp + 16 + 176]
    lea rdx, [rsp + 16 + 176]
    call ubt_aes_enc
    movdqu xmm0, [rsp + 16 + 176]
    movdqu xmm1, [rsp + 16 + 192]
    pxor xmm0, xmm1
    movdqu [rsp + 16 + 176], xmm0
    lea rdi, [rsp + 16]
    lea rsi, [rsp + 16 + 176]
    mov rdx, [rsp + 8]
    call ubt_aes_enc
    add rsp, 8
    pop r9
    pxor xmm0, xmm0
%assign r 0
%rep 13
    movdqu [rsp + r * 16], xmm0
%assign r r + 1
%endrep
    add rsp, 232
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ubt_s1 — RDI = k, RSI = r1, RDX = r2 (16 each), RCX = out:
; e(k, r1's low 64 bits || r2's low 64 bits)
global ubt_s1
ubt_s1:
    sub rsp, 24
    mov rax, [rsi + 8]
    mov [rsp], rax
    mov rax, [rdx + 8]
    mov [rsp + 8], rax
    mov rsi, rsp
    mov rdx, rcx
    call ubt_aes128
    add rsp, 24
    ret

; -----------------------------------------------------------------------------
; ubt_p256_public — RDI = private key (32), RSI = public key out (64)
; ubt_p256_dh     — RDI = private key, RSI = the peer's public key (64),
;                   RDX = the shared secret out (32, its x)
; Output: EAX = 0, or -1 (a key out of range, a point not on the curve)
; Big-endian, x || y.
; -----------------------------------------------------------------------------
global ubt_p256_public
ubt_p256_public:
    xchg rdi, rsi
    sub rsp, 8
    call ecdsa_p256_public_from_private
    add rsp, 8
    ret

global ubt_p256_dh
ubt_p256_dh:
    push rbx
    push r12
    push r13
    sub rsp, 304                        ; [rsp] peer point (96), [+96] result
                                        ; (96), [+192] scalar (32), [+224] x||y
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov rdi, rsp
    mov rsi, r12
    call p256_point_from_bytes
    test eax, eax
    jnz .out
    lea rdi, [rsp + 192]
    mov rsi, rbx
    call p256_from_be
    lea rdi, [rsp + 96]
    lea rsi, [rsp + 192]
    mov rdx, rsp
    call p256_scalarmult_ct
    lea rdi, [rsp + 224]
    lea rsi, [rsp + 96]
    call p256_point_to_bytes
    lea rsi, [rsp + 224]
    mov rdi, r13
    mov ecx, 32
    rep movsb
    xor eax, eax
.out:
    mov ebx, eax
    lea rdi, [rsp]
    xor eax, eax
    mov ecx, 304
    rep stosb
    mov eax, ebx
    add rsp, 304
    pop r13
    pop r12
    pop rbx
    ret

%endif ; LIB_UBT_SM_CRYPTO_ASM
