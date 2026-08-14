%ifndef GUARD_STORAGE_UXFS_VFS_COMPAT_SQUASHFS_ASM
%define GUARD_STORAGE_UXFS_VFS_COMPAT_SQUASHFS_ASM
; =============================================================================
; Tattva OS — storage/uxfs/vfs/compat/squashfs.asm
; =============================================================================
; SquashFS Read-Only Compressed Filesystem Driver.
;
; Implements:
;   - Superblock validation and geometry capture (`squashfs_mount`)
;   - Metadata block header decoding (`squashfs_read_metadata_block`)
;   - Inode reference decomposition (`squashfs_decode_inode_ref`)
;   - Data block reads with per-block compression (`squashfs_read_file`)
;
; SquashFS stores everything in two kinds of block, and confusing them is the
; usual source of bugs.
;
; METADATA blocks are always 8KB uncompressed and carry a 16-bit header: the
; low 15 bits are the on-disk size and bit 15 is set when the block is stored
; UNCOMPRESSED. Note the polarity — the flag marks the exception, so a naive
; "bit set means compressed" reading inverts every decision.
;
; DATA blocks use the superblock's block_size and carry their length in the
; fragment/block table instead, with the same inverted compression flag.
;
; An inode reference is not an offset. It packs a 48-bit block start with a
; 16-bit offset into the uncompressed metadata block, so it must be split
; before either half is usable.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "storage/uxfs/uxfs.inc"
%include "lib/ucmp/include/ucmp.inc"

%define SQUASHFS_MAGIC              0x73717368  ; "hsqs"
%define SQUASHFS_METADATA_SIZE      8192        ; Fixed uncompressed metadata size
%define SQUASHFS_COMPRESSED_BIT     0x8000      ; SET means NOT compressed
%define SQUASHFS_SIZE_MASK          0x7FFF
%define SQUASHFS_INVALID_FRAG       0xFFFFFFFF

; Compression identifiers from the superblock.
%define SQUASHFS_COMP_ZLIB          1
%define SQUASHFS_COMP_LZMA          2
%define SQUASHFS_COMP_LZO           3
%define SQUASHFS_COMP_XZ            4
%define SQUASHFS_COMP_LZ4           5
%define SQUASHFS_COMP_ZSTD          6

struc squashfs_super_t
    .magic:             resd 1      ; SQUASHFS_MAGIC
    .inodes:            resd 1
    .mkfs_time:         resd 1
    .block_size:        resd 1      ; Data block size, a power of two
    .fragments:         resd 1
    .compression:       resw 1      ; SQUASHFS_COMP_*
    .block_log:         resw 1      ; log2(block_size); must agree
    .flags:             resw 1
    .no_ids:            resw 1
    .s_major:           resw 1
    .s_minor:           resw 1
    .root_inode:        resq 1      ; Packed block/offset reference
    .bytes_used:        resq 1
    .id_table_start:    resq 1
endstruc

section .data
align 64

global squashfs_block_size
squashfs_block_size:        dd 0
squashfs_compression:       dd 0
squashfs_root_inode:        dq 0
squashfs_mounted:           dd 0
squashfs_reads:             dq 0
squashfs_decompressions:    dq 0

section .text

global squashfs_init
global squashfs_mount
global squashfs_read_file
global squashfs_read_metadata_block
global squashfs_decode_inode_ref
global squashfs_map_algorithm

; -----------------------------------------------------------------------------
; squashfs_init
;
; Returns:
;   EAX = 0
; -----------------------------------------------------------------------------
align 32
squashfs_init:
    mov dword [squashfs_block_size], 0
    mov dword [squashfs_compression], 0
    mov qword [squashfs_root_inode], 0
    mov dword [squashfs_mounted], 0
    xor eax, eax
    ret

; -----------------------------------------------------------------------------
; squashfs_map_algorithm
;
; Maps a SquashFS compression id onto a UCMP algorithm id.
;
; Inputs:
;   EDI = SQUASHFS_COMP_*
;
; Returns:
;   EAX = UCMP_ALGO_*, or POSIX_EINVAL when unsupported
; -----------------------------------------------------------------------------
align 32
squashfs_map_algorithm:
    cmp edi, SQUASHFS_COMP_ZLIB
    je .ma_zlib
    cmp edi, SQUASHFS_COMP_XZ
    je .ma_xz
    cmp edi, SQUASHFS_COMP_LZ4
    je .ma_lz4
    cmp edi, SQUASHFS_COMP_ZSTD
    je .ma_zstd
    cmp edi, SQUASHFS_COMP_LZMA
    je .ma_lzma

    ; LZO has no UCMP backend; reject rather than silently mis-decode.
    mov eax, POSIX_EINVAL
    ret

.ma_zlib:
    mov eax, UCMP_ALGO_ZLIB
    ret
.ma_xz:
    mov eax, UCMP_ALGO_XZ
    ret
.ma_lz4:
    mov eax, UCMP_ALGO_LZ4
    ret
.ma_zstd:
    mov eax, UCMP_ALGO_ZSTD
    ret
.ma_lzma:
    mov eax, UCMP_ALGO_LZMA
    ret

; -----------------------------------------------------------------------------
; squashfs_mount
;
; Validates the superblock and captures the geometry later reads depend on.
;
; Inputs:
;   RDI = Pointer to the superblock
;
; Returns:
;   EAX = 0 on success
;         POSIX_EIO on a bad magic or inconsistent geometry
;         POSIX_EINVAL on an unsupported compressor
; -----------------------------------------------------------------------------
align 32
squashfs_mount:
    push rbx

    test rdi, rdi
    jz .sm_inval
    mov rbx, rdi

    mov eax, dword [rbx + squashfs_super_t.magic]
    cmp eax, SQUASHFS_MAGIC
    jne .sm_badmagic

    ; block_log must equal log2(block_size). A mismatch means a corrupt or
    ; hand-edited image, and trusting either field alone reads wrong offsets.
    mov eax, dword [rbx + squashfs_super_t.block_size]
    movzx ecx, word [rbx + squashfs_super_t.block_log]
    mov edx, 1
    shl edx, cl
    cmp eax, edx
    jne .sm_badmagic

    mov dword [squashfs_block_size], eax

    movzx edi, word [rbx + squashfs_super_t.compression]
    call squashfs_map_algorithm
    test eax, eax
    js .sm_inval
    mov dword [squashfs_compression], eax

    mov rax, [rbx + squashfs_super_t.root_inode]
    mov [squashfs_root_inode], rax

    mov dword [squashfs_mounted], 1

    xor eax, eax
    pop rbx
    ret

.sm_badmagic:
    mov eax, POSIX_EIO
    pop rbx
    ret

.sm_inval:
    mov eax, POSIX_EINVAL
    pop rbx
    ret

; -----------------------------------------------------------------------------
; squashfs_decode_inode_ref
;
; Splits a packed inode reference into its block start and intra-block offset.
;
; Inputs:
;   RDI = Packed reference
;   RSI = Pointer to a qword receiving the block start
;   RDX = Pointer to a dword receiving the offset
;
; Returns:
;   EAX = 0 on success, POSIX_EINVAL on a null argument
; -----------------------------------------------------------------------------
align 32
squashfs_decode_inode_ref:
    test rsi, rsi
    jz .dr_inval
    test rdx, rdx
    jz .dr_inval

    ; Upper 48 bits: byte offset of the metadata block.
    mov rax, rdi
    shr rax, 16
    mov [rsi], rax

    ; Lower 16 bits: offset within the UNCOMPRESSED block.
    mov eax, edi
    and eax, 0xFFFF
    mov dword [rdx], eax

    xor eax, eax
    ret

.dr_inval:
    mov eax, POSIX_EINVAL
    ret

; -----------------------------------------------------------------------------
; squashfs_read_metadata_block
;
; Decodes one metadata block, decompressing unless the header says otherwise.
;
; Inputs:
;   RDI = Pointer to the on-disk block, header first
;   RSI = Pointer to an 8KB destination buffer
;
; Returns:
;   RAX = Uncompressed byte count, or a negative POSIX error
;   RDX = Total on-disk bytes consumed, including the 2-byte header
; -----------------------------------------------------------------------------
align 32
squashfs_read_metadata_block:
    push rbx
    push r12
    push r13
    push r14

    mov rbx, rdi
    mov r12, rsi

    test rbx, rbx
    jz .rm_inval
    test r12, r12
    jz .rm_inval

    movzx r13d, word [rbx]          ; Header
    mov r14d, r13d
    and r13d, SQUASHFS_SIZE_MASK    ; On-disk payload size

    test r13d, r13d
    jz .rm_corrupt
    cmp r13d, SQUASHFS_METADATA_SIZE
    ja .rm_corrupt

    ; Bit 15 SET means stored uncompressed. The flag marks the exception.
    test r14d, SQUASHFS_COMPRESSED_BIT
    jz .rm_compressed

    mov rdi, r12
    lea rsi, [rbx + 2]
    mov ecx, r13d
    rep movsb

    mov rax, r13
    mov rdx, r13
    add rdx, 2
    jmp .rm_return

.rm_compressed:
    sub rsp, ucmp_stream_t_size
    mov rdi, rsp
    mov rcx, ucmp_stream_t_size
    xor al, al
    rep stosb

    mov eax, dword [squashfs_compression]
    mov dword [rsp + ucmp_stream_t.algo_id], eax
    lea rax, [rbx + 2]
    mov [rsp + ucmp_stream_t.src_ptr], rax
    mov rax, r13
    mov [rsp + ucmp_stream_t.src_len], rax
    mov [rsp + ucmp_stream_t.dst_ptr], r12
    mov qword [rsp + ucmp_stream_t.dst_len], SQUASHFS_METADATA_SIZE

    mov rdi, rsp
    call ucmp_decompress
    mov rcx, rax
    mov rax, [rsp + ucmp_stream_t.dst_written]
    add rsp, ucmp_stream_t_size

    test rcx, rcx
    js .rm_corrupt

    inc qword [squashfs_decompressions]
    mov rdx, r13
    add rdx, 2
    jmp .rm_return

.rm_corrupt:
    mov rax, POSIX_EIO
    xor rdx, rdx
    jmp .rm_return

.rm_inval:
    mov rax, POSIX_EINVAL
    xor rdx, rdx

.rm_return:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; squashfs_read_file
;
; Reads one data block, decompressing when the size header says it is stored
; compressed. Data blocks use the same inverted flag as metadata blocks but
; the superblock's block_size as their uncompressed ceiling.
;
; Inputs:
;   RDI = Pointer to the on-disk data block
;   RSI = Pointer to the destination buffer
;   EDX = Block size entry from the block table (size plus compression flag)
;
; Returns:
;   RAX = Bytes produced, or a negative POSIX error
; -----------------------------------------------------------------------------
align 32
squashfs_read_file:
    push rbx
    push r12
    push r13
    push r14

    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx

    test rbx, rbx
    jz .rf_inval
    test r12, r12
    jz .rf_inval
    cmp dword [squashfs_mounted], 0
    je .rf_inval

    mov r14d, r13d
    and r13d, 0x00FFFFFF            ; Data blocks use a 24-bit size field
    test r13d, r13d
    jz .rf_sparse                   ; Zero length encodes a hole

    mov eax, dword [squashfs_block_size]
    cmp r13d, eax
    ja .rf_corrupt

    ; Bit 24 SET means stored uncompressed, mirroring the metadata convention.
    test r14d, 0x01000000
    jz .rf_compressed

    mov rdi, r12
    mov rsi, rbx
    mov ecx, r13d
    rep movsb

    inc qword [squashfs_reads]
    mov rax, r13
    jmp .rf_return

.rf_compressed:
    sub rsp, ucmp_stream_t_size
    mov rdi, rsp
    mov rcx, ucmp_stream_t_size
    xor al, al
    rep stosb

    mov eax, dword [squashfs_compression]
    mov dword [rsp + ucmp_stream_t.algo_id], eax
    mov [rsp + ucmp_stream_t.src_ptr], rbx
    mov rax, r13
    mov [rsp + ucmp_stream_t.src_len], rax
    mov [rsp + ucmp_stream_t.dst_ptr], r12
    mov eax, dword [squashfs_block_size]
    mov [rsp + ucmp_stream_t.dst_len], rax

    mov rdi, rsp
    call ucmp_decompress
    mov rcx, rax
    mov rax, [rsp + ucmp_stream_t.dst_written]
    add rsp, ucmp_stream_t_size

    test rcx, rcx
    js .rf_corrupt

    inc qword [squashfs_reads]
    inc qword [squashfs_decompressions]
    jmp .rf_return

.rf_sparse:
    ; A hole reads back as zeroes of one full block.
    mov rdi, r12
    mov ecx, dword [squashfs_block_size]
    xor al, al
    rep stosb
    mov eax, dword [squashfs_block_size]
    jmp .rf_return

.rf_corrupt:
    mov rax, POSIX_EIO
    jmp .rf_return

.rf_inval:
    mov rax, POSIX_EINVAL

.rf_return:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

%endif ; GUARD_STORAGE_UXFS_VFS_COMPAT_SQUASHFS_ASM
