%ifndef GUARD_CRYPTO_USIGN_ECDSA_RFC6979_ASM
%define GUARD_CRYPTO_USIGN_ECDSA_RFC6979_ASM
; =============================================================================
; Tattva OS — crypto/usign/ecdsa/rfc6979.asm
; =============================================================================
; Deterministic ECDSA nonces (RFC 6979) over HMAC-SHA256.
;
; Implements:
;   - Nonce derivation (`rfc6979_generate_k`)
;
; WHY THIS EXISTS. ECDSA needs a per-signature nonce k that is secret, uniformly
; distributed, and NEVER repeated. Two signatures under the same k give up the
; private key by elementary algebra:
;
;     s1 = k^-1 (e1 + r d),  s2 = k^-1 (e2 + r d)
;     =>  k = (e1 - e2) / (s1 - s2),  then  d = (s k - e) / r
;
; That is not a theoretical concern — it is the single most common way real
; deployments lose ECDSA private keys, and it has happened to shipped consoles,
; cryptocurrency wallets and TLS stacks. Even a slight BIAS is fatal given
; enough signatures: lattice attacks recover the key from a few hundred
; signatures whose nonces leak a handful of bits.
;
; RFC 6979 removes the RNG from the signing path entirely. k is derived from
; the private key and the message hash through an HMAC-DRBG, so it is
; reproducible, unbiased, and identical for identical inputs. Signing on a
; machine whose entropy pool has failed is then still safe, which is exactly
; the situation that breaks the randomized construction.
;
; The DRBG is instantiated fresh for every signature. Retaining state across
; calls would make k depend on how many signatures preceded it.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

[BITS 64]

section .text

global rfc6979_generate_k

; -----------------------------------------------------------------------------
; rfc6979_generate_k
;
; Inputs:
;   RDI = 32-byte output for k, little-endian limbs
;   RSI = Private key x, 4 little-endian limbs
;   RDX = 32-byte message hash h1, big-endian as SHA-256 emits it
;
; Returns:
;   EAX = 0 on success
;
;   V = 0x01 repeated 32 times
;   K = 0x00 repeated 32 times
;   K = HMAC(K, V || 0x00 || int2octets(x) || bits2octets(h1))
;   V = HMAC(K, V)
;   K = HMAC(K, V || 0x01 || int2octets(x) || bits2octets(h1))
;   V = HMAC(K, V)
;   loop: V = HMAC(K, V); k = bits2int(V)
;         accept when 1 <= k < n
;         otherwise K = HMAC(K, V || 0x00); V = HMAC(K, V); retry
;
; int2octets and bits2octets both emit 32 BIG-endian bytes. bits2octets also
; reduces the hash below n first — by one conditional subtraction, not a modulo,
; because the hash is already less than 2^256 and n is close to it.
; -----------------------------------------------------------------------------
align 32
rfc6979_generate_k:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 256

%define K6_V      0                 ; DRBG V, 32
%define K6_K      32                ; DRBG K, 32
%define K6_MSG    64                ; V || tag || x || h1, 97 bytes
%define K6_XOCT   176               ; int2octets(x), 32
%define K6_HOCT   208               ; bits2octets(h1), 32
%define K6_TMP    240

    mov rbx, rdi                    ; k output
    mov r12, rsi                    ; private key
    mov r13, rdx                    ; h1

    ; ---- int2octets(x): the scalar as 32 big-endian bytes ----
%assign i 0
%rep 4
    mov rax, [r12 + (3 - i)*8]
    bswap rax
    mov [rsp + K6_XOCT + i*8], rax
%assign i i+1
%endrep

    ; ---- bits2octets(h1) = int2octets(bits2int(h1) mod n) ----
    ; h1 arrives big-endian; convert, conditionally subtract n, convert back.
    lea rdi, [rsp + K6_TMP]
    mov rsi, r13
    call p256_from_be

    lea rdi, [rsp + K6_TMP]
    lea rsi, [p256_n]
    call bn256_cmp
    cmp eax, 0
    jl .h_reduced
    lea rdi, [rsp + K6_TMP]
    lea rsi, [rsp + K6_TMP]
    lea rdx, [p256_n]
    lea rcx, [p256_n]
    call bn256_submod
.h_reduced:
%assign i 0
%rep 4
    mov rax, [rsp + K6_TMP + (3 - i)*8]
    bswap rax
    mov [rsp + K6_HOCT + i*8], rax
%assign i i+1
%endrep

    ; ---- V = 0x01 * 32, K = 0x00 * 32 ----
    mov rax, 0x0101010101010101
%assign i 0
%rep 4
    mov [rsp + K6_V + i*8], rax
%assign i i+1
%endrep
    xor eax, eax
%assign i 0
%rep 4
    mov [rsp + K6_K + i*8], rax
%assign i i+1
%endrep

    ; ---- two priming rounds, tag 0x00 then 0x01 ----
    xor r14d, r14d                  ; tag
.prime:
    ; message = V || tag || xoct || hoct
    lea rdi, [rsp + K6_MSG]
    lea rsi, [rsp + K6_V]
    mov ecx, 32
    rep movsb
    mov al, r14b
    mov [rdi], al
    inc rdi
    lea rsi, [rsp + K6_XOCT]
    mov ecx, 32
    rep movsb
    lea rsi, [rsp + K6_HOCT]
    mov ecx, 32
    rep movsb

    lea rdi, [rsp + K6_K]
    mov rsi, 32
    lea rdx, [rsp + K6_MSG]
    mov rcx, 97
    lea r8, [rsp + K6_K]
    call hmac_sha256                ; K = HMAC(K, message)

    lea rdi, [rsp + K6_K]
    mov rsi, 32
    lea rdx, [rsp + K6_V]
    mov rcx, 32
    lea r8, [rsp + K6_V]
    call hmac_sha256                ; V = HMAC(K, V)

    inc r14d
    cmp r14d, 2
    jb .prime

    ; ---- candidate loop ----
    mov r15d, 0
.candidate:
    lea rdi, [rsp + K6_K]
    mov rsi, 32
    lea rdx, [rsp + K6_V]
    mov rcx, 32
    lea r8, [rsp + K6_V]
    call hmac_sha256                ; V = HMAC(K, V)

    ; k = bits2int(V). qlen is 256 and V is 32 bytes, so this is a plain
    ; big-endian read with no truncation.
    mov rdi, rbx
    lea rsi, [rsp + K6_V]
    call p256_from_be

    ; Accept when 1 <= k < n.
    mov rdi, rbx
    call bn256_is_zero
    test eax, eax
    jnz .retry
    mov rdi, rbx
    lea rsi, [p256_n]
    call bn256_cmp
    cmp eax, 0
    jl .done

.retry:
    ; K = HMAC(K, V || 0x00); V = HMAC(K, V)
    lea rdi, [rsp + K6_MSG]
    lea rsi, [rsp + K6_V]
    mov ecx, 32
    rep movsb
    mov byte [rdi], 0

    lea rdi, [rsp + K6_K]
    mov rsi, 32
    lea rdx, [rsp + K6_MSG]
    mov rcx, 33
    lea r8, [rsp + K6_K]
    call hmac_sha256

    lea rdi, [rsp + K6_K]
    mov rsi, 32
    lea rdx, [rsp + K6_V]
    mov rcx, 32
    lea r8, [rsp + K6_V]
    call hmac_sha256

    inc r15d
    cmp r15d, 64                    ; Bound the loop; it never runs twice in
    jb .candidate                   ; practice, but must not be unbounded

.done:
    ; The DRBG state and the copy of the private key are as sensitive as the
    ; key itself: anything that reproduces k reproduces the signature, and a
    ; leaked k gives up the key directly.
    lea rdi, [rsp]
    mov ecx, 256 / 8
    xor eax, eax
.wipe:
    mov [rdi], rax
    add rdi, 8
    dec ecx
    jnz .wipe

    xor eax, eax
    add rsp, 256
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

%endif ; GUARD_CRYPTO_USIGN_ECDSA_RFC6979_ASM
