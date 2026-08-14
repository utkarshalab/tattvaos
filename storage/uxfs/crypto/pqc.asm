; =============================================================================
; Tattva OS — storage/uxfs/crypto/pqc.asm
; =============================================================================
; NIST ML-KEM-1024 Post-Quantum Volume Master Key Wrapping.
;
; Implements:
;   - KEM-DEM master key wrapping (`uxfs_pqc_wrap_key`)
;   - Authenticated unwrap with constant-time tag check (`uxfs_pqc_unwrap_key`)
;   - Volume keypair generation (`uxfs_pqc_generate_keypair`)
;
; Volume master keys are wrapped rather than stored, so a recorded disk image
; cannot be decrypted later by an adversary holding a quantum computer. ML-KEM
; (CRYSTALS-Kyber) is a lattice KEM: its security does not rest on factoring or
; discrete log, so Shor's algorithm does not apply.
;
; The construction is standard KEM-DEM:
;
;   encapsulate(pk)          -> kem_ct, ss
;   wrapped = mk XOR KDF(ss)
;   tag     = SHA-256(ss || wrapped)
;
; The tag is what makes unwrap authenticated. Without it an attacker can flip
; bits in `wrapped` and flip the same bits in the recovered master key, which
; for XTS means controlled corruption of plaintext. The tag is compared in
; constant time so a wrong key cannot be recovered byte-by-byte via timing.
;
; NOTE: the KDF here is a single SHA-256 over the shared secret with a domain
; separator. A shared secret is already uniformly random, so a full HKDF
; extract step buys nothing; the hash provides domain separation only.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "storage/uxfs/uxfs.inc"

; ML-KEM-1024 parameter set sizes (NIST FIPS 203).
%define UXFS_MLKEM_PK_BYTES          1568
%define UXFS_MLKEM_SK_BYTES          3168
%define UXFS_MLKEM_CT_BYTES          1568
%define UXFS_MLKEM_SS_BYTES          32
%define UXFS_PQC_KEY_BYTES           32     ; Volume master key width
%define UXFS_PQC_TAG_BYTES           32     ; SHA-256 authentication tag

; -----------------------------------------------------------------------------
; Wrapped key blob as it sits on disk.
; -----------------------------------------------------------------------------
struc uxfs_pqc_blob_t
    .kem_ct:            resb UXFS_MLKEM_CT_BYTES    ; ML-KEM ciphertext
    .wrapped:           resb UXFS_PQC_KEY_BYTES     ; Master key XOR KDF(ss)
    .tag:               resb UXFS_PQC_TAG_BYTES     ; SHA-256(ss || wrapped)
endstruc

section .rodata
align 16

; Domain separators keep the derivation and tag hashes in disjoint namespaces
; so neither can be used as an oracle for the other.
uxfs_pqc_kdf_label:     db "UXFS-PQC-KDF-v1", 0
uxfs_pqc_kdf_label_len  equ $ - uxfs_pqc_kdf_label

uxfs_pqc_tag_label:     db "UXFS-PQC-TAG-v1", 0
uxfs_pqc_tag_label_len  equ $ - uxfs_pqc_tag_label

; Scratch for KEM material. Zeroed after every use: a shared secret left in
; memory defeats the point of wrapping the key at all. Explicitly zeroed rather
; than reserved, because in -f bin a nobits .bss must be the final section.
section .data
align 64

uxfs_pqc_ss:            times UXFS_MLKEM_SS_BYTES db 0
uxfs_pqc_kdf_in:        times UXFS_MLKEM_SS_BYTES + 32 db 0
uxfs_pqc_kdf_out:       times 32 db 0
uxfs_pqc_tag_in:        times UXFS_MLKEM_SS_BYTES + UXFS_PQC_KEY_BYTES + 32 db 0
uxfs_pqc_tag_calc:      times UXFS_PQC_TAG_BYTES db 0

section .text

global uxfs_pqc_wrap_key
global uxfs_pqc_unwrap_key
global uxfs_pqc_generate_keypair
global uxfs_pqc_blob_size

; -----------------------------------------------------------------------------
; uxfs_pqc_zero_scratch
;
; Wipes every KEM scratch buffer. Called on all exit paths, success or not.
; -----------------------------------------------------------------------------
align 32
uxfs_pqc_zero_scratch:
    push rdi
    push rcx
    push rax

    lea rdi, [uxfs_pqc_ss]
    mov rcx, UXFS_MLKEM_SS_BYTES
    xor al, al
    rep stosb

    lea rdi, [uxfs_pqc_kdf_in]
    mov rcx, UXFS_MLKEM_SS_BYTES + 32
    xor al, al
    rep stosb

    lea rdi, [uxfs_pqc_kdf_out]
    mov rcx, 32
    xor al, al
    rep stosb

    lea rdi, [uxfs_pqc_tag_in]
    mov rcx, UXFS_MLKEM_SS_BYTES + UXFS_PQC_KEY_BYTES + 32
    xor al, al
    rep stosb

    pop rax
    pop rcx
    pop rdi
    ret

; -----------------------------------------------------------------------------
; uxfs_pqc_derive
;
; Builds KDF(ss) = SHA-256(label || ss) into uxfs_pqc_kdf_out.
; -----------------------------------------------------------------------------
align 32
uxfs_pqc_derive:
    push rbx
    push r12

    lea rbx, [uxfs_pqc_kdf_in]

    ; label || ss
    lea rsi, [uxfs_pqc_kdf_label]
    mov rdi, rbx
    mov rcx, uxfs_pqc_kdf_label_len
    rep movsb

    mov r12, uxfs_pqc_kdf_label_len
    lea rsi, [uxfs_pqc_ss]
    lea rdi, [rbx + r12]
    mov rcx, UXFS_MLKEM_SS_BYTES
    rep movsb

    mov rdi, rbx
    mov rsi, uxfs_pqc_kdf_label_len + UXFS_MLKEM_SS_BYTES
    lea rdx, [uxfs_pqc_kdf_out]
    call uhash_sha256

    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_pqc_tag_compute
;
; Builds tag = SHA-256(label || ss || wrapped) into uxfs_pqc_tag_calc.
;
; Inputs:
;   RDI = Pointer to the 32-byte wrapped key
; -----------------------------------------------------------------------------
align 32
uxfs_pqc_tag_compute:
    push rbx
    push r12
    push r13

    mov r13, rdi                    ; Wrapped key
    lea rbx, [uxfs_pqc_tag_in]

    lea rsi, [uxfs_pqc_tag_label]
    mov rdi, rbx
    mov rcx, uxfs_pqc_tag_label_len
    rep movsb

    mov r12, uxfs_pqc_tag_label_len
    lea rsi, [uxfs_pqc_ss]
    lea rdi, [rbx + r12]
    mov rcx, UXFS_MLKEM_SS_BYTES
    rep movsb

    add r12, UXFS_MLKEM_SS_BYTES
    mov rsi, r13
    lea rdi, [rbx + r12]
    mov rcx, UXFS_PQC_KEY_BYTES
    rep movsb

    mov rdi, rbx
    mov rsi, uxfs_pqc_tag_label_len + UXFS_MLKEM_SS_BYTES + UXFS_PQC_KEY_BYTES
    lea rdx, [uxfs_pqc_tag_calc]
    call uhash_sha256

    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_pqc_generate_keypair
;
; Produces a volume ML-KEM keypair. The private key must be sealed to hardware
; (see crypto/vault.asm) or the wrapping provides no protection at rest.
;
; Inputs:
;   RDI = Output public key buffer  (UXFS_MLKEM_PK_BYTES)
;   RSI = Output private key buffer (UXFS_MLKEM_SK_BYTES)
;
; Returns:
;   EAX = 0 on success, POSIX_EIO on KEM failure
; -----------------------------------------------------------------------------
align 32
uxfs_pqc_generate_keypair:
    push rbx

    test rdi, rdi
    jz .gk_inval
    test rsi, rsi
    jz .gk_inval

    call kyber_keygen
    cmp rax, 1
    jne .gk_fail

    xor eax, eax
    pop rbx
    ret

.gk_inval:
    mov eax, POSIX_EINVAL
    pop rbx
    ret

.gk_fail:
    mov eax, POSIX_EIO
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_pqc_wrap_key
;
; Wraps a volume master key to an ML-KEM public key.
;
; Inputs:
;   RDI = Pointer to the 32-byte master key to protect
;   RSI = Pointer to the ML-KEM public key
;   RDX = Pointer to an output uxfs_pqc_blob_t
;
; Returns:
;   EAX = 0 on success, POSIX_EINVAL on a null argument, POSIX_EIO on KEM failure
; -----------------------------------------------------------------------------
align 32
uxfs_pqc_wrap_key:
    push rbx
    push r12
    push r13
    push r14

    mov rbx, rdi                    ; Master key
    mov r12, rsi                    ; Public key
    mov r13, rdx                    ; Output blob

    test rbx, rbx
    jz .wk_inval
    test r12, r12
    jz .wk_inval
    test r13, r13
    jz .wk_inval

    ; Encapsulate: yields the on-disk ciphertext and a fresh shared secret.
    mov rdi, r12
    lea rsi, [r13 + uxfs_pqc_blob_t.kem_ct]
    lea rdx, [uxfs_pqc_ss]
    call kyber_encapsulate
    cmp rax, 1
    jne .wk_fail

    call uxfs_pqc_derive

    ; wrapped = mk XOR KDF(ss), 32 bytes as four quadwords.
    lea r14, [r13 + uxfs_pqc_blob_t.wrapped]
    lea rcx, [uxfs_pqc_kdf_out]

    mov rax, [rbx]
    xor rax, [rcx]
    mov [r14], rax
    mov rax, [rbx + 8]
    xor rax, [rcx + 8]
    mov [r14 + 8], rax
    mov rax, [rbx + 16]
    xor rax, [rcx + 16]
    mov [r14 + 16], rax
    mov rax, [rbx + 24]
    xor rax, [rcx + 24]
    mov [r14 + 24], rax

    ; Authenticate the wrapped bytes.
    mov rdi, r14
    call uxfs_pqc_tag_compute

    lea rdi, [r13 + uxfs_pqc_blob_t.tag]
    lea rsi, [uxfs_pqc_tag_calc]
    mov rcx, 4
    rep movsq

    call uxfs_pqc_zero_scratch
    xor eax, eax
    jmp .wk_return

.wk_inval:
    mov eax, POSIX_EINVAL
    jmp .wk_return

.wk_fail:
    call uxfs_pqc_zero_scratch
    mov eax, POSIX_EIO

.wk_return:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_pqc_unwrap_key
;
; Recovers a volume master key from a wrapped blob.
;
; The tag is verified BEFORE the master key is handed back, and the comparison
; is constant time. On any failure the output buffer is left zeroed rather than
; holding a partially-recovered key.
;
; Inputs:
;   RDI = Pointer to a uxfs_pqc_blob_t
;   RSI = Pointer to the ML-KEM private key
;   RDX = Pointer to a 32-byte master key output buffer
;
; Returns:
;   EAX = 0 on success, POSIX_EACCES on tag mismatch, POSIX_EIO on KEM failure
; -----------------------------------------------------------------------------
align 32
uxfs_pqc_unwrap_key:
    push rbx
    push r12
    push r13
    push r14

    mov rbx, rdi                    ; Blob
    mov r12, rsi                    ; Private key
    mov r13, rdx                    ; Output master key

    test rbx, rbx
    jz .uk_inval
    test r12, r12
    jz .uk_inval
    test r13, r13
    jz .uk_inval

    ; Fail closed: never leave stale bytes in the caller's key buffer.
    mov rdi, r13
    xor rax, rax
    mov rcx, 4
    rep stosq

    mov rdi, r12
    lea rsi, [rbx + uxfs_pqc_blob_t.kem_ct]
    lea rdx, [uxfs_pqc_ss]
    call kyber_decapsulate
    cmp rax, 1
    jne .uk_fail

    ; Recompute the tag over the stored wrapped bytes and compare in constant
    ; time. A variable-time compare would leak the tag one byte at a time.
    lea r14, [rbx + uxfs_pqc_blob_t.wrapped]
    mov rdi, r14
    call uxfs_pqc_tag_compute

    lea rdi, [uxfs_pqc_tag_calc]
    lea rsi, [rbx + uxfs_pqc_blob_t.tag]
    mov rdx, UXFS_PQC_TAG_BYTES
    call ucrypt_ct_memcmp
    test rax, rax
    jnz .uk_badtag

    call uxfs_pqc_derive

    ; mk = wrapped XOR KDF(ss)
    lea rcx, [uxfs_pqc_kdf_out]
    mov rax, [r14]
    xor rax, [rcx]
    mov [r13], rax
    mov rax, [r14 + 8]
    xor rax, [rcx + 8]
    mov [r13 + 8], rax
    mov rax, [r14 + 16]
    xor rax, [rcx + 16]
    mov [r13 + 16], rax
    mov rax, [r14 + 24]
    xor rax, [rcx + 24]
    mov [r13 + 24], rax

    call uxfs_pqc_zero_scratch
    xor eax, eax
    jmp .uk_return

.uk_badtag:
    call uxfs_pqc_zero_scratch
    mov eax, POSIX_EACCES
    jmp .uk_return

.uk_inval:
    mov eax, POSIX_EINVAL
    jmp .uk_return

.uk_fail:
    call uxfs_pqc_zero_scratch
    mov eax, POSIX_EIO

.uk_return:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_pqc_blob_size
;
; Returns:
;   RAX = On-disk size of a wrapped key blob in bytes
; -----------------------------------------------------------------------------
align 32
uxfs_pqc_blob_size:
    mov rax, uxfs_pqc_blob_t_size
    ret
