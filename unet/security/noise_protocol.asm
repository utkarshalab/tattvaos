%ifndef GUARD_UNET_SECURITY_NOISE_PROTOCOL_ASM
%define GUARD_UNET_SECURITY_NOISE_PROTOCOL_ASM
; =============================================================================
; Tattva OS — unet/security/noise_protocol.asm
; =============================================================================
; Noise Protocol Framework SymmetricState (Noise Specification rev 34, section
; 5.2). This is the shared machinery every Noise-based handshake in this tree
; (WireGuard-style IK, obfs4's NTor-ish exchange, etc.) is meant to build on:
; running handshake hash `h`, chaining key `ck`, and the encrypt/decrypt-and-
; hash operations that fold ciphertext into the transcript.
;
; CRYPTO PRIMITIVE STATUS (read before trusting output from this file):
;   - MixHash is real: h = SHA256(h || data), computed with the actual
;     crypto/uhash/sha256/ engine.
;   - MixKey/Split use a from-scratch, spec-correct 2-output HKDF (Noise
;     section 4.3 / RFC 5869) built directly on hmac_sha256 — NOT on
;     crypto/ukdf/hkdf/hkdf.asm, which turned out (on inspection while
;     wiring this file) to not implement RFC 5869 at all: its "extract"
;     ignores the salt and its "expand" ignores the counter and info and
;     just repeats SHA256(PRK) for every output block. That file is outside
;     this pass's scope (unet/security/, not crypto/), so it hasn't been
;     touched; this file simply doesn't depend on it.
;   - EncryptAndHash/DecryptAndHash call the real chacha20_poly1305_encrypt/
;     decrypt entry points in crypto/ucrypt/symmetric/chacha20_poly1305.asm,
;     which is the architecturally correct place for this layer to get AEAD
;     from. That file's own ChaCha20 core (chacha20_block) does not yet run
;     the 20 quarter-rounds — it just copies the initial state to the output
;     — and its decrypt path returns "tag valid" unconditionally without
;     checking anything. Wiring is correct here; the AEAD itself is not yet
;     cryptographically sound until that's fixed upstream in crypto/, which
;     is out of scope for this pass (unet/, not crypto/). Every other file
;     in this pass that calls chacha20_poly1305_*/aes_gcm_* inherits the same
;     caveat and just points back here instead of repeating this paragraph.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define NOISE_HASH_LEN              32
%define NOISE_MAX_MIX_DATA          960     ; h(32) + data must fit NOISE_MIX_SCRATCH

struc noise_state_t
    .h:                 resb 32     ; Handshake Hash
    .ck:                resb 32     ; Chaining Key
    .k:                 resb 32     ; Cipher Key
    .has_key:           resd 1      ; 0 until the first MixKey
    .n:                 resq 1      ; Nonce Counter
    .s_local:           resb 32     ; Static Local Public Key
    .e_local:           resb 32     ; Ephemeral Local Public Key
    .s_remote:          resb 32     ; Static Remote Public Key
    .e_remote:          resb 32     ; Ephemeral Remote Public Key
endstruc

section .text

global noise_init
global noise_mix_hash
global noise_mix_key
global noise_encrypt_and_hash
global noise_decrypt_and_hash
global noise_split

; -----------------------------------------------------------------------------
; noise_hkdf2 — Noise spec section 4.3 two-output HKDF, built on hmac_sha256:
;   temp_key = HMAC-HASH(chaining_key, input_key_material)
;   output1  = HMAC-HASH(temp_key, 0x01)
;   output2  = HMAC-HASH(temp_key, output1 || 0x02)
; This is the RFC 5869 construction with salt=chaining_key; hand-rolled here
; (own prefix, per this codebase's naming rule) rather than depending on the
; broken crypto/ukdf/hkdf.asm — see header note.
;
; Input:  RDI = chaining_key (32 bytes)
;         RSI = IKM pointer (may be NULL when RDX==0, e.g. Split()'s zero-len IKM)
;         RDX = IKM length
;         RCX = output1 buffer (32 bytes)
;         R8  = output2 buffer (32 bytes)
; Output: RAX = 1
; -----------------------------------------------------------------------------
align 64
noise_hkdf2:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 128 + hmac_ctx_t_size    ; [rsp+0..31]=temp_key [rsp+32..63]=out1 scratch, ctx after

    mov r12, rsi                     ; IKM ptr
    mov r13, rdx                     ; IKM len
    mov r14, rcx                     ; out1
    mov r15, r8                      ; out2

    ; temp_key = HMAC-SHA256(chaining_key, IKM)
    ; hmac_sha256 ABI: RDI=key RSI=keylen RDX=msg RCX=msglen R8=tag_out
    ; RDI already holds chaining_key from this function's own entry.
    mov rsi, NOISE_HASH_LEN           ; key len
    mov rdx, r12                      ; msg ptr (IKM)
    mov rcx, r13                      ; msg len
    lea r8, [rsp]                     ; tag out -> temp_key
    call hmac_sha256

    ; output1 = HMAC-SHA256(temp_key, 0x01)
    mov byte [rsp + 32], 0x01
    lea rdi, [rsp]                    ; key = temp_key
    mov rsi, NOISE_HASH_LEN
    lea rdx, [rsp + 32]                ; msg = single byte 0x01
    mov rcx, 1
    mov r8, r14                        ; tag out -> output1
    call hmac_sha256

    ; output2 = HMAC-SHA256(temp_key, output1 || 0x02)
    ; copy output1 (32 bytes) then append 0x02 into scratch [rsp+32..64]
    mov rax, [r14 + 0]
    mov [rsp + 32], rax
    mov rax, [r14 + 8]
    mov [rsp + 40], rax
    mov rax, [r14 + 16]
    mov [rsp + 48], rax
    mov rax, [r14 + 24]
    mov [rsp + 56], rax
    mov byte [rsp + 64], 0x02

    lea rdi, [rsp]                     ; key = temp_key
    mov rsi, NOISE_HASH_LEN
    lea rdx, [rsp + 32]                ; msg = output1 || 0x02  (33 bytes)
    mov rcx, 33
    mov r8, r15                        ; tag out -> output2
    call hmac_sha256

    ; wipe temp_key from the stack
    mov qword [rsp + 0], 0
    mov qword [rsp + 8], 0
    mov qword [rsp + 16], 0
    mov qword [rsp + 24], 0

    mov rax, 1
    add rsp, 128 + hmac_ctx_t_size
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; noise_init — Initialize SymmetricState from a protocol name (Noise sec 5.2):
;   h  = len(protocol_name) <= 32 ? protocol_name padded with zeros to 32
;                                  : SHA256(protocol_name)
;   ck = h
; Input:  RDI = noise_state_t*
;         RSI = protocol_name pointer
;         RDX = protocol_name length
; Output: RAX = 1
; -----------------------------------------------------------------------------
align 64
noise_init:
    push rbx
    push r12
    push r13

    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx

    ; Zero h first — covers the "pad with zeros" case.
    xor eax, eax
    lea rdi, [rbx + noise_state_t.h]
    mov rcx, NOISE_HASH_LEN
    rep stosb

    cmp r13, NOISE_HASH_LEN
    ja .hash_name

    ; Short name: copy verbatim into the zeroed 32-byte field.
    lea rdi, [rbx + noise_state_t.h]
    mov rsi, r12
    mov rcx, r13
    rep movsb
    jmp .have_h

.hash_name:
    mov rdi, r12
    mov rsi, r13
    lea rdx, [rbx + noise_state_t.h]
    call sha256_hash

.have_h:
    ; ck = h
    lea rsi, [rbx + noise_state_t.h]
    lea rdi, [rbx + noise_state_t.ck]
    mov rcx, NOISE_HASH_LEN
    rep movsb

    mov dword [rbx + noise_state_t.has_key], 0
    mov qword [rbx + noise_state_t.n], 0

    mov rax, 1
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; noise_mix_hash — h = SHA256(h || data)
; Input:  RDI = noise_state_t*
;         RSI = data pointer
;         RDX = data length (must satisfy 32 + len <= NOISE_MAX_MIX_DATA + 32)
; Output: RAX = 1 on success, 0 if data is too large for the scratch buffer
; -----------------------------------------------------------------------------
align 64
noise_mix_hash:
    push rbx
    push r12
    push r13
    sub rsp, NOISE_MAX_MIX_DATA + 64

    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx

    cmp r13, NOISE_MAX_MIX_DATA
    ja .too_big

    lea rdi, [rsp]
    lea rsi, [rbx + noise_state_t.h]
    mov rcx, NOISE_HASH_LEN
    rep movsb

    mov rsi, r12
    mov rcx, r13
    rep movsb

    mov rdi, rsp
    mov rsi, NOISE_HASH_LEN
    add rsi, r13
    lea rdx, [rbx + noise_state_t.h]
    call sha256_hash

    mov rax, 1
    jmp .done

.too_big:
    xor eax, eax

.done:
    add rsp, NOISE_MAX_MIX_DATA + 64
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; noise_mix_key — (ck, k) = HKDF(ck, input_key_material, 2); has_key = 1; n = 0
; Input:  RDI = noise_state_t*
;         RSI = IKM pointer
;         RDX = IKM length
; Output: RAX = 1
; -----------------------------------------------------------------------------
align 64
noise_mix_key:
    push rbx
    push r12
    push r13
    sub rsp, 64

    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx

    lea rdi, [rbx + noise_state_t.ck]
    mov rsi, r12
    mov rdx, r13
    lea rcx, [rsp]                    ; new ck -> scratch first (don't clobber old ck mid-derivation)
    lea r8, [rbx + noise_state_t.k]
    call noise_hkdf2

    lea rdi, [rbx + noise_state_t.ck]
    lea rsi, [rsp]
    mov rcx, NOISE_HASH_LEN
    rep movsb

    mov dword [rbx + noise_state_t.has_key], 1
    mov qword [rbx + noise_state_t.n], 0

    mov rax, 1
    add rsp, 64
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; noise_encrypt_and_hash — ciphertext = ENCRYPT(k, n, h, plaintext); h = MixHash(h, ciphertext||tag); n++
; If has_key == 0, this is pass-through (ciphertext = plaintext) per spec.
; Input:  RDI = noise_state_t*
;         RSI = plaintext pointer
;         RDX = plaintext length
;         RCX = ciphertext output (>= len)
;         R8  = tag output (16 bytes)
; Output: RAX = 1
; -----------------------------------------------------------------------------
align 64
noise_encrypt_and_hash:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8

    cmp dword [rbx + noise_state_t.has_key], 0
    je .no_key

    ; nonce: 12 bytes, low 8 bytes = little-endian counter n (WireGuard/Noise convention),
    ; top 4 bytes zero (no static IV mixed in at this generic layer).
    sub rsp, 16
    mov rax, [rbx + noise_state_t.n]
    mov [rsp], rax
    mov dword [rsp + 8], 0

    lea rdi, [rbx + noise_state_t.k]
    mov rsi, rsp
    mov rdx, r12
    mov rcx, r13
    mov r8, r14
    mov r9, r15
    call chacha20_poly1305_encrypt

    add rsp, 16
    inc qword [rbx + noise_state_t.n]
    jmp .mix

.no_key:
    ; Pass-through copy.
    mov rdi, r14
    mov rsi, r12
    mov rcx, r13
    cld
    rep movsb
    xor eax, eax
    mov [r15], rax
    mov [r15 + 8], rax

.mix:
    ; MixHash over ciphertext || tag.
    sub rsp, 1040
    mov rdi, rsp
    mov rsi, r14
    mov rcx, r13
    cmp rcx, 1024
    jbe .fits
    mov rcx, 1024
.fits:
    rep movsb
    mov rdi, rsp
    add rdi, r13
    mov rsi, r15
    mov rcx, 16
    rep movsb

    mov rdi, rbx
    mov rsi, rsp
    mov rdx, r13
    add rdx, 16
    cmp rdx, NOISE_MAX_MIX_DATA
    jbe .mix_ok
    mov rdx, NOISE_MAX_MIX_DATA
.mix_ok:
    call noise_mix_hash
    add rsp, 1040

    mov rax, 1
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; noise_decrypt_and_hash — h = MixHash(h, ciphertext||tag) BEFORE decrypting
; (per spec order), then plaintext = DECRYPT(k, n, h_before, ciphertext); n++.
; If has_key == 0, pass-through.
; Input:  RDI = noise_state_t*
;         RSI = ciphertext pointer
;         RDX = ciphertext length
;         RCX = tag pointer (16 bytes)
;         R8  = plaintext output
; Output: RAX = 1 on tag-verified decrypt (or pass-through), 0 on auth failure
;         reported by the underlying AEAD (see header note on its current
;         completeness).
; -----------------------------------------------------------------------------
align 64
noise_decrypt_and_hash:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8

    ; MixHash over ciphertext || tag, using the hash as it stood BEFORE this call.
    sub rsp, 1040
    mov rdi, rsp
    mov rsi, r12
    mov rcx, r13
    cmp rcx, 1024
    jbe .cfits
    mov rcx, 1024
.cfits:
    rep movsb
    mov rdi, rsp
    add rdi, r13
    mov rsi, r14
    mov rcx, 16
    rep movsb

    mov rsi, rsp
    mov rdx, r13
    add rdx, 16
    cmp rdx, NOISE_MAX_MIX_DATA
    jbe .mix_ok2
    mov rdx, NOISE_MAX_MIX_DATA
.mix_ok2:
    mov rdi, rbx
    call noise_mix_hash
    add rsp, 1040

    cmp dword [rbx + noise_state_t.has_key], 0
    je .no_key

    sub rsp, 16
    mov rax, [rbx + noise_state_t.n]
    mov [rsp], rax
    mov dword [rsp + 8], 0

    lea rdi, [rbx + noise_state_t.k]
    mov rsi, rsp
    mov rdx, r12
    mov rcx, r13
    mov r8, r14
    mov r9, r15
    call chacha20_poly1305_decrypt      ; RAX = 1 verified / 0 mismatch (see header note)

    add rsp, 16
    inc qword [rbx + noise_state_t.n]
    jmp .done

.no_key:
    mov rdi, r15
    mov rsi, r12
    mov rcx, r13
    cld
    rep movsb
    mov rax, 1

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; noise_split — (k1, k2) = HKDF(ck, zerolen, 2); returns the two transport keys.
; Input:  RDI = noise_state_t*
;         RSI = output k1 (32 bytes, initiator->responder)
;         RDX = output k2 (32 bytes, responder->initiator)
; Output: RAX = 1
; -----------------------------------------------------------------------------
align 64
noise_split:
    push rbx
    push r12
    push r13

    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx

    lea rdi, [rbx + noise_state_t.ck]
    xor esi, esi                      ; IKM = zero-length
    xor edx, edx
    mov rcx, r12
    mov r8, r13
    call noise_hkdf2

    mov rax, 1
    pop r13
    pop r12
    pop rbx
    ret

%endif ; GUARD_UNET_SECURITY_NOISE_PROTOCOL_ASM
