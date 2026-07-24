; =============================================================================
; Tattva OS — ufs/ufs.inc
; =============================================================================
; Master Schema Definitions for uFS (Unikernel Encrypted File System v1.0).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef UFS_INC
%define UFS_INC

; -----------------------------------------------------------------------------
; uFS Constants & Magic Numbers
; -----------------------------------------------------------------------------
%define UFS_MAGIC_NUMBER            0x5546533230323630  ; "UFS20260"
%define UFS_SECTOR_SIZE             512                 ; 512-byte physical disk sector
%define UFS_BLOCK_SIZE              4096                ; 4KB logical file system block
%define UFS_MAX_FILENAME_LEN        255
%define UFS_INODE_SIZE              128
%define UFS_MAX_OPEN_FILES          1024

; -----------------------------------------------------------------------------
; Unikernel Single-User Performance Mode Flag
; -----------------------------------------------------------------------------
%define CONFIG_UNIKERNEL_SINGLE_USER 1

; -----------------------------------------------------------------------------
; File Inode Types & Feature Flags
; -----------------------------------------------------------------------------
%define UFS_TYPE_REGULAR            0x01
%define UFS_TYPE_DIRECTORY          0x02
%define UFS_TYPE_SYMLINK            0x03
%define UFS_TYPE_DEVICE             0x04
%define UFS_FLAG_ENCRYPTED          0x1000
%define UFS_FLAG_COMPRESSED         0x2000
%define UFS_FLAG_COW_SNAPSHOT       0x4000
%define UFS_FLAG_IMMUTABLE_EROFS    0x8000
%define UFS_FLAG_PQC_ENCRYPTED      0x10000

; -----------------------------------------------------------------------------
; uFS Superblock Schema (512 bytes)
; -----------------------------------------------------------------------------
struc ufs_superblock_t
    .magic:             resq 1      ; UFS_MAGIC_NUMBER ("UFS20260")
    .version:           resd 1      ; File system version (0x0100)
    .block_size:        resd 1      ; Block size (4096)
    .total_blocks:      resq 1      ; Total storage blocks
    .free_blocks:       resq 1      ; Free block count
    .total_inodes:      resq 1      ; Total inode count
    .free_inodes:       resq 1      ; Free inode count
    .root_inode_id:     resq 1      ; Root directory inode ID
    .journal_block_id:  resq 1      ; Fast-Commit WAL Journal Block ID
    .alloc_group_count: resd 1      ; XFS Allocation Group count
    .flags:             resd 1      ; Superblock flags
    .disk_uuid:         resb 16     ; 128-bit Disk UUID
    .volume_name:       resb 64     ; Volume label string
    .reserved:          resb 384    ; Pad to 512 bytes
endstruc

; -----------------------------------------------------------------------------
; uFS Inode Schema (128 bytes)
; -----------------------------------------------------------------------------
struc ufs_inode_t
    .inode_id:          resq 1      ; Inode 64-bit ID
    .type_flags:        resd 1      ; File type and permission flags
    .uid:               resd 1      ; Owner User ID
    .gid:               resd 1      ; Owner Group ID
    .file_size:         resq 1      ; File size in bytes
    .block_count:       resq 1      ; Allocated 4KB block count
    .atime:             resq 1      ; Access timestamp (POSIX epoch)
    .mtime:             resq 1      ; Modification timestamp
    .ctime:             resq 1      ; Status change timestamp
    .direct_blocks:     resq 8      ; 8 Direct block pointers (32KB inline)
    .extent_root_id:    resq 1      ; Extents tree root block pointer
    .blake3_checksum:   resb 32     ; BLAKE3 256-bit data integrity checksum
endstruc

; -----------------------------------------------------------------------------
; uFS VFS File Descriptor Schema
; -----------------------------------------------------------------------------
struc ufs_file_desc_t
    .fd_id:             resd 1      ; File descriptor integer (0, 1, 2...)
    .flags:             resd 1      ; Open flags (O_RDONLY, O_WRONLY...)
    .inode_id:          resq 1      ; Associated inode ID
    .file_offset:       resq 1      ; Read/Write offset pointer
    .key_vault_ptr:     resq 1      ; Per-directory encryption key vault pointer
endstruc

%endif ; UFS_INC
