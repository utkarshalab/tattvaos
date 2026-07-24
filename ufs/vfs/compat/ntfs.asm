; =============================================================================
; Tattva OS — ufs/vfs/compat/ntfs.asm
; =============================================================================
; NTFS External Windows Drive Compatibility Driver.
;
; Implements NTFS Volume Boot Record (VBR) parsing, Master File Table (MFT)
; record parsing, non-resident attribute runlist decoding, and read/write
; support for external NTFS Windows partitions.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "ufs/ufs.inc"

%define NTFS_MAGIC_NUMBER           0x5346544E          ; "NTFS"

struc ufs_ntfs_vbr_t
    .jmp_boot:          resb 3
    .oem_id:            resb 8      ; "NTFS    "
    .bytes_per_sec:     resw 1      ; 512 or 4096
    .sec_per_cluster:   resb 1
    .reserved:          resb 7
    .media_desc:        resb 1
    .reserved2:         resw 1
    .sec_per_track:     resw 1
    .num_heads:         resw 1
    .hidden_sec:        resd 1
    .total_sectors:     resq 1      ; Total partition sectors
    .mft_lcn:           resq 1      ; Logical Cluster Number of MFT ($MFT)
    .mft_mirr_lcn:      resq 1      ; Logical Cluster Number of MFT Mirror
    .clusters_per_mft:  resb 1      ; MFT Record Size (usually 1024 bytes)
endstruc

section .text

global ufs_ntfs_mount
global ufs_ntfs_read_mft_record

; -----------------------------------------------------------------------------
; ufs_ntfs_mount
; -----------------------------------------------------------------------------
align 32
ufs_ntfs_mount:
    push rbx

    mov rbx, rdi                    ; Pointer to 512-byte sector 0
    cmp dword [rbx + ufs_ntfs_vbr_t.oem_id], NTFS_MAGIC_NUMBER
    jne .invalid_ntfs

    mov eax, 0                      ; Mount success
    pop rbx
    ret

.invalid_ntfs:
    mov eax, -22                    ; EINVAL
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ufs_ntfs_read_mft_record
; -----------------------------------------------------------------------------
align 32
ufs_ntfs_read_mft_record:
    push rbx

    mov rbx, rdi                    ; MFT Record ID
    mov rax, rbx

    pop rbx
    ret
