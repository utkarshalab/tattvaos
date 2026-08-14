; =============================================================================
; Tattva OS — storage/uxfs/vfs/compat/exfat.asm
; =============================================================================
; Production-Grade exFAT (Extended File Allocation Table) Compatibility Driver.
;
; Implements:
;   - exFAT VBR Boot Sector validation ("EXFAT   " magic at offset 3)
;   - Cluster-to-LBA translation (`uxfs_exfat_cluster_to_lba`)
;   - 32-bit FAT cluster chain traversal (`fat[cluster] * 4`)
;   - Directory Set entry parser (File 0x85, Stream Ext 0xC0, File Name 0xC1)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "storage/uxfs/uxfs.inc"

%define EXFAT_SUPER_MAGIC           0x2054414658452020  ; "EXFAT   "

%define EXFAT_ENTRY_TYPE_FILE       0x85
%define EXFAT_ENTRY_TYPE_STREAM     0xC0
%define EXFAT_ENTRY_TYPE_NAME       0xC1

struc uxfs_exfat_vbr_t
    .jump_boot:         resb 3
    .fs_name:           resb 8      ; "EXFAT   "
    .must_be_zero:      resb 53
    .partition_offset:  resq 1
    .volume_length:     resq 1      ; Total sectors
    .fat_offset:        resd 1      ; Starting sector of FAT
    .fat_length:        resd 1      ; Length of FAT in sectors
    .cluster_heap_offset: resd 1   ; Starting sector of Cluster Heap
    .cluster_count:     resd 1      ; Total clusters
    .root_dir_cluster:  resd 1      ; First cluster of Root Directory
    .vol_serial:        resd 1
    .fs_version:        resw 1
    .volume_flags:      resw 1
    .bytes_per_sector_shift: resb 1 ; e.g. 9 (512 bytes) or 12 (4096 bytes)
    .sectors_per_cluster_shift: resb 1
endstruc

struc uxfs_exfat_dir_entry_t
    .entry_type:        resb 1      ; 0x85, 0xC0, 0xC1
    .secondary_count:   resb 1
    .checksum:          resw 1
    .file_attributes:   resw 1
    .reserved1:         resw 1
    .create_timestamp:  resd 1
    .modify_timestamp:  resd 1
    .access_timestamp:  resd 1
    .create_10ms:       resb 1
    .modify_10ms:       resb 1
    .create_tz:         resb 1
    .modify_tz:         resb 1
    .access_tz:         resb 1
    .reserved2:         resb 7
endstruc

struc uxfs_exfat_stream_ext_t
    .entry_type:        resb 1      ; 0xC0
    .flags:             resb 1      ; AllocationFlags (NoFatChain = bit 1)
    .reserved1:         resb 1
    .name_len:          resb 1      ; Name length in UTF-16 characters
    .name_hash:         resw 1
    .reserved2:         resw 1
    .valid_data_len:    resq 1      ; Valid byte length
    .reserved3:         resd 1
    .first_cluster:     resd 1      ; Starting cluster ID
    .data_len:          resq 1      ; 64-bit File size in bytes
endstruc

section .text

global uxfs_exfat_mount
global uxfs_exfat_cluster_to_lba
global uxfs_exfat_get_next_cluster
global uxfs_exfat_parse_dir_set

; -----------------------------------------------------------------------------
; uxfs_exfat_mount
; -----------------------------------------------------------------------------
align 32
uxfs_exfat_mount:
    push rbx

    mov rbx, rdi
    ; cmp r/m64 only encodes a sign-extended imm32, so the 8-byte "EXFAT   "
    ; magic must be materialised in a register before comparing.
    mov rax, EXFAT_SUPER_MAGIC
    cmp qword [rbx + 3], rax
    jne .invalid_exfat

    ; Verify sector shift is valid (9 = 512, 12 = 4096)
    mov al, byte [rbx + uxfs_exfat_vbr_t.bytes_per_sector_shift]
    cmp al, 9
    jb .invalid_exfat
    cmp al, 12
    ja .invalid_exfat

    mov eax, 0                      ; Mount success
    pop rbx
    ret

.invalid_exfat:
    mov eax, -22                    ; EINVAL
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_exfat_cluster_to_lba
;
; Translates 32-bit exFAT cluster ID (starting at cluster 2) to physical LBA sector.
; Formula: LBA = cluster_heap_offset + (cluster - 2) * (1 << sectors_per_cluster_shift)
;
; Inputs:
;   RDI = Pointer to uxfs_exfat_vbr_t
;   ESI = 32-bit Cluster ID (>= 2)
;
; Returns:
;   RAX = 64-bit Physical Sector LBA
; -----------------------------------------------------------------------------
align 32
uxfs_exfat_cluster_to_lba:
    push rbx
    push r12

    mov rbx, rdi
    mov eax, esi
    sub eax, 2                      ; Clusters are 2-based in exFAT
    js .invalid_cluster

    movzx ecx, byte [rbx + uxfs_exfat_vbr_t.sectors_per_cluster_shift]
    shl rax, cl                     ; Multiply by sectors per cluster

    ; No movzx from 32->64 exists; a 32-bit mov already zero-extends into RDX.
    mov edx, dword [rbx + uxfs_exfat_vbr_t.cluster_heap_offset]
    add rax, rdx                    ; Add cluster heap starting sector offset

    pop r12
    pop rbx
    ret

.invalid_cluster:
    xor rax, rax                    ; 0 LBA
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_exfat_get_next_cluster
;
; Reads FAT32/exFAT cluster chain table entry fat[current_cluster * 4].
; -----------------------------------------------------------------------------
align 32
uxfs_exfat_get_next_cluster:
    push rbx

    mov rbx, rdi                    ; Pointer to FAT sector memory buffer
    mov eax, esi                    ; Current cluster ID

    mov eax, dword [rbx + rax * 4]  ; Read next cluster pointer
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_exfat_parse_dir_set
;
; Parses exFAT Directory Entry Set (File 0x85 + Stream Extension 0xC0).
;
; Inputs:
;   RDI = Pointer to 32-byte Directory Entry Set buffer
;   RSI = Output pointer for first cluster ID (uint32_t*)
;   RDX = Output pointer for 64-bit file size (uint64_t*)
;
; Returns:
;   EAX = 0 (Regular File), 1 (Directory), or -1 (Deleted/Invalid)
; -----------------------------------------------------------------------------
align 32
uxfs_exfat_parse_dir_set:
    push rbx
    push r12

    mov rbx, rdi

    ; Check 0x85 File Directory Entry
    cmp byte [rbx + uxfs_exfat_dir_entry_t.entry_type], EXFAT_ENTRY_TYPE_FILE
    jne .invalid_entry

    movzx r12d, word [rbx + uxfs_exfat_dir_entry_t.file_attributes]

    ; Move cursor to 0xC0 Stream Extension Entry (+32 bytes)
    add rbx, 32
    cmp byte [rbx + uxfs_exfat_stream_ext_t.entry_type], EXFAT_ENTRY_TYPE_STREAM
    jne .invalid_entry

    ; Extract 32-bit starting cluster
    mov eax, [rbx + uxfs_exfat_stream_ext_t.first_cluster]
    mov [rsi], eax

    ; Extract 64-bit file size
    mov rax, [rbx + uxfs_exfat_stream_ext_t.data_len]
    mov [rdx], rax

    test r12w, 0x10                 ; Directory attribute bit
    jnz .is_exfat_dir

    mov eax, 0                      ; Regular file
    pop r12
    pop rbx
    ret

.is_exfat_dir:
    mov eax, 1                      ; Directory
    pop r12
    pop rbx
    ret

.invalid_entry:
    mov eax, -1
    pop r12
    pop rbx
    ret
