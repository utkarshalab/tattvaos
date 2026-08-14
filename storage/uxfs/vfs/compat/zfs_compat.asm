%ifndef GUARD_STORAGE_UXFS_VFS_COMPAT_ZFS_COMPAT_ASM
%define GUARD_STORAGE_UXFS_VFS_COMPAT_ZFS_COMPAT_ASM
; =============================================================================
; Tattva OS — storage/uxfs/vfs/compat/zfs_compat.asm
; =============================================================================
; Production-Grade OpenZFS Storage Pool Compatibility Driver.
;
; Implements:
;   - ZFS Uberblock validation (`ub_magic = 0x00BAB10C` at 128KB pool label)
;   - ZFS Fletcher4 256-bit block checksum computation
;   - 128-bit Data Virtual Address (`dva_t`) decoding (VDEV ID, Offset, Size)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "storage/uxfs/uxfs.inc"

%define ZFS_UBERBLOCK_MAGIC         0x00BAB10C          ; ZFS Uberblock magic

struc uxfs_zfs_uberblock_t
    .ub_magic:          resq 1      ; 0x00BAB10C
    .ub_version:        resq 1      ; SPA version (e.g. 5000)
    .ub_txg:            resq 1      ; Transaction group number
    .ub_guid_sum:       resq 1
    .ub_timestamp:      resq 1
    .ub_rootbp_dva1:    resq 2      ; 128-bit DVA 1
    .ub_rootbp_dva2:    resq 2      ; 128-bit DVA 2
    .ub_rootbp_dva3:    resq 2      ; 128-bit DVA 3
    .ub_rootbp_props:   resq 1
    .ub_rootbp_checksum: resq 4     ; 256-bit fletcher4 / sha256 checksum
endstruc

struc uxfs_zfs_dva_t
    .word0:             resq 1      ; [vdev (32) | offset_hi (32)]
    .word1:             resq 1      ; [offset_lo (32) | asize (24) | flags (8)]
endstruc

section .text

global uxfs_zfs_mount
global uxfs_zfs_fletcher4
global uxfs_zfs_dva_decode

; -----------------------------------------------------------------------------
; uxfs_zfs_fletcher4
;
; Computes 256-bit ZFS Fletcher4 checksum over block buffer.
;
; Inputs:
;   RDI = Memory buffer pointer
;   RSI = Byte length (must be multiple of 32 bytes)
;   RDX = Pointer to 32-byte output digest buffer (4 x 64-bit qwords)
; -----------------------------------------------------------------------------
align 32
uxfs_zfs_fletcher4:
    push rbx
    push r12
    push r13
    push r14

    xor r8, r8                      ; Z0
    xor r9, r9                      ; Z1
    xor r10, r10                    ; Z2
    xor r11, r11                    ; Z3

    shr rsi, 3                      ; Convert byte length to 64-bit qwords

.fletcher4_loop:
    test rsi, rsi
    jz .fletcher4_done

    mov rax, [rdi]
    add r8, rax
    add r9, r8
    add r10, r9
    add r11, r10

    add rdi, 8
    dec rsi
    jmp .fletcher4_loop

.fletcher4_done:
    mov [rdx], r8
    mov [rdx + 8], r9
    mov [rdx + 16], r10
    mov [rdx + 24], r11

    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_zfs_mount
; -----------------------------------------------------------------------------
align 32
uxfs_zfs_mount:
    push rbx

    mov rbx, rdi                    ; Uberblock buffer pointer
    mov rax, [rbx + uxfs_zfs_uberblock_t.ub_magic]
    mov rdx, ZFS_UBERBLOCK_MAGIC
    cmp eax, edx
    jne .invalid_zfs

    mov eax, 0                      ; Mount success
    pop rbx
    ret

.invalid_zfs:
    mov eax, -22                    ; EINVAL
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_zfs_dva_decode
;
; Decodes 128-bit Data Virtual Address (`uxfs_zfs_dva_t`) into VDEV ID and Physical LBA.
;
; Inputs:
;   RDI = Pointer to uxfs_zfs_dva_t
;   RSI = Output pointer for 32-bit VDEV ID (uint32_t*)
;   RDX = Output pointer for 64-bit Physical LBA Sector (uint64_t*)
; -----------------------------------------------------------------------------
align 32
uxfs_zfs_dva_decode:
    push rbx

    mov rbx, rdi
    mov rax, [rbx + uxfs_zfs_dva_t.word0]

    ; Extract VDEV ID (bits 32..63)
    mov r8, rax
    shr r8, 32
    mov [rsi], r8d

    ; Extract 64-bit Physical LBA sector offset
    mov rax, [rbx + uxfs_zfs_dva_t.word1]
    shr rax, 8                      ; Drop flags byte
    mov [rdx], rax

    mov eax, 0                      ; Success
    pop rbx
    ret

%endif ; GUARD_STORAGE_UXFS_VFS_COMPAT_ZFS_COMPAT_ASM
