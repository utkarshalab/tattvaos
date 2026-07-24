; =============================================================================
; Tattva OS — ufs/compress/erofs.asm
; =============================================================================
; EROFS (Enhanced Read-Only File System) Immutable Compressed Boot Partition Reader.
;
; Provides high-speed read-only decompression of system boot images using LZ4
; fixed-output decompression.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "ufs/ufs.inc"
%include "lib/ucmp/include/ucmp.inc"

%define EROFS_MAGIC_NUMBER          0xE0F5E1E2

struc ufs_erofs_super_block_t
    .magic:             resd 1      ; 0xE0F5E1E2
    .checksum:          resd 1
    .feature_compat:    resd 1
    .blkszbits:         resb 1      ; 12 = 4KB block size
    .sb_extslots:       resb 1
    .root_nid:          resw 1      ; Root directory Node ID
    .inos:              resq 1
    .build_time:        resq 1
    .build_time_nsec:   resd 1
    .blocks:            resd 1
    .meta_blkaddr:      resd 1
    .xattr_blkaddr:     resd 1
    .volume_name:       resb 16
endstruc

section .text

global ufs_erofs_mount
global ufs_erofs_read_block

extern ucmp_lz4_decompress

; -----------------------------------------------------------------------------
; ufs_erofs_mount
; -----------------------------------------------------------------------------
align 32
ufs_erofs_mount:
    push rbx

    mov rbx, rdi                    ; Pointer to EROFS superblock
    cmp dword [rbx + ufs_erofs_super_block_t.magic], EROFS_MAGIC_NUMBER
    jne .invalid_erofs

    mov eax, 0                      ; Mount success
    pop rbx
    ret

.invalid_erofs:
    mov eax, -22                    ; EINVAL
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ufs_erofs_read_block
; -----------------------------------------------------------------------------
align 32
ufs_erofs_read_block:
    push rbp
    mov rbp, rsp

    call ucmp_lz4_decompress

    pop rbp
    ret
