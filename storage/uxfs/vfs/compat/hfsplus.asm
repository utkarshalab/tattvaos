; =============================================================================
; Tattva OS — storage/uxfs/vfs/compat/hfsplus.asm
; =============================================================================
; Apple HFS+ (Mac OS Extended) Compatibility Driver.
;
; Implements:
;   - Volume header validation at offset 1024 (`uxfs_hfsplus_mount`)
;   - Big-endian field accessors (`uxfs_hfsplus_be16/be32/be64`)
;   - Catalog B-tree node parsing (`uxfs_hfsplus_parse_catalog_node`)
;   - Catalog key comparison (`uxfs_hfsplus_compare_key`)
;   - Extent record resolution (`uxfs_hfsplus_extent_lookup`)
;
; HFS+ is BIG-ENDIAN throughout, a legacy of its 68k and PowerPC origins.
; Every multi-byte field must be byte-swapped on x86 — including the "H+"
; signature itself, which is 0x482B on disk. Forgetting one swap somewhere
; deep in the catalog tree is the characteristic HFS+ bug, because the volume
; still mounts and only some lookups misbehave.
;
; The volume header lives 1024 bytes in, leaving room for boot blocks.
;
; Catalog records are keyed by parent directory ID plus a Unicode name, so a
; lookup walks the B-tree comparing parent ID first and only then the name.
; That ordering is what makes a directory listing a contiguous key range.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "storage/uxfs/uxfs.inc"

%define HFSPLUS_MAGIC               0x2B48      ; "H+" after byte swap
%define HFSPLUSX_MAGIC              0x5848      ; "HX" case-sensitive variant
%define HFSPLUS_VH_OFFSET           1024        ; Volume header past boot blocks
%define HFSPLUS_MAX_NAME            255

; B-tree node kinds.
%define HFSPLUS_NODE_LEAF           0xFF        ; -1 as a signed byte
%define HFSPLUS_NODE_INDEX          0x00
%define HFSPLUS_NODE_HEADER         0x01
%define HFSPLUS_NODE_MAP            0x02

; Catalog record types, stored big-endian.
%define HFSPLUS_FOLDER_RECORD       0x0001
%define HFSPLUS_FILE_RECORD         0x0002
%define HFSPLUS_FOLDER_THREAD       0x0003
%define HFSPLUS_FILE_THREAD         0x0004

; Well-known catalog node IDs.
%define HFSPLUS_ROOT_PARENT_ID      1
%define HFSPLUS_ROOT_FOLDER_ID      2
%define HFSPLUS_EXTENTS_FILE_ID     3
%define HFSPLUS_CATALOG_FILE_ID     4

struc uxfs_hfsplus_volume_header_t
    .signature:         resw 1      ; "H+" / "HX", big-endian
    .version:           resw 1
    .attributes:        resd 1
    .last_mounted_version: resd 1
    .journal_info_block: resd 1
    .create_date:       resd 1
    .modify_date:       resd 1
    .backup_date:       resd 1
    .checked_date:      resd 1
    .file_count:        resd 1
    .folder_count:      resd 1
    .block_size:        resd 1      ; Allocation block size
    .total_blocks:      resd 1
    .free_blocks:       resd 1
endstruc

struc uxfs_hfsplus_btree_node_descriptor_t
    .flink:             resd 1      ; Next node id, big-endian
    .blink:             resd 1      ; Previous node id, big-endian
    .kind:              resb 1      ; HFSPLUS_NODE_*
    .height:            resb 1
    .num_records:       resw 1      ; Record count, big-endian
    .reserved:          resw 1
endstruc

; Catalog key: parent id plus a UTF-16 name.
struc uxfs_hfsplus_catalog_key_t
    .key_length:        resw 1      ; Big-endian
    .parent_id:         resd 1      ; Big-endian catalog node id
    .name_length:       resw 1      ; UTF-16 code unit count, big-endian
endstruc

; One extent descriptor: an allocation block run.
struc uxfs_hfsplus_extent_t
    .start_block:       resd 1      ; Big-endian
    .block_count:       resd 1      ; Big-endian
endstruc

section .data
align 64

global uxfs_hfsplus_block_size
uxfs_hfsplus_block_size:    dd 0
uxfs_hfsplus_total_blocks:  dd 0
uxfs_hfsplus_case_sensitive: dd 0
uxfs_hfsplus_mounted:       dd 0
uxfs_hfsplus_lookups:       dq 0

section .text

global uxfs_hfsplus_mount
global uxfs_hfsplus_parse_catalog_node
global uxfs_hfsplus_be16
global uxfs_hfsplus_be32
global uxfs_hfsplus_be64
global uxfs_hfsplus_compare_key
global uxfs_hfsplus_extent_lookup

; -----------------------------------------------------------------------------
; uxfs_hfsplus_be16
;
; Inputs:
;   RDI = Pointer to a big-endian 16-bit field
;
; Returns:
;   EAX = Host-order value
; -----------------------------------------------------------------------------
align 32
uxfs_hfsplus_be16:
    movzx eax, word [rdi]
    xchg al, ah
    ret

; -----------------------------------------------------------------------------
; uxfs_hfsplus_be32
;
; Inputs:
;   RDI = Pointer to a big-endian 32-bit field
;
; Returns:
;   EAX = Host-order value
; -----------------------------------------------------------------------------
align 32
uxfs_hfsplus_be32:
    mov eax, dword [rdi]
    bswap eax
    ret

; -----------------------------------------------------------------------------
; uxfs_hfsplus_be64
;
; Inputs:
;   RDI = Pointer to a big-endian 64-bit field
;
; Returns:
;   RAX = Host-order value
; -----------------------------------------------------------------------------
align 32
uxfs_hfsplus_be64:
    mov rax, [rdi]
    bswap rax
    ret

; -----------------------------------------------------------------------------
; uxfs_hfsplus_mount
;
; Validates the volume header and records the allocation geometry.
;
; Inputs:
;   RDI = Pointer to a buffer holding at least HFSPLUS_VH_OFFSET + 512 bytes
;         from the start of the volume
;
; Returns:
;   EAX = 0 on success
;         POSIX_EIO on a bad signature or zero block size
;         POSIX_EINVAL on a null argument
; -----------------------------------------------------------------------------
align 32
uxfs_hfsplus_mount:
    push rbx
    push r12

    test rdi, rdi
    jz .hm_inval

    ; The header sits past the boot blocks, not at offset zero.
    lea rbx, [rdi + HFSPLUS_VH_OFFSET]

    ; Signature is big-endian, so swap before comparing.
    lea rdi, [rbx + uxfs_hfsplus_volume_header_t.signature]
    call uxfs_hfsplus_be16

    cmp eax, HFSPLUS_MAGIC
    je .hm_case_insensitive
    cmp eax, HFSPLUSX_MAGIC
    je .hm_case_sensitive
    jmp .hm_badvol

.hm_case_sensitive:
    mov dword [uxfs_hfsplus_case_sensitive], 1
    jmp .hm_geometry

.hm_case_insensitive:
    mov dword [uxfs_hfsplus_case_sensitive], 0

.hm_geometry:
    lea rdi, [rbx + uxfs_hfsplus_volume_header_t.block_size]
    call uxfs_hfsplus_be32
    test eax, eax
    jz .hm_badvol                   ; A zero block size divides by zero later

    ; Allocation block size must be a power of two.
    mov ecx, eax
    dec ecx
    test eax, ecx
    jnz .hm_badvol

    mov dword [uxfs_hfsplus_block_size], eax

    lea rdi, [rbx + uxfs_hfsplus_volume_header_t.total_blocks]
    call uxfs_hfsplus_be32
    mov dword [uxfs_hfsplus_total_blocks], eax

    mov dword [uxfs_hfsplus_mounted], 1

    xor eax, eax
    pop r12
    pop rbx
    ret

.hm_badvol:
    mov eax, POSIX_EIO
    pop r12
    pop rbx
    ret

.hm_inval:
    mov eax, POSIX_EINVAL
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_hfsplus_parse_catalog_node
;
; Reads a B-tree node descriptor and reports its kind and record count.
;
; Inputs:
;   RDI = Pointer to the node
;   RSI = Pointer to a dword receiving the record count
;   RDX = Pointer to a dword receiving the node kind
;
; Returns:
;   EAX = 0 on success, POSIX_EIO on an implausible descriptor
; -----------------------------------------------------------------------------
align 32
uxfs_hfsplus_parse_catalog_node:
    push rbx
    push r12
    push r13

    test rdi, rdi
    jz .pc_inval
    test rsi, rsi
    jz .pc_inval
    test rdx, rdx
    jz .pc_inval

    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx

    movzx eax, byte [rbx + uxfs_hfsplus_btree_node_descriptor_t.kind]

    ; Only the four defined node kinds are acceptable.
    cmp eax, HFSPLUS_NODE_LEAF
    je .pc_kind_ok
    cmp eax, HFSPLUS_NODE_MAP
    jbe .pc_kind_ok
    jmp .pc_corrupt

.pc_kind_ok:
    mov dword [r13], eax

    lea rdi, [rbx + uxfs_hfsplus_btree_node_descriptor_t.num_records]
    call uxfs_hfsplus_be16

    ; A node cannot hold more records than its smallest possible entries.
    cmp eax, 1024
    ja .pc_corrupt

    mov dword [r12], eax

    xor eax, eax
    pop r13
    pop r12
    pop rbx
    ret

.pc_corrupt:
    mov eax, POSIX_EIO
    pop r13
    pop r12
    pop rbx
    ret

.pc_inval:
    mov eax, POSIX_EINVAL
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_hfsplus_compare_key
;
; Orders two catalog keys: parent id first, then name length as a tiebreak.
;
; Parent id dominates because it is what groups a directory's children into
; one contiguous key range — comparing names first would scatter them.
;
; Inputs:
;   RDI = Pointer to catalog key A
;   RSI = Pointer to catalog key B
;
; Returns:
;   EAX = -1 when A < B, 0 when equal, 1 when A > B
; -----------------------------------------------------------------------------
align 32
uxfs_hfsplus_compare_key:
    push rbx
    push r12
    push r13

    mov rbx, rdi
    mov r12, rsi

    lea rdi, [rbx + uxfs_hfsplus_catalog_key_t.parent_id]
    call uxfs_hfsplus_be32
    mov r13d, eax

    lea rdi, [r12 + uxfs_hfsplus_catalog_key_t.parent_id]
    call uxfs_hfsplus_be32

    cmp r13d, eax
    jb .ck_less
    ja .ck_greater

    ; Same parent: fall back to name length.
    lea rdi, [rbx + uxfs_hfsplus_catalog_key_t.name_length]
    call uxfs_hfsplus_be16
    mov r13d, eax

    lea rdi, [r12 + uxfs_hfsplus_catalog_key_t.name_length]
    call uxfs_hfsplus_be16

    cmp r13d, eax
    jb .ck_less
    ja .ck_greater

    xor eax, eax
    pop r13
    pop r12
    pop rbx
    ret

.ck_less:
    mov eax, -1
    pop r13
    pop r12
    pop rbx
    ret

.ck_greater:
    mov eax, 1
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_hfsplus_extent_lookup
;
; Maps a file-relative block index onto an allocation block, walking the eight
; inline extent descriptors a fork record carries.
;
; A file needing more than eight extents spills into the extents overflow
; file; this reports ENOENT for that case rather than returning a wrong block.
;
; Inputs:
;   RDI = Pointer to the extent record, eight uxfs_hfsplus_extent_t entries
;   RSI = File-relative block index
;
; Returns:
;   RAX = Absolute allocation block, or POSIX_ENOENT when past the inline set
; -----------------------------------------------------------------------------
align 32
uxfs_hfsplus_extent_lookup:
    push rbx
    push r12
    push r13
    push r14

    mov rbx, rdi                    ; Extent array
    mov r12, rsi                    ; Wanted block index
    xor r13d, r13d                  ; Extent index
    xor r14, r14                    ; Blocks covered so far

.el_loop:
    cmp r13d, 8
    jae .el_overflow

    mov rax, r13
    imul rax, uxfs_hfsplus_extent_t_size
    lea rdi, [rbx + rax]
    push rdi
    add rdi, uxfs_hfsplus_extent_t.block_count
    call uxfs_hfsplus_be32
    mov ecx, eax                    ; Block count for this extent
    pop rdi

    test ecx, ecx
    jz .el_overflow                 ; Zero-length extent ends the record

    ; Does the wanted index fall inside this run?
    mov rax, r14
    add rax, rcx
    cmp r12, rax
    jae .el_next

    ; Yes: start block plus the offset into this run.
    push rcx
    call uxfs_hfsplus_be32          ; RDI still points at start_block
    pop rcx

    mov rdx, r12
    sub rdx, r14                    ; Offset within the extent
    add rax, rdx

    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.el_next:
    add r14, rcx
    inc r13d
    jmp .el_loop

.el_overflow:
    ; Beyond the inline extents: the extents overflow file holds the rest.
    mov rax, POSIX_ENOENT
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
