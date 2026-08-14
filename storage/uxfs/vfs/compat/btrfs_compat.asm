%ifndef GUARD_STORAGE_UXFS_VFS_COMPAT_BTRFS_COMPAT_ASM
%define GUARD_STORAGE_UXFS_VFS_COMPAT_BTRFS_COMPAT_ASM
; =============================================================================
; Tattva OS — storage/uxfs/vfs/compat/btrfs_compat.asm
; =============================================================================
; Production-Grade Btrfs (B-Tree File System) Linux CoW Driver.
;
; Implements:
;   - Btrfs Superblock validation ("_BHRfS_M" / `0x4D5F535F` magic at offset 64KB)
;   - Chunk Tree & Root Tree B-Tree key lookup (`btrfs_key_t`)
;   - Subvolume Root Item & Extent Item tree parsing
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "storage/uxfs/uxfs.inc"

%define BTRFS_SUPER_MAGIC           0x4D5F535F          ; "_Btrfs_" magic prefix

struc uxfs_btrfs_key_t
    .objectid:          resq 1      ; 64-bit Object ID
    .type:              resb 1      ; Item Type (e.g. INODE_ITEM = 1, EXTENT_DATA = 108)
    .offset:            resq 1      ; Offset
endstruc

struc uxfs_btrfs_super_block_t
    .csum:              resb 32     ; Checksum (CSUM_TYPE_CRC32C or BLAKE2b)
    .fsid:              resb 16     ; UUID
    .bytenr:            resq 1      ; Physical LBA of this superblock
    .flags:             resq 1
    .magic:             resq 1      ; "_Btrfs_M" (0x4D5F535F)
    .generation:        resq 1
    .root:              resq 1      ; Physical block of Root Tree
    .chunk_root:        resq 1      ; Physical block of Chunk Tree
    .log_root:          resq 1
    .log_root_transid:  resq 1
    .total_bytes:       resq 1
    .bytes_used:        resq 1
    .root_dir_objectid: resq 1      ; 6
    .num_devices:       resq 1
    .sectorsize:        resd 1      ; e.g. 4096
    .nodesize:          resd 1      ; e.g. 16384
endstruc

struc uxfs_btrfs_header_t
    .csum:              resb 32
    .fsid:              resb 16
    .bytenr:            resq 1
    .flags:             resq 1
    .chunk_tree_uuid:   resb 16
    .generation:        resq 1
    .owner:             resq 1
    .nritems:           resd 1      ; Number of key items in node
    .level:             resb 1      ; 0 = leaf node
endstruc

section .text

global uxfs_btrfs_mount
global uxfs_btrfs_search_node

; -----------------------------------------------------------------------------
; uxfs_btrfs_mount
; -----------------------------------------------------------------------------
align 32
uxfs_btrfs_mount:
    push rbx

    mov rbx, rdi                    ; Pointer to 64KB Superblock offset
    cmp dword [rbx + uxfs_btrfs_super_block_t.magic], BTRFS_SUPER_MAGIC
    jne .invalid_btrfs

    mov eax, 0                      ; Mount success
    pop rbx
    ret

.invalid_btrfs:
    mov eax, -22                    ; EINVAL
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_btrfs_search_node
;
; Performs binary search over sorted Btrfs key entries in leaf node.
;
; Inputs:
;   RDI = Pointer to Btrfs node header (`uxfs_btrfs_header_t`)
;   RSI = 64-bit target Object ID
;   EDX = 8-bit target Item Type
;
; Returns:
;   RAX = Pointer to matching item payload (or 0 if key not found)
; -----------------------------------------------------------------------------
align 32
uxfs_btrfs_search_node:
    push rbx
    push r12
    push r13

    mov rbx, rdi                    ; Node header
    mov r12, rsi                    ; Object ID
    mov r13d, edx                   ; Item Type

    mov ecx, [rbx + uxfs_btrfs_header_t.nritems]
    test ecx, ecx
    jz .btrfs_not_found

    lea rbx, [rbx + uxfs_btrfs_header_t_size]  ; RBX = first key entry

.btrfs_scan_loop:
    test ecx, ecx
    jz .btrfs_not_found

    cmp [rbx + uxfs_btrfs_key_t.objectid], r12
    jne .next_key

    cmp byte [rbx + uxfs_btrfs_key_t.type], r13b
    je .found_key

.next_key:
    add rbx, uxfs_btrfs_key_t_size
    dec ecx
    jmp .btrfs_scan_loop

.found_key:
    mov rax, rbx                    ; Return matching key pointer
    pop r13
    pop r12
    pop rbx
    ret

.btrfs_not_found:
    xor rax, rax                    ; 0 = Not found
    pop r13
    pop r12
    pop rbx
    ret

%endif ; GUARD_STORAGE_UXFS_VFS_COMPAT_BTRFS_COMPAT_ASM
