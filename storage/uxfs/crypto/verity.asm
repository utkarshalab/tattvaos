; =============================================================================
; Tattva OS — storage/uxfs/crypto/verity.asm
; =============================================================================
; dm-verity Merkle Tree Block Integrity Verification.
;
; Implements:
;   - Salted leaf hashing (`uxfs_verity_hash_block`)
;   - Full leaf-to-root Merkle path verification (`uxfs_verity_verify_path`)
;   - Single-level digest comparison (`uxfs_verity_verify_block`)
;   - Superblock root anchoring (`uxfs_verity_set_root`, `uxfs_verity_check_root`)
;
; Verifying a block against a caller-supplied digest proves nothing on its own:
; an attacker who can rewrite the block can rewrite the digest beside it. The
; guarantee comes from the CHAIN — each block's hash appears in a parent node,
; whose hash appears in its parent, up to a single root digest held somewhere
; the attacker cannot reach (a signed superblock or the TPM vault).
;
; Tree geometry: 4096-byte hash blocks holding 32-byte SHA-256 digests gives a
; fanout of 128, so a 1TB volume of 4KB blocks needs only five levels. Each
; level is verified on the way up, so tampering anywhere in the path is caught.
;
; Leaves are salted. Without a salt, identical data blocks hash identically
; across volumes, letting an attacker precompute a dictionary of known-content
; digests once and reuse it against every deployment.
;
; All digest comparisons are constant time. A variable-time compare on a
; verification path lets an attacker recover the expected digest byte by byte
; by timing how early the comparison aborts.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "storage/uxfs/uxfs.inc"

%define UXFS_VERITY_DIGEST_BYTES     32
%define UXFS_VERITY_BLOCK_BYTES      4096
%define UXFS_VERITY_MAX_SALT         32
%define UXFS_VERITY_FANOUT           128     ; 4096 / 32 digests per hash block
%define UXFS_VERITY_FANOUT_SHIFT     7       ; log2(128), for index descent
%define UXFS_VERITY_MAX_LEVELS       8       ; Covers well beyond 1TB at 4KB
%define UXFS_VERITY_VERSION          1

; -----------------------------------------------------------------------------
; Verity descriptor. `root_digest` is the trust anchor: everything else on the
; volume is untrusted until it chains up to this value.
; -----------------------------------------------------------------------------
struc uxfs_verity_sb_t
    .version:           resd 1      ; UXFS_VERITY_VERSION
    .hash_algorithm:    resd 1      ; 0 = SHA-256
    .data_block_size:   resd 1      ; 4096
    .hash_block_size:   resd 1      ; 4096
    .data_blocks:       resq 1      ; Leaf count
    .levels:            resd 1      ; Tree height, excluding the root
    .salt_size:         resd 1      ; 0..UXFS_VERITY_MAX_SALT
    .salt:              resb UXFS_VERITY_MAX_SALT
    .root_digest:       resb UXFS_VERITY_DIGEST_BYTES
endstruc

section .data
align 64

; Staging for salt || block. Salt is prepended, matching dm-verity layout.
uxfs_verity_hash_in:    times UXFS_VERITY_MAX_SALT + UXFS_VERITY_BLOCK_BYTES db 0
uxfs_verity_digest:     times UXFS_VERITY_DIGEST_BYTES db 0
uxfs_verity_walk:       times UXFS_VERITY_DIGEST_BYTES db 0

global uxfs_verity_failures
uxfs_verity_failures:   dq 0        ; Cumulative integrity failures observed

section .text

global uxfs_verity_hash_block
global uxfs_verity_verify_block
global uxfs_verity_verify_path
global uxfs_verity_set_root
global uxfs_verity_check_root
global uxfs_verity_level_offset

; -----------------------------------------------------------------------------
; uxfs_verity_hash_block
;
; digest = SHA-256(salt || block)
;
; Inputs:
;   RDI = Pointer to the block to hash
;   ESI = Block length in bytes
;   RDX = Pointer to a uxfs_verity_sb_t (supplies the salt)
;   RCX = Pointer to a 32-byte digest output buffer
;
; Returns:
;   EAX = 0 on success, POSIX_EINVAL on a bad argument
; -----------------------------------------------------------------------------
align 32
uxfs_verity_hash_block:
    push rbx
    push r12
    push r13
    push r14

    mov rbx, rdi                    ; Block
    mov r12d, esi                   ; Block length
    mov r13, rdx                    ; Verity superblock
    mov r14, rcx                    ; Digest out

    test rbx, rbx
    jz .hb_inval
    test r14, r14
    jz .hb_inval
    cmp r12d, UXFS_VERITY_BLOCK_BYTES
    ja .hb_inval

    xor ecx, ecx
    test r13, r13
    jz .hb_no_salt
    mov ecx, dword [r13 + uxfs_verity_sb_t.salt_size]
    cmp ecx, UXFS_VERITY_MAX_SALT
    ja .hb_inval

.hb_no_salt:
    push rcx                        ; Preserve salt length across the copies

    ; Stage salt first.
    test ecx, ecx
    jz .hb_copy_block
    lea rdi, [uxfs_verity_hash_in]
    lea rsi, [r13 + uxfs_verity_sb_t.salt]
    rep movsb

.hb_copy_block:
    pop rcx
    push rcx

    lea rdi, [uxfs_verity_hash_in]
    add rdi, rcx                    ; Block lands immediately after the salt
    mov rsi, rbx
    mov ecx, r12d
    rep movsb

    pop rcx

    lea rdi, [uxfs_verity_hash_in]
    mov esi, r12d
    add rsi, rcx                    ; Total = salt + block
    mov rdx, r14
    call uhash_sha256

    xor eax, eax
    jmp .hb_return

.hb_inval:
    mov eax, POSIX_EINVAL

.hb_return:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_verity_verify_block
;
; Hashes one block and compares it against an expected digest in constant time.
;
; This alone does NOT establish integrity — it is one link. Use
; uxfs_verity_verify_path for an actual trust decision.
;
; Inputs:
;   RDI = Pointer to the block
;   RSI = Pointer to the expected 32-byte digest
;   RDX = Pointer to a uxfs_verity_sb_t, or 0 for an unsalted hash
;
; Returns:
;   EAX = 0 when the digest matches, POSIX_EIO on mismatch
; -----------------------------------------------------------------------------
align 32
uxfs_verity_verify_block:
    push rbx
    push r12

    mov rbx, rdi
    mov r12, rsi

    test rbx, rbx
    jz .vb_inval
    test r12, r12
    jz .vb_inval

    ; RDX still carries the caller's superblock pointer for the salt.
    mov rdi, rbx
    mov esi, UXFS_VERITY_BLOCK_BYTES
    lea rcx, [uxfs_verity_digest]
    call uxfs_verity_hash_block
    test eax, eax
    jnz .vb_fail

    lea rdi, [uxfs_verity_digest]
    mov rsi, r12
    mov rdx, UXFS_VERITY_DIGEST_BYTES
    call ucrypt_ct_memcmp
    test rax, rax
    jnz .vb_fail

    xor eax, eax
    pop r12
    pop rbx
    ret

.vb_fail:
    inc qword [uxfs_verity_failures]
    mov eax, POSIX_EIO
    pop r12
    pop rbx
    ret

.vb_inval:
    mov eax, POSIX_EINVAL
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_verity_level_offset
;
; Byte offset of a level's first hash block within the hash tree region.
; Level 0 is the widest; each level above divides by the fanout.
;
; Inputs:
;   RDI = Pointer to a uxfs_verity_sb_t
;   ESI = Level index
;
; Returns:
;   RAX = Byte offset of that level's base
; -----------------------------------------------------------------------------
align 32
uxfs_verity_level_offset:
    push rbx
    push r12
    push r13

    mov r12d, esi                   ; Target level
    mov r13, [rdi + uxfs_verity_sb_t.data_blocks]
    xor rax, rax                    ; Accumulated offset
    xor ebx, ebx                    ; Current level

.lo_loop:
    cmp ebx, r12d
    jae .lo_done

    ; Blocks at this level = ceil(entries / fanout).
    add r13, UXFS_VERITY_FANOUT - 1
    shr r13, UXFS_VERITY_FANOUT_SHIFT

    mov rcx, r13
    shl rcx, 12                     ; * 4096 bytes per hash block
    add rax, rcx

    inc ebx
    jmp .lo_loop

.lo_done:
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_verity_verify_path
;
; Verifies a data block by walking the Merkle path from leaf to root.
;
; At each level the running digest must appear at the expected slot inside the
; parent hash block; that parent block is then hashed and becomes the running
; digest for the level above. The walk only succeeds if the final digest equals
; the anchored root, so tampering at ANY level is caught.
;
; Inputs:
;   RDI = Pointer to a uxfs_verity_sb_t
;   RSI = Data block index
;   RDX = Pointer to the data block contents
;   RCX = Pointer to the mapped hash tree region
;
; Returns:
;   EAX = 0 when the block chains to the trusted root
;         POSIX_EIO on any mismatch along the path
;         POSIX_EINVAL on a bad argument
; -----------------------------------------------------------------------------
align 32
uxfs_verity_verify_path:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi                    ; Verity superblock
    mov r12, rsi                    ; Block index
    mov r13, rdx                    ; Data block
    mov r14, rcx                    ; Hash tree base

    test rbx, rbx
    jz .vp_inval
    test r13, r13
    jz .vp_inval
    test r14, r14
    jz .vp_inval

    mov rax, [rbx + uxfs_verity_sb_t.data_blocks]
    cmp r12, rax
    jae .vp_inval                   ; Index past the end of the tree

    ; Running digest starts as the salted hash of the data block itself.
    mov rdi, r13
    mov esi, UXFS_VERITY_BLOCK_BYTES
    mov rdx, rbx
    lea rcx, [uxfs_verity_walk]
    call uxfs_verity_hash_block
    test eax, eax
    jnz .vp_inval

    xor r15d, r15d                  ; Current level

.vp_level:
    mov eax, dword [rbx + uxfs_verity_sb_t.levels]
    cmp r15d, eax
    jae .vp_root                    ; Reached the top: compare against root

    ; Locate the parent hash block for the current index.
    mov rdi, rbx
    mov esi, r15d
    call uxfs_verity_level_offset   ; RAX = level base offset

    mov rcx, r12
    shr rcx, UXFS_VERITY_FANOUT_SHIFT   ; Parent block index within the level
    shl rcx, 12                         ; * 4096
    add rax, rcx
    add rax, r14                        ; Absolute parent block address
    push rax                            ; Keep it for the parent hash below

    ; Slot within the parent = (index % fanout) * 32.
    mov rcx, r12
    and rcx, UXFS_VERITY_FANOUT - 1
    shl rcx, 5
    add rax, rcx

    ; The running digest must match the stored slot, in constant time.
    lea rdi, [uxfs_verity_walk]
    mov rsi, rax
    mov rdx, UXFS_VERITY_DIGEST_BYTES
    call ucrypt_ct_memcmp
    test rax, rax
    pop rdi                         ; Parent block address
    jnz .vp_fail

    ; Parent block becomes the next running digest.
    mov esi, UXFS_VERITY_BLOCK_BYTES
    mov rdx, rbx
    lea rcx, [uxfs_verity_walk]
    call uxfs_verity_hash_block
    test eax, eax
    jnz .vp_fail

    shr r12, UXFS_VERITY_FANOUT_SHIFT   ; Ascend one level
    inc r15d
    jmp .vp_level

.vp_root:
    lea rdi, [uxfs_verity_walk]
    lea rsi, [rbx + uxfs_verity_sb_t.root_digest]
    mov rdx, UXFS_VERITY_DIGEST_BYTES
    call ucrypt_ct_memcmp
    test rax, rax
    jnz .vp_fail

    xor eax, eax
    jmp .vp_return

.vp_fail:
    inc qword [uxfs_verity_failures]
    mov eax, POSIX_EIO
    jmp .vp_return

.vp_inval:
    mov eax, POSIX_EINVAL

.vp_return:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_verity_set_root
;
; Anchors the trusted root digest. This value must come from somewhere the
; attacker cannot rewrite — a signed superblock or crypto/vault.asm — otherwise
; the entire tree is self-consistent but meaningless.
;
; Inputs:
;   RDI = Pointer to a uxfs_verity_sb_t
;   RSI = Pointer to the 32-byte trusted root digest
;
; Returns:
;   EAX = 0 on success, POSIX_EINVAL on a null argument
; -----------------------------------------------------------------------------
align 32
uxfs_verity_set_root:
    test rdi, rdi
    jz .sr_inval
    test rsi, rsi
    jz .sr_inval

    push rdi
    lea rdi, [rdi + uxfs_verity_sb_t.root_digest]
    mov rcx, 4
    rep movsq
    pop rdi

    mov dword [rdi + uxfs_verity_sb_t.version], UXFS_VERITY_VERSION
    xor eax, eax
    ret

.sr_inval:
    mov eax, POSIX_EINVAL
    ret

; -----------------------------------------------------------------------------
; uxfs_verity_check_root
;
; Constant-time comparison of a candidate root against the anchored one.
;
; Inputs:
;   RDI = Pointer to a uxfs_verity_sb_t
;   RSI = Pointer to a candidate 32-byte root digest
;
; Returns:
;   EAX = 0 when the roots match, POSIX_EIO otherwise
; -----------------------------------------------------------------------------
align 32
uxfs_verity_check_root:
    push rbx

    test rdi, rdi
    jz .cr_inval
    test rsi, rsi
    jz .cr_inval

    lea rdi, [rdi + uxfs_verity_sb_t.root_digest]
    mov rdx, UXFS_VERITY_DIGEST_BYTES
    call ucrypt_ct_memcmp
    test rax, rax
    jnz .cr_fail

    xor eax, eax
    pop rbx
    ret

.cr_fail:
    inc qword [uxfs_verity_failures]
    mov eax, POSIX_EIO
    pop rbx
    ret

.cr_inval:
    mov eax, POSIX_EINVAL
    pop rbx
    ret
