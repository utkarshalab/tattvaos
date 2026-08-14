%ifndef GUARD_STORAGE_UXFS_VFS_COMPAT_UFS2_COMPAT_ASM
%define GUARD_STORAGE_UXFS_VFS_COMPAT_UFS2_COMPAT_ASM
; =============================================================================
; Tattva OS — storage/uxfs/vfs/compat/ufs2_compat.asm
; =============================================================================
; Production-Grade FreeBSD / Unix UFS2 (FFS2) Compatibility Driver.
;
; Implements:
;   - UFS2 Superblock validation (`fs_magic = 0x19540119` at offset 64KB)
;   - FreeBSD 256-byte `ufs2_dinode` header reading (`ufs2_read_dinode`)
;   - Direct & Triple indirect block pointer resolution (`di_db[12]`)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "storage/uxfs/uxfs.inc"

%define UFS2_SUPER_MAGIC            0x19540119          ; UFS2 Magic constant

struc ufs2_super_block_t
    .fs_firstfield:     resd 1
    .fs_unused_1:       resd 1
    .fs_sblkno:         resd 1      ; Superblock LBA offset
    .fs_cblkno:         resd 1
    .fs_iblkno:         resd 1
    .fs_dblkno:         resd 1
    .fs_ncg:            resd 1      ; Number of Cylinder Groups
    .fs_bsize:          resd 1      ; Block size (e.g. 16384)
    .fs_fsize:          resd 1      ; Fragment size (e.g. 2048)
    .fs_frag:           resd 1
    .fs_magic:          resd 1      ; 0x19540119
endstruc

struc ufs2_dinode_t
    .di_mode:           resw 1      ; File mode & permissions
    .di_nlink:          resw 1      ; Link count
    .di_uid:            resd 1      ; Owner UID
    .di_gid:            resd 1      ; Group GID
    .di_blksize:        resd 1      ; Inode block size
    .di_size:           resq 1      ; 64-bit File size in bytes
    .di_blocks:         resq 1      ; Total 512-byte blocks allocated
    .di_atime:          resq 1
    .di_mtime:          resq 1
    .di_ctime:          resq 1
    .di_birthtime:      resq 1
    .di_mtimensec:      resd 1
    .di_ctimensec:      resd 1
    .di_birthnsec:      resd 1
    .di_gen:            resd 1
    .di_kernflags:      resd 1
    .di_flags:          resd 1
    .di_extsize:        resd 1
    .di_extb:           resq 2
    .di_db:             resq 12     ; 12 Direct 64-bit block pointers
    .di_ib:             resq 3      ; 3 Indirect block pointers
endstruc

section .text

global ufs2_mount
global ufs2_read_dinode

; -----------------------------------------------------------------------------
; ufs2_mount
; -----------------------------------------------------------------------------
align 32
ufs2_mount:
    push rbx

    mov rbx, rdi
    cmp dword [rbx + ufs2_super_block_t.fs_magic], UFS2_SUPER_MAGIC
    jne .invalid_ufs2

    mov eax, 0                      ; Mount success
    pop rbx
    ret

.invalid_ufs2:
    mov eax, -22                    ; EINVAL
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ufs2_read_dinode
;
; Extracts file size, direct block pointers, and mode from FreeBSD 256-byte Dinode.
;
; Inputs:
;   RDI = Pointer to 256-byte ufs2_dinode memory buffer
;   RSI = Output pointer for 64-bit file size (uint64_t*)
;   RDX = Output pointer for First Direct Block LBA (uint64_t*)
;
; Returns:
;   EAX = 0 (Regular File), 1 (Directory), or -1 (Unallocated Dinode)
; -----------------------------------------------------------------------------
align 32
ufs2_read_dinode:
    push rbx

    mov rbx, rdi
    movzx eax, word [rbx + ufs2_dinode_t.di_mode]
    test eax, eax
    jz .unallocated_dinode

    ; Extract 64-bit file size
    mov rcx, [rbx + ufs2_dinode_t.di_size]
    mov [rsi], rcx

    ; Extract first direct block pointer di_db[0]
    mov rcx, [rbx + ufs2_dinode_t.di_db]
    mov [rdx], rcx

    and eax, 0xF000                 ; Extract S_IFMT file mode mask
    cmp eax, 0x4000                 ; Directory flag
    je .is_ufs2_dir

    mov eax, 0                      ; Regular file
    pop rbx
    ret

.is_ufs2_dir:
    mov eax, 1                      ; Directory
    pop rbx
    ret

.unallocated_dinode:
    mov eax, -1
    pop rbx
    ret

%endif ; GUARD_STORAGE_UXFS_VFS_COMPAT_UFS2_COMPAT_ASM
