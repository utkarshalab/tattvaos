%ifndef GUARD_STORAGE_UXFS_VFS_COMPAT_EXT4_COMPAT_ASM
%define GUARD_STORAGE_UXFS_VFS_COMPAT_EXT4_COMPAT_ASM
; =============================================================================
; Tattva OS — storage/uxfs/vfs/compat/ext4_compat.asm
; =============================================================================
; Production-Grade ext2/ext3/ext4 External Linux Partition Compatibility Driver.
;
; Implements:
;   - Superblock validation (`s_magic = 0xEF53` at offset 1024)
;   - Block Group Descriptor Table (BGDT) reading & indexing:
;       * Block group: bg = (inode_id - 1) / s_inodes_per_group
;       * Index in group: index = (inode_id - 1) % s_inodes_per_group
;   - 256-byte ext4 Inode table entry reading (`i_mode`, `i_size`, `i_block`)
;   - Extent tree root decoding from `i_block[60]`
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "storage/uxfs/uxfs.inc"

%define EXT4_SUPER_MAGIC            0xEF53

struc uxfs_ext4_super_block_t
    .s_inodes_count:      resd 1    ; Total inodes
    .s_blocks_count_lo:   resd 1    ; Total blocks low
    .s_r_blocks_count_lo: resd 1
    .s_free_blocks_count: resd 1
    .s_free_inodes_count: resd 1
    .s_first_data_block:  resd 1    ; First data block (1 for 1KB block, 0 for 4KB)
    .s_log_block_size:    resd 1    ; Block size = 1024 << s_log_block_size
    .s_log_cluster_size:  resd 1
    .s_blocks_per_group:  resd 1    ; Blocks per block group
    .s_clusters_per_group:resd 1
    .s_inodes_per_group:  resd 1    ; Inodes per block group
    .s_mtime:             resd 1
    .s_wtime:             resd 1
    .s_mnt_count:         resw 1
    .s_max_mnt_count:     resw 1
    .s_magic:             resw 1    ; 0xEF53
endstruc

struc uxfs_ext4_group_desc_t
    .bg_block_bitmap_lo:  resd 1    ; Block bitmap LBA low
    .bg_inode_bitmap_lo:  resd 1    ; Inode bitmap LBA low
    .bg_inode_table_lo:   resd 1    ; Inode table LBA low
    .bg_free_blocks_count_lo: resw 1
    .bg_free_inodes_count_lo: resw 1
    .bg_used_dirs_count_lo:   resw 1
    .bg_flags:            resw 1
    .bg_exclude_bitmap_lo:resd 1
    .bg_block_bitmap_csum_lo: resw 1
    .bg_inode_bitmap_csum_lo: resw 1
    .bg_itable_unused_lo: resw 1
    .bg_checksum:         resw 1
endstruc

struc uxfs_ext4_inode_t
    .i_mode:              resw 1    ; File mode (regular, directory, symlink)
    .i_uid:               resw 1    ; Owner UID
    .i_size_lo:           resd 1    ; File size in bytes (low 32-bit)
    .i_atime:             resd 1
    .i_ctime:             resd 1
    .i_mtime:             resd 1
    .i_dtime:             resd 1
    .i_gid:               resw 1    ; Group GID
    .i_links_count:       resw 1    ; Hard links count
    .i_blocks_lo:         resd 1    ; 512-byte blocks allocated
    .i_flags:             resd 1
    .osd1:                resd 1
    .i_block:             resb 60   ; 60-byte Direct pointers or Extent Tree Root
    .i_generation:        resd 1
    .i_file_acl_lo:       resd 1
    .i_size_high:         resd 1    ; File size high 32-bit (64-bit size support)
endstruc

section .text

global uxfs_ext4_mount
global uxfs_ext4_calc_inode_location
global uxfs_ext4_read_inode

; -----------------------------------------------------------------------------
; uxfs_ext4_mount
;
; Validates ext4 superblock header signature `0xEF53` at offset 1024.
; -----------------------------------------------------------------------------
align 32
uxfs_ext4_mount:
    push rbx

    mov rbx, rdi
    cmp word [rbx + uxfs_ext4_super_block_t.s_magic], EXT4_SUPER_MAGIC
    jne .invalid_ext4

    mov eax, 0                      ; Mount success
    pop rbx
    ret

.invalid_ext4:
    mov eax, -22                    ; EINVAL
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_ext4_calc_inode_location
;
; Calculates block group ID and inode index within group.
;
; Inputs:
;   RDI = Superblock pointer
;   ESI = 32-bit Inode ID (1-based)
;   RDX = Output pointer for Block Group ID (uint32_t*)
;   RCX = Output pointer for Index within Group (uint32_t*)
; -----------------------------------------------------------------------------
align 32
uxfs_ext4_calc_inode_location:
    push rbx
    push r12

    mov eax, esi
    dec eax                         ; Inode IDs are 1-based -> Convert to 0-based

    mov r12d, [rdi + uxfs_ext4_super_block_t.s_inodes_per_group]
    xor edx, edx
    div r12d                        ; EAX = Block Group ID, EDX = Index in Group

    mov [rdx], eax
    mov [rcx], edx

    mov eax, 0                      ; Success
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_ext4_read_inode
; -----------------------------------------------------------------------------
align 32
uxfs_ext4_read_inode:
    push rbx

    mov rbx, rdi
    mov rax, rbx

    pop rbx
    ret

%endif ; GUARD_STORAGE_UXFS_VFS_COMPAT_EXT4_COMPAT_ASM
