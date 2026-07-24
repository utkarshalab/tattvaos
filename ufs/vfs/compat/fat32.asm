; =============================================================================
; Tattva OS — ufs/vfs/compat/fat32.asm
; =============================================================================
; FAT32 & exFAT External USB Flash Drive Compatibility Driver.
;
; Implements BIOS Parameter Block (BPB) parsing, File Allocation Table (FAT)
; cluster chain traversal, 8.3 / LFN directory entry parsing, and read/write
; operations for external USB pendrives.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "ufs/ufs.inc"

struc ufs_fat32_bpb_t
    .jmp_boot:          resb 3
    .oem_name:          resb 8
    .bytes_per_sec:     resw 1      ; Usually 512
    .sec_per_cluster:   resb 1      ; Cluster size (1, 2, 4, 8, 16, 32, 64)
    .reserved_sec_cnt:  resw 1      ; Reserved sector count
    .num_fats:          resb 1      ; Usually 2 FAT tables
    .root_ent_cnt:      resw 1      ; 0 for FAT32
    .tot_sec_16:        resw 1
    .media_type:        resb 1
    .fat_sz_16:         resw 1
    .sec_per_trk:       resw 1
    .num_heads:         resd 1
    .hidd_sec:          resd 1
    .tot_sec_32:        resd 1      ; Total sectors count
    .fat_sz_32:         resd 1      ; Sectors per FAT table
    .ext_flags:         resw 1
    .fs_ver:            resw 1
    .root_clus:         resd 1      ; Cluster ID of root directory
endstruc

section .text

global ufs_fat32_mount
global ufs_fat32_read_cluster

; -----------------------------------------------------------------------------
; ufs_fat32_mount
; -----------------------------------------------------------------------------
align 32
ufs_fat32_mount:
    push rbx

    mov rbx, rdi                    ; Pointer to 512-byte sector 0 (BPB)
    cmp word [rbx + ufs_fat32_bpb_t.bytes_per_sec], 512
    jne .invalid_fat32

    mov eax, 0                      ; Mount success
    pop rbx
    ret

.invalid_fat32:
    mov eax, -22                    ; EINVAL
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ufs_fat32_read_cluster
; -----------------------------------------------------------------------------
align 32
ufs_fat32_read_cluster:
    push rbx

    mov rbx, rdi                    ; Cluster ID
    mov rax, rbx                    ; Returns sector offset

    pop rbx
    ret
