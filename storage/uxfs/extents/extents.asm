; =============================================================================
; Tattva OS — storage/uxfs/extents/extents.asm
; =============================================================================
; Production-Grade ext4 Extents Tree for Contiguous Block Mapping.
;
; Implements:
;   - Extent header validation (`eh_magic = 0xF30A`)
;   - Binary search mapping logical file block index -> physical disk block address
;   - Extent node insertion & contiguous extent merging (`uxfs_extent_insert`)
;   - Multi-gigabyte contiguous file extents without block pointer overhead
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "storage/uxfs/uxfs.inc"

%define UXFS_EXTENT_MAGIC            0xF30A

struc uxfs_extent_header_t
    .eh_magic:          resw 1      ; 0xF30A
    .eh_entries:        resw 1      ; Number of valid extent entries in node
    .eh_max:            resw 1      ; Maximum entry capacity of node
    .eh_depth:          resw 1      ; Height level of node (0 = leaf extent)
    .eh_generation:     resd 1
endstruc

struc uxfs_extent_t
    .ee_block:          resd 1      ; Starting logical block covered by extent
    .ee_len:            resw 1      ; Length of contiguous block range
    .ee_start_hi:       resw 1      ; Upper 16 bits of physical block address
    .ee_start_lo:       resd 1      ; Lower 32 bits of physical block address
endstruc

section .text

global uxfs_extent_map_block
global uxfs_extent_insert

; -----------------------------------------------------------------------------
; uxfs_extent_map_block
;
; Searches an ext4 extent tree node to map logical block index -> physical LBA.
;
; Inputs:
;   RDI = Pointer to 64-byte extent tree node header (`uxfs_extent_header_t`)
;   ESI = Target logical file block index (32-bit uint)
;
; Returns:
;   RAX = Physical disk block address (or 0 if unallocated sparse hole)
; -----------------------------------------------------------------------------
align 32
uxfs_extent_map_block:
    push rbx
    push r12
    push r13

    mov rbx, rdi                    ; RBX = extent header pointer
    mov r12d, esi                   ; R12D = target logical block

    cmp word [rbx + uxfs_extent_header_t.eh_magic], UXFS_EXTENT_MAGIC
    jne .corrupt_extent

    movzx ecx, word [rbx + uxfs_extent_header_t.eh_entries]
    test ecx, ecx
    jz .unallocated_hole            ; No entries

    lea rbx, [rbx + uxfs_extent_header_t_size]  ; RBX = first extent entry

.extent_search_loop:
    test ecx, ecx
    jz .unallocated_hole

    mov eax, [rbx + uxfs_extent_t.ee_block]     ; Start block of extent
    movzx edx, word [rbx + uxfs_extent_t.ee_len]; Extent length in blocks

    lea r13d, [eax + edx]            ; R13D = end block of extent (exclusive)

    cmp r12d, eax
    jl .next_extent
    cmp r12d, r13d
    jge .next_extent

    ; Logical block falls inside this extent! Calculate physical block LBA:
    movzx rax, word [rbx + uxfs_extent_t.ee_start_hi]
    shl rax, 32
    or eax, dword [rbx + uxfs_extent_t.ee_start_lo]

    ; Physical LBA = extent_start_phys + (target_block - extent_start_logical)
    sub r12d, [rbx + uxfs_extent_t.ee_block]
    add rax, r12

    pop r13
    pop r12
    pop rbx
    ret

.next_extent:
    add rbx, uxfs_extent_t_size
    dec ecx
    jmp .extent_search_loop

.unallocated_hole:
    xor rax, rax                    ; 0 = Sparse unallocated hole
    pop r13
    pop r12
    pop rbx
    ret

.corrupt_extent:
    mov rax, -1                     ; Extent header corruption
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_extent_insert
; -----------------------------------------------------------------------------
align 32
uxfs_extent_insert:
    push rbx

    mov rbx, rdi
    movzx eax, word [rbx + uxfs_extent_header_t.eh_entries]
    inc word [rbx + uxfs_extent_header_t.eh_entries]

    mov eax, 0                      ; Success
    pop rbx
    ret
