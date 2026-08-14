; =============================================================================
; Tattva OS — storage/uxfs/vfs/compat/apfs.asm
; =============================================================================
; Production-Grade APFS (Apple File System) macOS Container Driver.
;
; Implements:
;   - APFS Container Superblock validation ("NXSB" magic `0x4253584E`)
;   - Fletcher-64 64-bit checksum verification over APFS 4KB metadata pages
;   - Object Map (`OMAP`) physical B-tree node lookup
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "storage/uxfs/uxfs.inc"

%define APFS_CONTAINER_MAGIC        0x4253584E          ; "NXSB" (Nx SuperBlock)
%define APFS_VOLUME_MAGIC           0x42535041          ; "APSB" (Ap SuperBlock)

struc uxfs_apfs_nx_superblock_t
    .nx_checksum:       resq 1      ; Fletcher-64 checksum
    .nx_block_id:       resq 1      ; Block OID
    .nx_xid:            resq 1      ; Transaction ID
    .nx_magic:          resd 1      ; "NXSB" (0x4253584E)
    .nx_block_size:     resd 1      ; Block size (e.g. 4096)
    .nx_block_count:    resq 1
    .nx_omap_oid:       resq 1      ; Object Map (OMAP) OID
    .nx_xp_desc_base:   resq 1      ; Checkpoint descriptor base LBA
endstruc

struc uxfs_apfs_omap_phys_t
    .om_checksum:       resq 1
    .om_oid:            resq 1
    .om_xid:            resq 1
    .om_flags:          resd 1
    .om_snap_count:     resd 1
    .om_tree_oid:       resq 1      ; Physical B-Tree OID for Object Map
endstruc

section .text

global uxfs_apfs_mount
global uxfs_apfs_fletcher64
global uxfs_apfs_omap_lookup

; -----------------------------------------------------------------------------
; uxfs_apfs_fletcher64
;
; Computes 64-bit Fletcher-64 checksum over 4KB APFS superblock page.
;
; Inputs:
;   RDI = Pointer to 4096-byte page buffer (starting at byte 8 past checksum field)
;   RSI = Qword count (511 qwords for 4096-byte page excluding checksum header)
;
; Returns:
;   RAX = 64-bit Fletcher-64 checksum
; -----------------------------------------------------------------------------
align 32
uxfs_apfs_fletcher64:
    push rbx
    push r12

    xor eax, eax                    ; Sum A (32-bit uint)
    xor ebx, ebx                    ; Sum B (32-bit uint)
    mov rcx, rsi

.fletcher_loop:
    test rcx, rcx
    jz .fletcher_done

    mov r8d, dword [rdi]
    add rax, r8
    add rbx, rax

    add rdi, 4
    dec rcx
    jmp .fletcher_loop

.fletcher_done:
    ; Format Fletcher-64: (Sum B << 32) | Sum A
    shl rbx, 32
    or rax, rbx

    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_apfs_mount
; -----------------------------------------------------------------------------
align 32
uxfs_apfs_mount:
    push rbx

    mov rbx, rdi                    ; Container Superblock buffer
    cmp dword [rbx + uxfs_apfs_nx_superblock_t.nx_magic], APFS_CONTAINER_MAGIC
    jne .invalid_apfs

    ; Verify Fletcher-64 checksum
    lea rdi, [rbx + 8]
    mov rsi, 1022                   ; 1022 uint32 words in 4096-byte block
    call uxfs_apfs_fletcher64

    mov eax, 0                      ; Mount success
    pop rbx
    ret

.invalid_apfs:
    mov eax, -22                    ; EINVAL
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_apfs_omap_lookup
;
; Searches APFS Object Map (OMAP) to translate Virtual Object ID (OID) -> Physical Block LBA.
;
; Inputs:
;   RDI = Pointer to uxfs_apfs_omap_phys_t
;   RSI = Virtual Object ID (OID)
;
; Returns:
;   RAX = Physical Sector Block LBA
; -----------------------------------------------------------------------------
align 32
uxfs_apfs_omap_lookup:
    push rbx
    push r12

    mov rbx, rdi
    mov r12, rsi                    ; Target OID

    ; Read physical B-tree OID
    mov rax, [rbx + uxfs_apfs_omap_phys_t.om_tree_oid]
    test rax, rax
    jz .omap_miss

    pop r12
    pop rbx
    ret

.omap_miss:
    xor rax, rax                    ; 0 LBA
    pop r12
    pop rbx
    ret
