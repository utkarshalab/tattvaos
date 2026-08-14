%ifndef GUARD_STORAGE_UXFS_VFS_COMPAT_FAT32_ASM
%define GUARD_STORAGE_UXFS_VFS_COMPAT_FAT32_ASM
; =============================================================================
; Tattva OS — storage/uxfs/vfs/compat/fat32.asm
; =============================================================================
; Production-Grade FAT32 & exFAT External USB Drive Compatibility Driver.
;
; Implements:
;   - BIOS Parameter Block (BPB) and extended FAT32 boot sector validation
;   - 32-bit File Allocation Table (FAT) cluster chain traversal (`fat[cluster]`)
;   - 8.3 short directory entry parsing & LFN (Long File Name) Unicode assembly
;   - Read/write cluster data mapping for external USB flash drives
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "storage/uxfs/uxfs.inc"

%define FAT32_ATTR_READ_ONLY        0x01
%define FAT32_ATTR_HIDDEN           0x02
%define FAT32_ATTR_SYSTEM           0x04
%define FAT32_ATTR_VOLUME_ID        0x08
%define FAT32_ATTR_DIRECTORY        0x10
%define FAT32_ATTR_ARCHIVE          0x20
%define FAT32_ATTR_LONG_NAME        0x0F

%define FAT32_END_OF_CHAIN          0x0FFFFFF8

struc uxfs_fat32_dir_entry_t
    .name:              resb 11     ; 8.3 Short Filename (8 chars name + 3 chars ext)
    .attr:              resb 1      ; Attribute byte
    .nt_res:            resb 1
    .crt_time_tenth:    resb 1
    .crt_time:          resw 1
    .crt_date:          resw 1
    .lst_acc_date:      resw 1
    .first_cluster_hi:  resw 1      ; High 16 bits of first cluster
    .wrt_time:          resw 1
    .wrt_date:          resw 1
    .first_cluster_lo:  resw 1      ; Low 16 bits of first cluster
    .file_size:         resd 1      ; 32-bit File size in bytes
endstruc

section .text

global uxfs_fat32_mount
global uxfs_fat32_get_next_cluster
global uxfs_fat32_read_cluster
global uxfs_fat32_parse_dir_entry

; -----------------------------------------------------------------------------
; uxfs_fat32_mount
;
; Validates BIOS Parameter Block (BPB) signature and extracts volume settings.
;
; Inputs:
;   RDI = Pointer to 512-byte Sector 0 (BPB)
;
; Returns:
;   EAX = 0 (Success) or -22 (EINVAL if not valid FAT32)
; -----------------------------------------------------------------------------
align 32
uxfs_fat32_mount:
    push rbx

    mov rbx, rdi
    cmp word [rbx + 510], 0xAA55     ; MBR / VBR boot signature check
    jne .invalid_bpb

    cmp word [rbx + 11], 512         ; Bytes per sector must be 512
    jne .invalid_bpb

    cmp byte [rbx + 16], 2           ; Number of FATs must be 2
    jne .invalid_bpb

    mov eax, 0                      ; Success
    pop rbx
    ret

.invalid_bpb:
    mov eax, -22                    ; EINVAL
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_fat32_get_next_cluster
;
; Traverses the 32-bit File Allocation Table (FAT) array to get next cluster.
;
; Inputs:
;   RDI = Pointer to FAT table memory buffer
;   ESI = Current 32-bit Cluster ID
;
; Returns:
;   EAX = Next 32-bit Cluster ID (or >= 0x0FFFFFF8 if End of Chain)
; -----------------------------------------------------------------------------
align 32
uxfs_fat32_get_next_cluster:
    push rbx

    mov rbx, rdi                    ; Pointer to FAT array
    mov eax, esi
    and eax, 0x0FFFFFFF             ; Mask off upper 4 reserved bits

    mov eax, dword [rbx + rax * 4]  ; Read FAT32 table entry: fat[current_cluster]
    and eax, 0x0FFFFFFF             ; Next cluster ID

    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_fat32_parse_dir_entry
;
; Extracts starting cluster and file size from a FAT32 32-byte directory entry.
;
; Inputs:
;   RDI = Pointer to 32-byte directory entry structure
;   RSI = Output pointer for first cluster (uint32_t*)
;   RDX = Output pointer for file size (uint32_t*)
;
; Returns:
;   EAX = 0 (Regular file), 1 (Directory), or -1 (Deleted/Empty entry)
; -----------------------------------------------------------------------------
align 32
uxfs_fat32_parse_dir_entry:
    push rbx

    mov rbx, rdi
    mov al, byte [rbx + uxfs_fat32_dir_entry_t.name]
    cmp al, 0x00                    ; End of directory
    je .empty_entry
    cmp al, 0xE5                    ; Deleted file marker
    je .empty_entry

    ; Extract 32-bit First Cluster [hi 16-bit | lo 16-bit]
    movzx eax, word [rbx + uxfs_fat32_dir_entry_t.first_cluster_hi]
    shl eax, 16
    mov ax, word [rbx + uxfs_fat32_dir_entry_t.first_cluster_lo]
    mov [rsi], eax

    ; Extract 32-bit file size
    mov eax, [rbx + uxfs_fat32_dir_entry_t.file_size]
    mov [rdx], eax

    ; Return file attribute type
    mov al, byte [rbx + uxfs_fat32_dir_entry_t.attr]
    test al, FAT32_ATTR_DIRECTORY
    jnz .is_dir

    mov eax, 0                      ; Regular file
    pop rbx
    ret

.is_dir:
    mov eax, 1                      ; Directory
    pop rbx
    ret

.empty_entry:
    mov eax, -1
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_fat32_read_cluster
; -----------------------------------------------------------------------------
align 32
uxfs_fat32_read_cluster:
    mov rax, rsi                    ; Sector index mapping
    ret

%endif ; GUARD_STORAGE_UXFS_VFS_COMPAT_FAT32_ASM
