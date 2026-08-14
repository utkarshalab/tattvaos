%ifndef GUARD_STORAGE_UXFS_COMPRESS_EROFS_ASM
%define GUARD_STORAGE_UXFS_COMPRESS_EROFS_ASM
; =============================================================================
; Tattva OS — storage/uxfs/compress/erofs.asm
; =============================================================================
; EROFS (Enhanced Read-Only File System) Compatibility Driver.
;
; Implements:
;   - Superblock validation at the 1KB offset (`uxfs_erofs_mount`)
;   - Compact and extended inode decoding (`uxfs_erofs_read_inode`)
;   - NID to disk address translation (`uxfs_erofs_nid_to_addr`)
;   - Uncompressed and LZ4-compressed block reads (`uxfs_erofs_read_block`)
;
; EROFS is the read-only image format Android and container runtimes use. Two
; of its design choices shape this driver.
;
; The superblock lives at byte offset 1024, not 0, leaving room for a boot
; sector — the same convention ext4 uses. Reading block 0 and expecting a
; magic there finds nothing.
;
; Inodes come in two widths. A compact inode is 32 bytes with 32-bit
; timestamps and a 16-bit link count; an extended inode is 64 bytes with
; 64-bit sizes. The format bits in the first field say which, and mis-reading
; one as the other yields plausible-looking garbage rather than an error.
;
; NIDs are not byte offsets. A NID is an index scaled by 32 bytes from
; meta_blkaddr, so the translation must be applied before any inode read.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "storage/uxfs/uxfs.inc"

%define EROFS_MAGIC_NUMBER          0xE0F5E1E2
%define EROFS_SUPER_OFFSET          1024        ; Superblock sits after the boot sector
%define EROFS_BLOCK_SIZE            4096
%define EROFS_INODE_SLOT_SIZE       32          ; NID scaling unit

; Inode layout selector, held in the low bit of i_format.
%define EROFS_INODE_LAYOUT_COMPACT  0
%define EROFS_INODE_LAYOUT_EXTENDED 1

; Data layout, bits 1..3 of i_format.
%define EROFS_INODE_FLAT_PLAIN          0   ; Contiguous, uncompressed
%define EROFS_INODE_FLAT_COMPRESSION_LEGACY 1
%define EROFS_INODE_FLAT_INLINE         2   ; Tail packed into the inode block
%define EROFS_INODE_CHUNK_BASED         4

%define EROFS_FORMAT_LAYOUT_MASK    0x0E
%define EROFS_FORMAT_LAYOUT_SHIFT   1

struc uxfs_erofs_super_block_t
    .magic:             resd 1      ; EROFS_MAGIC_NUMBER
    .checksum:          resd 1
    .feature_compat:    resd 1
    .blkszbits:         resb 1      ; log2 of block size; 12 = 4KB
    .sb_extslots:       resb 1
    .root_nid:          resw 1      ; Root directory node id
    .inos:              resq 1
    .build_time:        resq 1
    .build_time_nsec:   resd 1
    .blocks:            resd 1
    .meta_blkaddr:      resd 1      ; Base block for inode translation
    .xattr_blkaddr:     resd 1
    .volume_name:       resb 16
endstruc

; 32-byte compact inode.
struc uxfs_erofs_inode_compact_t
    .i_format:          resw 1      ; Layout selector and data layout
    .i_xattr_icount:    resw 1
    .i_mode:            resw 1
    .i_nlink:           resw 1
    .i_size:            resd 1      ; 32-bit: compact inodes cap at 4GB
    .i_reserved:        resd 1
    .i_u:               resd 1      ; Raw block address or chunk info
    .i_ino:             resd 1
    .i_uid:             resw 1
    .i_gid:             resw 1
    .i_reserved2:       resd 1
endstruc

; 64-byte extended inode.
struc uxfs_erofs_inode_extended_t
    .i_format:          resw 1
    .i_xattr_icount:    resw 1
    .i_mode:            resw 1
    .i_reserved:        resw 1
    .i_size:            resq 1      ; Full 64-bit size
    .i_u:               resd 1
    .i_ino:             resd 1
    .i_uid:             resd 1
    .i_gid:             resd 1
    .i_mtime:           resq 1
    .i_mtime_nsec:      resd 1
    .i_nlink:           resd 1
    .i_reserved2:       resb 16
endstruc

section .data
align 64

global uxfs_erofs_meta_blkaddr
uxfs_erofs_meta_blkaddr:    dd 0
uxfs_erofs_root_nid:        dd 0
uxfs_erofs_block_size:      dd EROFS_BLOCK_SIZE
uxfs_erofs_mounted:         dd 0

uxfs_erofs_reads:           dq 0
uxfs_erofs_decompressions:  dq 0

section .text

global uxfs_erofs_mount
global uxfs_erofs_read_block
global uxfs_erofs_read_inode
global uxfs_erofs_nid_to_addr
global uxfs_erofs_inode_size

; -----------------------------------------------------------------------------
; uxfs_erofs_mount
;
; Validates an EROFS superblock and caches the fields later reads depend on.
;
; Inputs:
;   RDI = Pointer to a buffer holding at least EROFS_SUPER_OFFSET + 128 bytes
;         from the start of the volume
;
; Returns:
;   EAX = 0 on success
;         POSIX_EINVAL on a null argument
;         POSIX_EIO    on a bad magic or unsupported block size
; -----------------------------------------------------------------------------
align 32
uxfs_erofs_mount:
    push rbx

    test rdi, rdi
    jz .em_inval

    ; The superblock is 1KB into the volume, not at offset zero.
    lea rbx, [rdi + EROFS_SUPER_OFFSET]

    cmp dword [rbx + uxfs_erofs_super_block_t.magic], EROFS_MAGIC_NUMBER
    jne .em_badmagic

    ; Only 4KB blocks are supported; blkszbits is a log2 exponent.
    movzx eax, byte [rbx + uxfs_erofs_super_block_t.blkszbits]
    cmp eax, 12
    jne .em_badmagic

    mov eax, dword [rbx + uxfs_erofs_super_block_t.meta_blkaddr]
    mov dword [uxfs_erofs_meta_blkaddr], eax

    movzx eax, word [rbx + uxfs_erofs_super_block_t.root_nid]
    mov dword [uxfs_erofs_root_nid], eax

    mov dword [uxfs_erofs_block_size], EROFS_BLOCK_SIZE
    mov dword [uxfs_erofs_mounted], 1

    xor eax, eax
    pop rbx
    ret

.em_badmagic:
    mov eax, POSIX_EIO
    pop rbx
    ret

.em_inval:
    mov eax, POSIX_EINVAL
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_erofs_nid_to_addr
;
; Converts a node id into an absolute byte offset.
;
; A NID indexes 32-byte slots relative to meta_blkaddr, so it must be scaled
; and rebased rather than used directly as an offset.
;
; Inputs:
;   RDI = Node id
;
; Returns:
;   RAX = Absolute byte offset of the inode
; -----------------------------------------------------------------------------
align 32
uxfs_erofs_nid_to_addr:
    mov eax, dword [uxfs_erofs_meta_blkaddr]
    shl rax, 12                     ; Block address -> byte offset
    mov rcx, rdi
    shl rcx, 5                      ; NID -> byte offset, 32 bytes per slot
    add rax, rcx
    ret

; -----------------------------------------------------------------------------
; uxfs_erofs_inode_size
;
; Reports an inode's file size, honouring the compact/extended split.
;
; Inputs:
;   RDI = Pointer to the on-disk inode
;
; Returns:
;   RAX = File size in bytes
; -----------------------------------------------------------------------------
align 32
uxfs_erofs_inode_size:
    movzx eax, word [rdi + uxfs_erofs_inode_compact_t.i_format]
    test eax, EROFS_INODE_LAYOUT_EXTENDED
    jnz .is_extended

    ; Compact: 32-bit size, zero-extended.
    mov eax, dword [rdi + uxfs_erofs_inode_compact_t.i_size]
    ret

.is_extended:
    mov rax, [rdi + uxfs_erofs_inode_extended_t.i_size]
    ret

; -----------------------------------------------------------------------------
; uxfs_erofs_read_inode
;
; Decodes an inode into a caller-supplied uxfs_inode_t.
;
; Inputs:
;   RDI = Pointer to the on-disk inode
;   RSI = Pointer to a uxfs_inode_t output
;
; Returns:
;   EAX = 0 on success, POSIX_EINVAL on a null argument
; -----------------------------------------------------------------------------
align 32
uxfs_erofs_read_inode:
    push rbx
    push r12

    test rdi, rdi
    jz .ri_inval
    test rsi, rsi
    jz .ri_inval

    mov rbx, rdi
    mov r12, rsi

    movzx eax, word [rbx + uxfs_erofs_inode_compact_t.i_format]
    test eax, EROFS_INODE_LAYOUT_EXTENDED
    jnz .ri_extended

    ; ---- Compact inode ----
    movzx eax, word [rbx + uxfs_erofs_inode_compact_t.i_mode]
    mov dword [r12 + uxfs_inode_t.mode_permissions], eax

    mov eax, dword [rbx + uxfs_erofs_inode_compact_t.i_ino]
    mov [r12 + uxfs_inode_t.inode_id], rax

    movzx eax, word [rbx + uxfs_erofs_inode_compact_t.i_uid]
    mov dword [r12 + uxfs_inode_t.uid], eax
    movzx eax, word [rbx + uxfs_erofs_inode_compact_t.i_gid]
    mov dword [r12 + uxfs_inode_t.gid], eax

    jmp .ri_common

.ri_extended:
    movzx eax, word [rbx + uxfs_erofs_inode_extended_t.i_mode]
    mov dword [r12 + uxfs_inode_t.mode_permissions], eax

    mov eax, dword [rbx + uxfs_erofs_inode_extended_t.i_ino]
    mov [r12 + uxfs_inode_t.inode_id], rax

    mov eax, dword [rbx + uxfs_erofs_inode_extended_t.i_uid]
    mov dword [r12 + uxfs_inode_t.uid], eax
    mov eax, dword [rbx + uxfs_erofs_inode_extended_t.i_gid]
    mov dword [r12 + uxfs_inode_t.gid], eax

.ri_common:
    ; EROFS images are read-only by construction.
    mov dword [r12 + uxfs_inode_t.type_flags], 0

    xor eax, eax
    pop r12
    pop rbx
    ret

.ri_inval:
    mov eax, POSIX_EINVAL
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_erofs_read_block
;
; Reads one logical block, decompressing when the inode's data layout says so.
;
; Inputs:
;   RDI = Pointer to the source block
;   RSI = Pointer to a 4KB destination buffer
;   EDX = Source byte length
;   ECX = Data layout from i_format (EROFS_INODE_FLAT_*)
;
; Returns:
;   RAX = Bytes produced, or a negative POSIX error
; -----------------------------------------------------------------------------
align 32
uxfs_erofs_read_block:
    push rbx
    push r12
    push r13
    push r14

    mov rbx, rdi                    ; Source
    mov r12, rsi                    ; Destination
    mov r13d, edx                   ; Source length
    mov r14d, ecx                   ; Layout

    test rbx, rbx
    jz .rb_inval
    test r12, r12
    jz .rb_inval
    test r13d, r13d
    jz .rb_inval
    cmp r13d, EROFS_BLOCK_SIZE
    ja .rb_inval

    cmp r14d, EROFS_INODE_FLAT_COMPRESSION_LEGACY
    je .rb_compressed

    ; ---- Plain or inline: straight copy ----
    mov rdi, r12
    mov rsi, rbx
    mov ecx, r13d
    rep movsb

    inc qword [uxfs_erofs_reads]
    mov rax, r13
    jmp .rb_return

.rb_compressed:
    ; EROFS clusters use LZ4 with a fixed 4KB output window.
    mov rdi, rbx
    mov rsi, r13
    mov rdx, r12
    mov rcx, EROFS_BLOCK_SIZE
    call ucmp_lz4_decompress
    test rax, rax
    js .rb_corrupt

    inc qword [uxfs_erofs_decompressions]
    inc qword [uxfs_erofs_reads]
    jmp .rb_return

.rb_corrupt:
    mov rax, POSIX_EIO
    jmp .rb_return

.rb_inval:
    mov rax, POSIX_EINVAL

.rb_return:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

%endif ; GUARD_STORAGE_UXFS_COMPRESS_EROFS_ASM
