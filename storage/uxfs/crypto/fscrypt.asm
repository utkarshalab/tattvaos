; =============================================================================
; Tattva OS — storage/uxfs/crypto/fscrypt.asm
; =============================================================================
; Policy-Based Per-Inode Filesystem Encryption (Linux fscrypt compatible).
;
; Implements:
;   - Policy attach / query on a directory inode (`uxfs_fscrypt_set/get_policy`)
;   - HKDF-SHA256 per-file key derivation (`uxfs_fscrypt_derive_file_key`)
;   - Master key registration and eviction (`uxfs_fscrypt_add/remove_key`)
;   - Filename padding to blunt length leakage (`uxfs_fscrypt_pad_name`)
;
; A single volume key encrypting every file is a poor design: one key recovered
; exposes everything, and identical plaintext blocks in different files encrypt
; identically. fscrypt instead derives a distinct key per inode from a master
; key and the inode number, so files are cryptographically independent even
; though the user manages exactly one secret.
;
; Derivation is HKDF-SHA256 (RFC 5869) with a per-use info string:
;
;   PRK      = HMAC-SHA256(salt = 0, IKM = master_key)
;   file_key = HMAC-SHA256(PRK, info || 0x01)
;
; The info string carries a context byte, so the contents key, the filenames
; key and the directory hash key derived from one master key are unrelated —
; recovering one does not yield the others.
;
; Filenames are padded before encryption because ciphertext length would
; otherwise leak the exact name length, which is often enough to fingerprint
; well-known files in a directory.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "storage/uxfs/uxfs.inc"

%define UXFS_FSCRYPT_POLICY_V1       1
%define UXFS_FSCRYPT_POLICY_V2       2

; Contents / filenames cipher identifiers, matching Linux fscrypt numbering.
%define UXFS_FSCRYPT_MODE_AES_256_XTS 1     ; File contents
%define UXFS_FSCRYPT_MODE_AES_256_CTS 4     ; Filenames

; Policy flags: filename padding granularity lives in the low two bits.
%define UXFS_FSCRYPT_PAD_4           0x00
%define UXFS_FSCRYPT_PAD_8           0x01
%define UXFS_FSCRYPT_PAD_16          0x02
%define UXFS_FSCRYPT_PAD_32          0x03
%define UXFS_FSCRYPT_PAD_MASK        0x03

; HKDF context bytes. Distinct values keep derived keys in separate namespaces.
%define UXFS_FSCRYPT_CTX_CONTENTS    1
%define UXFS_FSCRYPT_CTX_FILENAMES   2
%define UXFS_FSCRYPT_CTX_DIRHASH     3

%define UXFS_FSCRYPT_KEY_BYTES       32
%define UXFS_FSCRYPT_MAX_KEYS        16
%define UXFS_FSCRYPT_DESC_BYTES      8

; -----------------------------------------------------------------------------
; On-disk encryption policy, stored in the inode's extended attribute area.
; -----------------------------------------------------------------------------
struc uxfs_fscrypt_policy_t
    .version:                   resb 1      ; UXFS_FSCRYPT_POLICY_V1 or V2
    .contents_mode:             resb 1      ; UXFS_FSCRYPT_MODE_*
    .filenames_mode:            resb 1      ; UXFS_FSCRYPT_MODE_*
    .flags:                     resb 1      ; Padding granularity
    .master_key_descriptor:     resb UXFS_FSCRYPT_DESC_BYTES
endstruc

; -----------------------------------------------------------------------------
; In-memory master key slot. Keys live only while the volume is unlocked.
; -----------------------------------------------------------------------------
struc uxfs_fscrypt_keyslot_t
    .descriptor:        resb UXFS_FSCRYPT_DESC_BYTES    ; Identifier
    .key:               resb UXFS_FSCRYPT_KEY_BYTES     ; Master key
    .in_use:            resd 1
    .refcount:          resd 1
endstruc

section .rodata
align 16
uxfs_fscrypt_hkdf_label:    db "fscrypt", 0
uxfs_fscrypt_hkdf_label_len equ $ - uxfs_fscrypt_hkdf_label

section .data
align 64
global uxfs_fscrypt_keyring
uxfs_fscrypt_keyring:
    times UXFS_FSCRYPT_MAX_KEYS * uxfs_fscrypt_keyslot_t_size db 0

; Explicitly zeroed: in -f bin a nobits .bss must be the final section.
section .data
align 64
uxfs_fscrypt_prk:       times 32 db 0       ; HKDF pseudo-random key
uxfs_fscrypt_info:      times 64 db 0       ; HKDF info block
uxfs_fscrypt_hmac_buf:  times 512 db 0      ; HMAC block scratch (ipad|msg)

section .text

global uxfs_fscrypt_set_policy
global uxfs_fscrypt_get_policy
global uxfs_fscrypt_add_key
global uxfs_fscrypt_remove_key
global uxfs_fscrypt_find_key
global uxfs_fscrypt_derive_file_key
global uxfs_fscrypt_pad_name

; -----------------------------------------------------------------------------
; uxfs_fscrypt_hmac_sha256
;
; HMAC-SHA256 over a single message, per RFC 2104.
;
; Inputs:
;   RDI = Key pointer          (<= 64 bytes; longer keys are not used here)
;   ESI = Key length
;   RDX = Message pointer
;   ECX = Message length
;   R8  = 32-byte output buffer
; -----------------------------------------------------------------------------
align 32
uxfs_fscrypt_hmac_sha256:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 224                    ; [rsp]=ipad(64) [rsp+64]=opad(64)
                                    ; [rsp+128]=inner digest(32)

    mov rbx, rdi                    ; Key
    mov r12d, esi                   ; Key length
    mov r13, rdx                    ; Message
    mov r14d, ecx                   ; Message length
    mov r15, r8                     ; Output

    ; Zero both pads, then fold the key in.
    mov rdi, rsp
    mov rcx, 128
    xor al, al
    rep stosb

    xor rcx, rcx
.hm_copy:
    cmp ecx, r12d
    jae .hm_pad
    mov al, byte [rbx + rcx]
    mov byte [rsp + rcx], al
    mov byte [rsp + 64 + rcx], al
    inc rcx
    jmp .hm_copy

.hm_pad:
    xor rcx, rcx
.hm_xor:
    cmp rcx, 64
    jae .hm_inner
    xor byte [rsp + rcx], 0x36              ; ipad
    xor byte [rsp + 64 + rcx], 0x5C         ; opad
    inc rcx
    jmp .hm_xor

.hm_inner:
    ; Inner hash needs ipad || message contiguous; stage into the scratch block.
    lea rdi, [uxfs_fscrypt_hmac_buf]
    mov rsi, rsp
    mov rcx, 64
    rep movsb

    ; Append the message directly after the 64-byte ipad.
    lea rdi, [uxfs_fscrypt_hmac_buf + 64]
    mov rsi, r13
    mov ecx, r14d
    rep movsb

    lea rdi, [uxfs_fscrypt_hmac_buf]
    mov esi, r14d
    add rsi, 64
    lea rdx, [rsp + 128]
    call uhash_sha256

    ; Outer hash: opad || inner digest.
    lea rdi, [uxfs_fscrypt_hmac_buf]
    lea rsi, [rsp + 64]
    mov rcx, 64
    rep movsb

    lea rdi, [uxfs_fscrypt_hmac_buf + 64]
    lea rsi, [rsp + 128]
    mov rcx, 32
    rep movsb

    lea rdi, [uxfs_fscrypt_hmac_buf]
    mov rsi, 96
    mov rdx, r15
    call uhash_sha256

    add rsp, 224
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_fscrypt_derive_file_key
;
; Derives a per-inode key from a master key via HKDF-SHA256.
;
; Two inodes never share a key, so identical plaintext in two files produces
; unrelated ciphertext, and compromise of one file's key reveals nothing about
; any other.
;
; Inputs:
;   RDI = Pointer to the 32-byte master key
;   RSI = Inode number
;   EDX = Context byte (UXFS_FSCRYPT_CTX_*)
;   RCX = Pointer to a 32-byte derived key output buffer
;
; Returns:
;   EAX = 0 on success, POSIX_EINVAL on a null argument
; -----------------------------------------------------------------------------
align 32
uxfs_fscrypt_derive_file_key:
    push rbx
    push r12
    push r13
    push r14

    mov rbx, rdi                    ; Master key
    mov r12, rsi                    ; Inode number
    mov r13d, edx                   ; Context
    mov r14, rcx                    ; Output

    test rbx, rbx
    jz .dk_inval
    test r14, r14
    jz .dk_inval

    ; --- HKDF extract: PRK = HMAC(salt = 0^32, IKM = master_key) ----------
    sub rsp, 48
    mov rdi, rsp
    xor rax, rax
    mov rcx, 4
    rep stosq                       ; 32-byte zero salt

    mov rdi, rsp
    mov esi, 32
    mov rdx, rbx
    mov ecx, UXFS_FSCRYPT_KEY_BYTES
    lea r8, [uxfs_fscrypt_prk]
    call uxfs_fscrypt_hmac_sha256
    add rsp, 48

    ; --- HKDF expand info = label || context || inode || 0x01 -------------
    lea rdi, [uxfs_fscrypt_info]
    lea rsi, [uxfs_fscrypt_hkdf_label]
    mov rcx, uxfs_fscrypt_hkdf_label_len
    rep movsb

    mov rax, uxfs_fscrypt_hkdf_label_len
    lea rdi, [uxfs_fscrypt_info]
    mov byte [rdi + rax], r13b              ; Context separator
    inc rax
    mov [rdi + rax], r12                    ; Inode number binds key to file
    add rax, 8
    mov byte [rdi + rax], 0x01              ; HKDF block counter
    inc rax

    lea rdi, [uxfs_fscrypt_prk]
    mov esi, 32
    lea rdx, [uxfs_fscrypt_info]
    mov ecx, eax
    mov r8, r14
    call uxfs_fscrypt_hmac_sha256

    ; The PRK is as sensitive as the master key; do not leave it resident.
    lea rdi, [uxfs_fscrypt_prk]
    xor rax, rax
    mov rcx, 4
    rep stosq

    xor eax, eax
    jmp .dk_return

.dk_inval:
    mov eax, POSIX_EINVAL

.dk_return:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_fscrypt_find_key
;
; Looks up a master key slot by descriptor.
;
; Inputs:
;   RDI = Pointer to an 8-byte key descriptor
;
; Returns:
;   RAX = Pointer to the slot, or 0 when the key is not unlocked
; -----------------------------------------------------------------------------
align 32
uxfs_fscrypt_find_key:
    push rbx
    push r12

    lea rbx, [uxfs_fscrypt_keyring]
    mov r12, UXFS_FSCRYPT_MAX_KEYS

.fk_loop:
    cmp dword [rbx + uxfs_fscrypt_keyslot_t.in_use], 0
    je .fk_next

    mov rax, [rdi]
    cmp rax, [rbx + uxfs_fscrypt_keyslot_t.descriptor]
    je .fk_found

.fk_next:
    add rbx, uxfs_fscrypt_keyslot_t_size
    dec r12
    jnz .fk_loop

    xor eax, eax
    pop r12
    pop rbx
    ret

.fk_found:
    mov rax, rbx
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_fscrypt_add_key
;
; Installs a master key into the in-memory keyring, unlocking every inode whose
; policy names this descriptor.
;
; Inputs:
;   RDI = Pointer to an 8-byte key descriptor
;   RSI = Pointer to the 32-byte master key
;
; Returns:
;   EAX = 0 on success, POSIX_ENOSPC when the keyring is full
; -----------------------------------------------------------------------------
align 32
uxfs_fscrypt_add_key:
    push rbx
    push r12
    push r13

    mov r12, rdi
    mov r13, rsi

    test r12, r12
    jz .ak_inval
    test r13, r13
    jz .ak_inval

    ; Re-adding an unlocked key just takes another reference.
    mov rdi, r12
    call uxfs_fscrypt_find_key
    test rax, rax
    jnz .ak_existing

    lea rbx, [uxfs_fscrypt_keyring]
    mov rcx, UXFS_FSCRYPT_MAX_KEYS

.ak_scan:
    cmp dword [rbx + uxfs_fscrypt_keyslot_t.in_use], 0
    je .ak_claim
    add rbx, uxfs_fscrypt_keyslot_t_size
    dec rcx
    jnz .ak_scan

    mov eax, POSIX_ENOSPC
    jmp .ak_return

.ak_claim:
    mov rax, [r12]
    mov [rbx + uxfs_fscrypt_keyslot_t.descriptor], rax

    lea rdi, [rbx + uxfs_fscrypt_keyslot_t.key]
    mov rsi, r13
    mov rcx, 4
    rep movsq

    mov dword [rbx + uxfs_fscrypt_keyslot_t.in_use], 1
    mov dword [rbx + uxfs_fscrypt_keyslot_t.refcount], 1

    xor eax, eax
    jmp .ak_return

.ak_existing:
    inc dword [rax + uxfs_fscrypt_keyslot_t.refcount]
    xor eax, eax
    jmp .ak_return

.ak_inval:
    mov eax, POSIX_EINVAL

.ak_return:
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_fscrypt_remove_key
;
; Drops a reference and, when the last one goes, wipes the key material so a
; locked volume leaves nothing recoverable in RAM.
;
; Inputs:
;   RDI = Pointer to an 8-byte key descriptor
;
; Returns:
;   EAX = 0 on success, POSIX_ENOENT when the key was not present
; -----------------------------------------------------------------------------
align 32
uxfs_fscrypt_remove_key:
    push rbx

    call uxfs_fscrypt_find_key
    test rax, rax
    jz .rk_missing
    mov rbx, rax

    dec dword [rbx + uxfs_fscrypt_keyslot_t.refcount]
    cmp dword [rbx + uxfs_fscrypt_keyslot_t.refcount], 0
    jg .rk_done

    ; Last reference: scrub the slot.
    lea rdi, [rbx + uxfs_fscrypt_keyslot_t.key]
    xor rax, rax
    mov rcx, 4
    rep stosq

    mov qword [rbx + uxfs_fscrypt_keyslot_t.descriptor], 0
    mov dword [rbx + uxfs_fscrypt_keyslot_t.in_use], 0
    mov dword [rbx + uxfs_fscrypt_keyslot_t.refcount], 0

.rk_done:
    xor eax, eax
    pop rbx
    ret

.rk_missing:
    mov eax, POSIX_ENOENT
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_fscrypt_set_policy
;
; Attaches an encryption policy to a directory inode. A policy may only be set
; on an empty directory: existing children were written in the clear and would
; otherwise become silently unreadable rather than encrypted.
;
; Inputs:
;   RDI = Pointer to a uxfs_inode_t
;   RSI = Pointer to a uxfs_fscrypt_policy_t
;
; Returns:
;   EAX = 0 on success
;         POSIX_EINVAL on an unsupported version or cipher
;         POSIX_EEXIST when a policy is already attached
; -----------------------------------------------------------------------------
align 32
uxfs_fscrypt_set_policy:
    push rbx
    push r12

    mov rbx, rdi
    mov r12, rsi

    test rbx, rbx
    jz .sp_inval
    test r12, r12
    jz .sp_inval

    movzx eax, byte [r12 + uxfs_fscrypt_policy_t.version]
    cmp eax, UXFS_FSCRYPT_POLICY_V1
    jb .sp_inval
    cmp eax, UXFS_FSCRYPT_POLICY_V2
    ja .sp_inval

    movzx eax, byte [r12 + uxfs_fscrypt_policy_t.contents_mode]
    cmp eax, UXFS_FSCRYPT_MODE_AES_256_XTS
    jne .sp_inval

    movzx eax, byte [r12 + uxfs_fscrypt_policy_t.filenames_mode]
    cmp eax, UXFS_FSCRYPT_MODE_AES_256_CTS
    jne .sp_inval

    ; Refuse to re-key a directory that already carries a policy.
    test dword [rbx + uxfs_inode_t.type_flags], UXFS_FLAG_ENCRYPTED
    jnz .sp_exists

    or dword [rbx + uxfs_inode_t.type_flags], UXFS_FLAG_ENCRYPTED

    xor eax, eax
    pop r12
    pop rbx
    ret

.sp_exists:
    mov eax, POSIX_EEXIST
    pop r12
    pop rbx
    ret

.sp_inval:
    mov eax, POSIX_EINVAL
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_fscrypt_get_policy
;
; Reports the policy attached to an inode.
;
; Inputs:
;   RDI = Pointer to a uxfs_inode_t
;   RSI = Pointer to a uxfs_fscrypt_policy_t output buffer
;
; Returns:
;   EAX = 0 on success, POSIX_ENOENT when the inode is not encrypted
; -----------------------------------------------------------------------------
align 32
uxfs_fscrypt_get_policy:
    push rbx

    test rdi, rdi
    jz .gp_inval
    test rsi, rsi
    jz .gp_inval

    test dword [rdi + uxfs_inode_t.type_flags], UXFS_FLAG_ENCRYPTED
    jz .gp_missing

    mov byte [rsi + uxfs_fscrypt_policy_t.version], UXFS_FSCRYPT_POLICY_V2
    mov byte [rsi + uxfs_fscrypt_policy_t.contents_mode], UXFS_FSCRYPT_MODE_AES_256_XTS
    mov byte [rsi + uxfs_fscrypt_policy_t.filenames_mode], UXFS_FSCRYPT_MODE_AES_256_CTS
    mov byte [rsi + uxfs_fscrypt_policy_t.flags], UXFS_FSCRYPT_PAD_16

    xor eax, eax
    pop rbx
    ret

.gp_missing:
    mov eax, POSIX_ENOENT
    pop rbx
    ret

.gp_inval:
    mov eax, POSIX_EINVAL
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_fscrypt_pad_name
;
; Rounds a filename length up to the policy's padding granularity.
;
; Without padding, ciphertext length equals plaintext length and an observer
; can fingerprint files by name length alone. Padding to 16 or 32 bytes
; collapses many distinct names into one observable size.
;
; Inputs:
;   RDI = Filename length in bytes
;   ESI = Policy flags (padding granularity in the low two bits)
;
; Returns:
;   RAX = Padded length, capped at UXFS_MAX_NAME_LEN
; -----------------------------------------------------------------------------
align 32
uxfs_fscrypt_pad_name:
    and esi, UXFS_FSCRYPT_PAD_MASK

    mov ecx, 4                      ; PAD_4 default granularity
    cmp esi, UXFS_FSCRYPT_PAD_8
    je .pn_8
    cmp esi, UXFS_FSCRYPT_PAD_16
    je .pn_16
    cmp esi, UXFS_FSCRYPT_PAD_32
    je .pn_32
    jmp .pn_round

.pn_8:
    mov ecx, 8
    jmp .pn_round
.pn_16:
    mov ecx, 16
    jmp .pn_round
.pn_32:
    mov ecx, 32

.pn_round:
    ; Round up to the next multiple: (len + gran - 1) & ~(gran - 1).
    mov rax, rdi
    add rax, rcx
    dec rax
    dec rcx
    not rcx
    and rax, rcx

    cmp rax, UXFS_MAX_NAME_LEN
    jbe .pn_done
    mov rax, UXFS_MAX_NAME_LEN

.pn_done:
    ret
