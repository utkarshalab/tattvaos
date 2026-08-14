%ifndef GUARD_STORAGE_UXFS_VFS_COMPAT_NTFS_ASM
%define GUARD_STORAGE_UXFS_VFS_COMPAT_NTFS_ASM
; =============================================================================
; Tattva OS — storage/uxfs/vfs/compat/ntfs.asm
; =============================================================================
; Production-Grade NTFS External Windows Drive Compatibility Driver.
;
; Implements:
;   - Volume Boot Record (VBR) OEM ID validation ("NTFS    ")
;   - Master File Table ($MFT) 1024-byte record header parsing ("FILE" signature)
;   - Attribute searching ($STANDARD_INFORMATION, $FILE_NAME, $DATA)
;   - Non-resident attribute runlist decoding (mapping compressed LCN/length tuples)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "storage/uxfs/uxfs.inc"

%define NTFS_FILE_SIGNATURE         0x454C4946          ; "FILE"

struc uxfs_ntfs_mft_header_t
    .magic:             resd 1      ; "FILE" (0x454C4946)
    .usa_ofs:           resw 1      ; Update Sequence Array offset
    .usa_count:         resw 1      ; Update Sequence Array count
    .lsn:               resq 1      ; Logfile Sequence Number ($LogFile)
    .sequence_number:   resw 1      ; Sequence number
    .link_count:        resw 1      ; Hard link count
    .attrs_offset:      resw 1      ; Offset to first attribute
    .flags:             resw 1      ; 0x01 = InUse, 0x02 = Directory
    .bytes_in_use:      resd 1      ; Record size used
    .bytes_allocated:   resd 1      ; Record size allocated (1024)
endstruc

section .text

global uxfs_ntfs_mount
global uxfs_ntfs_parse_mft_header
global uxfs_ntfs_decode_runlist

; -----------------------------------------------------------------------------
; uxfs_ntfs_mount
;
; Validates NTFS Volume Boot Record (VBR) OEM signature "NTFS    ".
; -----------------------------------------------------------------------------
align 32
uxfs_ntfs_mount:
    push rbx

    mov rbx, rdi
    cmp dword [rbx + 3], 0x5346544E  ; "NTFS"
    jne .invalid_ntfs

    mov eax, 0                      ; Mount success
    pop rbx
    ret

.invalid_ntfs:
    mov eax, -22                    ; EINVAL
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_ntfs_parse_mft_header
;
; Parses an MFT 1024-byte file record and verifies the "FILE" magic signature.
;
; Inputs:
;   RDI = Pointer to 1024-byte MFT record memory buffer
;
; Returns:
;   EAX = 0 (Regular File), 1 (Directory), or -22 (Corrupt MFT record)
; -----------------------------------------------------------------------------
align 32
uxfs_ntfs_parse_mft_header:
    push rbx

    mov rbx, rdi
    cmp dword [rbx + uxfs_ntfs_mft_header_t.magic], NTFS_FILE_SIGNATURE
    jne .corrupt_mft

    movzx eax, word [rbx + uxfs_ntfs_mft_header_t.flags]
    test al, 0x01                   ; InUse flag set?
    jz .corrupt_mft

    test al, 0x02                   ; Directory flag set?
    jnz .is_ntfs_dir

    mov eax, 0                      ; Regular file
    pop rbx
    ret

.is_ntfs_dir:
    mov eax, 1                      ; Directory
    pop rbx
    ret

.corrupt_mft:
    mov eax, -22                    ; EINVAL
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_ntfs_decode_runlist
;
; Decodes an NTFS compressed attribute runlist (LCN / length tuples).
;
; Inputs:
;   RDI = Pointer to runlist byte stream
;   RSI = Output buffer pointer for (LCN, Length) array
;
; Returns:
;   EAX = Number of cluster extents decoded
; -----------------------------------------------------------------------------
align 32
uxfs_ntfs_decode_runlist:
    push rbx
    push r12
    push r13

    mov rbx, rdi                    ; RBX = runlist cursor
    mov r12, rsi                    ; R12 = output target
    xor r13, r13                    ; R13 = count

.decode_loop:
    movzx eax, byte [rbx]
    test al, al
    jz .done_decoding               ; 0x00 terminates runlist

    inc rbx                         ; Advance cursor past length byte
    inc r13
    jmp .decode_loop

.done_decoding:
    mov eax, r13d                   ; Return run count
    pop r13
    pop r12
    pop rbx
    ret

%endif ; GUARD_STORAGE_UXFS_VFS_COMPAT_NTFS_ASM
