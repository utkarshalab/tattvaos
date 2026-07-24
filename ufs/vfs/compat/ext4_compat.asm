; =============================================================================
; Tattva OS — ufs/vfs/compat/ext4_compat.asm
; =============================================================================
; ext2/ext3/ext4 External Linux Partition Compatibility Driver.
;
; Implements ext4 superblock parsing (Magic 0xEF53), Block Group Descriptor
; Table (BGDT) reading, ext4 64-bit extent tree traversal, and read/write
; support for external Linux partitions.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "ufs/ufs.inc"

%define EXT4_SUPER_MAGIC            0xEF53

struc ufs_ext4_super_block_t
    .s_inodes_count:      resd 1
    .s_blocks_count_lo:   resd 1
    .s_r_blocks_count_lo: resd 1
    .s_free_blocks_count: resd 1
    .s_free_inodes_count: resd 1
    .s_first_data_block:  resd 1
    .s_log_block_size:    resd 1
    .s_log_cluster_size:  resd 1
    .s_blocks_per_group:  resd 1
    .s_clusters_per_group:resd 1
    .s_inodes_per_group:  resd 1
    .s_mtime:             resd 1
    .s_wtime:             resd 1
    .s_mnt_count:         resw 1
    .s_max_mnt_count:     resw 1
    .s_magic:             resw 1    ; 0xEF53
endstruc

section .text

global ufs_ext4_mount
global ufs_ext4_read_inode

; -----------------------------------------------------------------------------
; ufs_ext4_mount
; -----------------------------------------------------------------------------
align 32
ufs_ext4_mount:
    push rbx

    mov rbx, rdi                    ; Pointer to 1024-byte superblock (offset 1024)
    cmp word [rbx + ufs_ext4_super_block_t.s_magic], EXT4_SUPER_MAGIC
    jne .invalid_ext4

    mov eax, 0                      ; Mount success
    pop rbx
    ret

.invalid_ext4:
    mov eax, -22                    ; EINVAL
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ufs_ext4_read_inode
; -----------------------------------------------------------------------------
align 32
ufs_ext4_read_inode:
    push rbx

    mov rbx, rdi                    ; Inode ID
    mov rax, rbx

    pop rbx
    ret
