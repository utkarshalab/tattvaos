; =============================================================================
; Tattva OS — ufs/ufs.inc
; =============================================================================
; Master Schema Header for uFS (Unikernel Encrypted File System).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef UFS_INC
%define UFS_INC

%define UFS_MAGIC_NUMBER            0x5546533230323630  ; "UFS20260"
%define UFS_BLOCK_SIZE              4096                ; 4KB Standard Block
%define UFS_MAX_OPEN_FILES          256
%define UFS_MAX_PATH_LEN            1024
%define UFS_MAX_NAME_LEN            240

; -----------------------------------------------------------------------------
; POSIX Error Codes
; -----------------------------------------------------------------------------
%define POSIX_ENOENT                -2                  ; No such file or directory
%define POSIX_EIO                   -5                  ; I/O error
%define POSIX_EBADF                 -9                  ; Bad file descriptor
%define POSIX_ENOMEM                -12                 ; Out of memory
%define POSIX_EACCES                -13                 ; Permission denied
%define POSIX_EEXIST                -17                 ; File exists
%define POSIX_EINVAL                -22                 ; Invalid argument
%define POSIX_EMFILE                -24                 ; Too many open files
%define POSIX_ENOSPC                -28                 ; No space left on device
%define POSIX_EDQUOT                -122                ; Disk quota exceeded

; -----------------------------------------------------------------------------
; Feature Flags
; -----------------------------------------------------------------------------
%define UFS_FLAG_ENCRYPTED          (1 << 0)
%define UFS_FLAG_COMPRESSED         (1 << 1)
%define UFS_FLAG_DEDUPLICATED       (1 << 2)
%define UFS_FLAG_VERITY_CHECKED     (1 << 3)
%define UFS_FLAG_COW_SNAPSHOT       (1 << 4)
%define UFS_FLAG_DAX_DIRECT         (1 << 5)

; -----------------------------------------------------------------------------
; Directory Entry Format
; -----------------------------------------------------------------------------
struc ufs_dir_entry_t
    .inode_id:          resq 1      ; 64-bit Target Inode ID
    .rec_len:           resw 1      ; Record byte length (256)
    .name_len:          resb 1      ; Name byte length
    .file_type:         resb 1      ; 1=Regular File, 2=Directory, 3=Symlink
    .name:              resb UFS_MAX_NAME_LEN  ; Null-terminated filename string
endstruc

; -----------------------------------------------------------------------------
; POSIX Stat Metadata Format
; -----------------------------------------------------------------------------
struc ufs_stat_t
    .st_dev:            resq 1      ; Device ID
    .st_ino:            resq 1      ; Inode number
    .st_mode:           resd 1      ; File mode (permissions + type)
    .st_nlink:          resd 1      ; Hard link count
    .st_uid:            resd 1      ; User ID
    .st_gid:            resd 1      ; Group ID
    .st_rdev:           resq 1      ; Device ID (if special file)
    .st_size:           resq 1      ; File size in bytes
    .st_blksize:        resq 1      ; Block size for filesystem I/O (4096)
    .st_blocks:         resq 1      ; 512-byte blocks allocated
    .st_atime:          resq 1      ; Access time
    .st_mtime:          resq 1      ; Modification time
    .st_ctime:          resq 1      ; Status change time
endstruc

; -----------------------------------------------------------------------------
; Superblock Format
; -----------------------------------------------------------------------------
struc ufs_superblock_t
    .magic:             resq 1      ; UFS_MAGIC_NUMBER
    .block_size:        resd 1      ; 4096
    .total_blocks:      resq 1      ; Total storage capacity in blocks
    .free_blocks:       resq 1      ; Available unallocated blocks
    .total_inodes:      resq 1      ; Total inode capacity
    .free_inodes:       resq 1      ; Available unallocated inodes
    .root_inode_id:     resq 1      ; Root directory Inode ID (1)
    .generation:        resq 1      ; Superblock CoW transaction generation
    .checksum:          resb 32     ; BLAKE3 256-bit superblock checksum
endstruc

; -----------------------------------------------------------------------------
; Inode Format (256 bytes)
; -----------------------------------------------------------------------------
struc ufs_inode_t
    .inode_id:          resq 1      ; 64-bit Inode ID
    .mode_permissions:  resd 1      ; POSIX mode & permission bits
    .uid:               resd 1      ; Owner User ID
    .gid:               resd 1      ; Owner Group ID
    .type_flags:        resd 1      ; UFS_FLAG_* bitmask
    .file_size_bytes:   resq 1      ; 64-bit File size in bytes
    .extent_tree_root:  resq 1      ; Physical block ID of extent tree root
    .blake3_checksum:   resb 32     ; BLAKE3 256-bit inode integrity checksum
    .reserved:          resb 184    ; Padding to 256 bytes
endstruc

; -----------------------------------------------------------------------------
; VFS File Descriptor Format
; -----------------------------------------------------------------------------
struc ufs_file_desc_t
    .fd_id:             resd 1      ; File descriptor index (3, 4, 5...)
    .flags:             resd 1      ; O_RDONLY, O_WRONLY, O_RDWR, O_CREAT
    .inode_id:          resq 1      ; Target Inode ID
    .file_offset:       resq 1      ; 64-bit Read/Write byte offset pointer
endstruc

%endif ; UFS_INC
