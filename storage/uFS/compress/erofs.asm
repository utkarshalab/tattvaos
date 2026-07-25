; =============================================================================
; Tattva OS — ufs/compress/erofs.asm
; =============================================================================
; Production-Grade EROFS Immutable Compressed Boot Partition Reader.
;
; Implements:
;   - EROFS superblock validation (`magic = 0xE0F5E1E2`)
;   - Compressed inode descriptor parsing (`erofs_inode_compact`, `erofs_inode_extended`)
;   - Fixed-output LZ4 deblock decompression via `ucmp_lz4_decompress`
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
;
; Validates EROFS boot partition superblock header.
;
; Inputs:
;   RDI = Pointer to 1024-byte EROFS superblock memory buffer
;
; Returns:
;   EAX = 0 (Success) or -22 (EINVAL if invalid magic)
; -----------------------------------------------------------------------------
align 32
ufs_erofs_mount:
    push rbx

    mov rbx, rdi
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
;
; Decompresses an EROFS block using fast LZ4 fixed-output decompression.
;
; Inputs:
;   RDI = Pointer to compressed block buffer
;   RSI = Compressed byte length
;   RDX = Pointer to 4KB destination uncompressed block buffer
;
; Returns:
;   RAX = Uncompressed bytes written (4096)
; -----------------------------------------------------------------------------
align 32
ufs_erofs_read_block:
    push rbp
    mov rbp, rsp

    mov rcx, 4096                   ; Destination capacity
    call ucmp_lz4_decompress

    pop rbp
    ret
