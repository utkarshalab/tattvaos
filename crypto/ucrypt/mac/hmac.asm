%ifndef GUARD_CRYPTO_UCRYPT_MAC_HMAC_ASM
%define GUARD_CRYPTO_UCRYPT_MAC_HMAC_ASM
; =============================================================================
; Tattva OS — crypto/ucrypt/mac/hmac.asm
; =============================================================================
; HMAC-SHA256 (RFC 2104 / FIPS 198-1).
;
; Implements:
;   - Keyed MAC over an arbitrary message (`hmac_sha256`)
;   - Streaming form for large inputs (`hmac_sha256_init/update/final`)
;   - Constant-time tag comparison (`hmac_sha256_verify`)
;
;   HMAC(K, m) = H( (K' ^ opad) || H( (K' ^ ipad) || m ) )
;
; The two-pass structure is not decoration. A naive H(key || message) is
; forgeable by length extension on any Merkle-Damgard hash, SHA-256 included:
; an attacker who knows H(key || m) can compute H(key || m || padding || suffix)
; without knowing the key at all. The outer hash closes that.
;
; Keys longer than the 64-byte block are hashed down first; shorter keys are
; zero-padded. Both are required by the spec, and skipping the long-key case
; means two different long keys can produce the same MAC.
;
; Verification is constant time. A byte-wise early-exit compare lets an attacker
; recover a valid tag one byte at a time by measuring rejection latency.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

[BITS 64]

%include "crypto/uhash/sha256/sha256.inc"

%define HMAC_BLOCK_SIZE     64
%define HMAC_DIGEST_SIZE    32
%define HMAC_IPAD           0x36
%define HMAC_OPAD           0x5C

; Streaming context: the inner hash state plus the derived outer key block.
struc hmac_ctx_t
    .inner:             resb sha256_ctx_t_size
    .okey:              resb HMAC_BLOCK_SIZE    ; K' ^ opad, kept for the final
endstruc

section .text

global hmac_sha256
global hmac_sha256_init
global hmac_sha256_update
global hmac_sha256_final
global hmac_sha256_verify

; -----------------------------------------------------------------------------
; hmac_sha256_init
;
; Derives the padded key blocks and starts the inner hash.
;
; Inputs:
;   RDI = Pointer to an hmac_ctx_t
;   RSI = Key pointer
;   RDX = Key length
;
; Returns:
;   RAX = 1
; -----------------------------------------------------------------------------
align 32
hmac_sha256_init:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, HMAC_BLOCK_SIZE + 16   ; Scratch for K'

    mov rbx, rdi                    ; Context
    mov r12, rsi                    ; Key
    mov r13, rdx                    ; Key length

    ; Zero the scratch: short keys are zero-padded to the block size.
    mov rdi, rsp
    mov rcx, HMAC_BLOCK_SIZE
    xor al, al
    rep stosb

    cmp r13, HMAC_BLOCK_SIZE
    ja .hi_long_key

    ; Short key: copy verbatim into the zeroed block.
    test r13, r13
    jz .hi_padded
    mov rdi, rsp
    mov rsi, r12
    mov rcx, r13
    rep movsb
    jmp .hi_padded

.hi_long_key:
    ; Long key: K' = H(K), which is then zero-padded like any short key.
    mov rdi, r12
    mov rsi, r13
    mov rdx, rsp
    call sha256_hash

.hi_padded:
    ; Build K' ^ opad into the context, and K' ^ ipad on the stack.
    xor rcx, rcx
.hi_xor:
    cmp rcx, HMAC_BLOCK_SIZE
    jae .hi_inner

    mov al, byte [rsp + rcx]
    mov dl, al
    xor al, HMAC_IPAD
    mov byte [rsp + rcx], al        ; K' ^ ipad, consumed immediately
    xor dl, HMAC_OPAD
    mov byte [rbx + hmac_ctx_t.okey + rcx], dl

    inc rcx
    jmp .hi_xor

.hi_inner:
    ; Inner hash starts with the ipad block.
    lea rdi, [rbx + hmac_ctx_t.inner]
    call sha256_init

    lea rdi, [rbx + hmac_ctx_t.inner]
    mov rsi, rsp
    mov rdx, HMAC_BLOCK_SIZE
    call sha256_update

    ; Do not leave K' ^ ipad on the stack for the next frame to inherit.
    mov rdi, rsp
    mov rcx, HMAC_BLOCK_SIZE
    xor al, al
    rep stosb

    mov rax, 1
    add rsp, HMAC_BLOCK_SIZE + 16
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; hmac_sha256_update
;
; Inputs:
;   RDI = Pointer to an hmac_ctx_t
;   RSI = Data pointer
;   RDX = Data length
;
; Returns:
;   RAX = 1
; -----------------------------------------------------------------------------
align 32
hmac_sha256_update:
    lea rdi, [rdi + hmac_ctx_t.inner]
    jmp sha256_update

; -----------------------------------------------------------------------------
; hmac_sha256_final
;
; Completes the inner hash and folds it through the outer one.
;
; Inputs:
;   RDI = Pointer to an hmac_ctx_t
;   RSI = Pointer to a 32-byte tag buffer
;
; Returns:
;   RAX = 1
; -----------------------------------------------------------------------------
align 32
hmac_sha256_final:
    push rbx
    push r12
    sub rsp, sha256_ctx_t_size + HMAC_DIGEST_SIZE + 16

    mov rbx, rdi                    ; Context
    mov r12, rsi                    ; Tag out

    ; Inner digest into scratch just past the outer context.
    lea rdi, [rbx + hmac_ctx_t.inner]
    lea rsi, [rsp + sha256_ctx_t_size]
    call sha256_final

    ; Outer: H(okey || inner_digest)
    mov rdi, rsp
    call sha256_init

    mov rdi, rsp
    lea rsi, [rbx + hmac_ctx_t.okey]
    mov rdx, HMAC_BLOCK_SIZE
    call sha256_update

    mov rdi, rsp
    lea rsi, [rsp + sha256_ctx_t_size]
    mov rdx, HMAC_DIGEST_SIZE
    call sha256_update

    mov rdi, rsp
    mov rsi, r12
    call sha256_final

    ; Wipe the outer key material and the inner digest.
    mov rdi, rbx
    mov rcx, hmac_ctx_t_size
    xor al, al
    rep stosb

    mov rax, 1
    add rsp, sha256_ctx_t_size + HMAC_DIGEST_SIZE + 16
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; hmac_sha256
;
; One-shot MAC.
;
; Inputs:
;   RDI = Key pointer
;   RSI = Key length
;   RDX = Message pointer
;   RCX = Message length
;   R8  = Pointer to a 32-byte tag buffer
;
; Returns:
;   RAX = 1
; -----------------------------------------------------------------------------
align 32
hmac_sha256:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, hmac_ctx_t_size + 16

    mov rbx, rdi                    ; Key
    mov r12, rsi                    ; Key length
    mov r13, rdx                    ; Message
    mov r14, rcx                    ; Message length
    mov r15, r8                     ; Tag out

    mov rdi, rsp
    mov rsi, rbx
    mov rdx, r12
    call hmac_sha256_init

    mov rdi, rsp
    mov rsi, r13
    mov rdx, r14
    call hmac_sha256_update

    mov rdi, rsp
    mov rsi, r15
    call hmac_sha256_final

    mov rax, 1
    add rsp, hmac_ctx_t_size + 16
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; hmac_sha256_verify
;
; Recomputes the MAC and compares in constant time.
;
; Inputs:
;   RDI = Key pointer
;   RSI = Key length
;   RDX = Message pointer
;   RCX = Message length
;   R8  = Pointer to the 32-byte expected tag
;
; Returns:
;   RAX = 1 when the tag matches, 0 otherwise
; -----------------------------------------------------------------------------
align 32
hmac_sha256_verify:
    push rbx
    push r12
    sub rsp, HMAC_DIGEST_SIZE + 16

    mov rbx, r8                     ; Expected tag

    mov r8, rsp                     ; Computed tag lands here
    call hmac_sha256

    ; Accumulate differences across all 32 bytes; never exit early.
    xor eax, eax
    xor rcx, rcx
.hv_cmp:
    cmp rcx, HMAC_DIGEST_SIZE
    jae .hv_done
    mov dl, byte [rsp + rcx]
    xor dl, byte [rbx + rcx]
    or al, dl
    inc rcx
    jmp .hv_cmp

.hv_done:
    ; AL is zero only if every byte matched.
    test al, al
    setz al
    movzx eax, al

    add rsp, HMAC_DIGEST_SIZE + 16
    pop r12
    pop rbx
    ret

%endif ; GUARD_CRYPTO_UCRYPT_MAC_HMAC_ASM
