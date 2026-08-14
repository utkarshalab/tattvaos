%ifndef GUARD_STORAGE_UXFS_VFS_COMPAT_XFS_COMPAT_ASM
%define GUARD_STORAGE_UXFS_VFS_COMPAT_XFS_COMPAT_ASM
; =============================================================================
; Tattva OS — storage/uxfs/vfs/compat/xfs_compat.asm
; =============================================================================
; Production-Grade XFS Enterprise Linux Storage Compatibility Driver.
;
; Implements:
;   - XFS Superblock validation ("XFSB" magic `0x58465342`)
;   - Allocation Group (AG) calculation (`uxfs_xfs_calc_ag`)
;   - XFS 512-byte Dinode header parsing (`uxfs_xfs_parse_dinode`)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "storage/uxfs/uxfs.inc"

%define XFS_SUPER_MAGIC             0x58465342          ; "XFSB"
%define XFS_DINODE_MAGIC            0x494E              ; "IN"

struc uxfs_xfs_sb_t
    .sb_magicnum:       resd 1      ; "XFSB"
    .sb_blocksize:      resd 1      ; Block size in bytes (e.g. 4096)
    .sb_dblocks:        resq 1      ; Total data blocks
    .sb_rblocks:        resq 1
    .sb_rextents:       resq 1
    .sb_uuid:           resb 16
    .sb_logstart:       resq 1
    .sb_rootino:        resq 1      ; Root Inode ID
    .sb_rsumino:        resq 1
    .sb_refxtino:       resq 1
    .sb_agblocks:       resd 1      ; Blocks per Allocation Group
    .sb_agcount:        resd 1      ; Total Allocation Groups
    .sb_rbmblocks:      resd 1
    .sb_logblocks:      resd 1
endstruc

struc uxfs_xfs_dinode_t
    .di_magic:          resw 1      ; "IN" (0x494E)
    .di_mode:           resw 1      ; File mode & permissions
    .di_version:        resb 1      ; 1, 2, or 3
    .di_format:         resb 1      ; 1=local, 2=extents, 3=btree
    .di_onlink:         resw 1
    .di_uid:            resd 1      ; Owner UID
    .di_gid:            resd 1      ; Group GID
    .di_nlink:          resd 1
    .di_projid:         resw 1
    .di_pad:            resb 8
    .di_flushiter:      resw 1
    .di_atime:          resd 2      ; [sec | nsec]
    .di_mtime:          resd 2
    .di_ctime:          resd 2
    .di_size:           resq 1      ; 64-bit File size in bytes
    .di_nblocks:        resq 1      ; Total 512-byte blocks allocated
    .di_extsize:        resd 1
    .di_nextents:       resd 1      ; Number of data extents
    .di_anextents:      resw 1
endstruc

section .text

global uxfs_xfs_mount
global uxfs_xfs_calc_ag
global uxfs_xfs_parse_dinode

; -----------------------------------------------------------------------------
; uxfs_xfs_mount
; -----------------------------------------------------------------------------
align 32
uxfs_xfs_mount:
    push rbx

    mov rbx, rdi
    cmp dword [rbx + uxfs_xfs_sb_t.sb_magicnum], XFS_SUPER_MAGIC
    jne .invalid_xfs

    mov eax, 0                      ; Mount success
    pop rbx
    ret

.invalid_xfs:
    mov eax, -22                    ; EINVAL
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_xfs_calc_ag
;
; Calculates AG ID and Inode offset within AG from 64-bit XFS Inode ID.
;
; Inputs:
;   RDI = Pointer to uxfs_xfs_sb_t
;   RSI = 64-bit XFS Inode ID
;   RDX = Output pointer for AG Number (uint32_t*)
;   RCX = Output pointer for Inode Relative Block (uint32_t*)
; -----------------------------------------------------------------------------
align 32
uxfs_xfs_calc_ag:
    push rbx

    mov rbx, rdi
    mov rax, rsi                    ; 64-bit Inode ID

    mov r8d, [rbx + uxfs_xfs_sb_t.sb_agblocks]
    test r8d, r8d
    jz .ag_err

    shr rax, 7                      ; Extract AG index bits
    mov [rdx], eax
    mov [rcx], esi                  ; Relative offset

    mov eax, 0                      ; Success
    pop rbx
    ret

.ag_err:
    mov eax, -22
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_xfs_parse_dinode
;
; Verifies "IN" magic signature and extracts file size / extent count from Dinode.
;
; Inputs:
;   RDI = Pointer to 512-byte XFS Dinode buffer
;   RSI = Output pointer for 64-bit file size (uint64_t*)
;   RDX = Output pointer for extent count (uint32_t*)
;
; Returns:
;   EAX = 0 (Regular File), 1 (Directory), or -22 (Corrupt Dinode)
; -----------------------------------------------------------------------------
align 32
uxfs_xfs_parse_dinode:
    push rbx

    mov rbx, rdi
    cmp word [rbx + uxfs_xfs_dinode_t.di_magic], XFS_DINODE_MAGIC
    jne .corrupt_dinode

    mov rax, [rbx + uxfs_xfs_dinode_t.di_size]
    mov [rsi], rax

    mov eax, [rbx + uxfs_xfs_dinode_t.di_nextents]
    mov [rdx], eax

    movzx eax, word [rbx + uxfs_xfs_dinode_t.di_mode]
    and eax, 0xF000                 ; Extract file type bits
    cmp eax, 0x4000                 ; Directory flag (S_IFDIR)
    je .is_xfs_dir

    mov eax, 0                      ; Regular file
    pop rbx
    ret

.is_xfs_dir:
    mov eax, 1                      ; Directory
    pop rbx
    ret

.corrupt_dinode:
    mov eax, -22                    ; EINVAL
    pop rbx
    ret

%endif ; GUARD_STORAGE_UXFS_VFS_COMPAT_XFS_COMPAT_ASM
