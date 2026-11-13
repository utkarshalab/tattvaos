; Scalable format-v3 repository superblock codec ABI.
%ifndef VCS_SUPERBLOCK_INC
%define VCS_SUPERBLOCK_INC

VCS_SUPERBLOCK_BYTES       equ 512
VCS_SUPERBLOCK_CHECKSUM_AT equ 480
VCS_SUPERBLOCK_FEATURES    equ 0x0f
VCS_SUPERBLOCK_REQUIRED    equ 0x03

struc vcs_superblock
    .magic            resb 8
    .version          resd 1
    .header_bytes     resd 1
    .features         resq 1
    .generation       resq 1
    .uuid             resb 16
    .hash_algorithm   resd 1
    .block_size       resd 1
    .head             resb 32
    .ref_root         resb 32
    .ownership_root   resb 32
    .operation_head   resb 32
    .object_index_root resb 32
    .migration_root   resb 32
    .operation_sequence resq 1
    .next_transaction resq 1
    .created_ns       resq 1
    .reserved         resb 208
    .checksum         resb 32
endstruc

%ifndef VCS_SUPERBLOCK_IMPLEMENTATION
extern vcs_superblock_seal
extern vcs_superblock_verify
%endif

%endif
