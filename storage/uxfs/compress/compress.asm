%ifndef GUARD_STORAGE_UXFS_COMPRESS_COMPRESS_ASM
%define GUARD_STORAGE_UXFS_COMPRESS_COMPRESS_ASM
; =============================================================================
; Tattva OS — storage/uxfs/compress/compress.asm
; =============================================================================
; Inline Transparent Block Compression with Incompressible-Data Fallback.
;
; Implements:
;   - Block compression with a stored-raw fallback (`uxfs_compress_block`)
;   - Header-driven decompression (`uxfs_decompress_block`)
;   - Compressibility estimation (`uxfs_compress_worth_it`)
;
; Every compressed block carries an 8-byte header naming the algorithm actually
; used. That indirection is what makes the fallback possible: when a block does
; not compress — already-compressed media, encrypted data, high-entropy noise —
; it is stored raw with UCMP_ALGO_NONE and read back verbatim.
;
; Without that fallback a filesystem is strictly worse off on incompressible
; data: it burns CPU on both paths and can EXPAND the block past its original
; size, since most codecs add framing overhead to data they cannot shrink. A
; 4KB block that compresses to 4100 bytes no longer fits where it belongs.
;
; The previous implementation had neither the header nor the fallback, and
; allocated 64 bytes of stack for a 92-byte ucmp_stream_t — overwriting 28
; bytes of the caller's frame on every call.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "storage/uxfs/uxfs.inc"
%include "lib/ucmp/include/ucmp.inc"

%define UXFS_CBLOCK_HEADER          8
%define UXFS_CBLOCK_FLAG_CHECKSUM   (1 << 0)

; -----------------------------------------------------------------------------
; On-disk header prefixed to every compressed extent.
; -----------------------------------------------------------------------------
struc uxfs_cblock_t
    .algo:              resb 1      ; UCMP_ALGO_* actually used; NONE = raw
    .flags:             resb 1      ; UXFS_CBLOCK_FLAG_*
    .orig_len:          resw 1      ; Uncompressed length, <= UXFS_BLOCK_SIZE
    .comp_len:          resd 1      ; Payload length following this header
endstruc

section .text

global uxfs_compress_block
global uxfs_decompress_block
global uxfs_compress_worth_it

; -----------------------------------------------------------------------------
; uxfs_compress_worth_it
;
; Decides whether a compressed result is worth storing.
;
; The rule is not "did it get smaller" but "did it get smaller by enough to
; save a block". Compression that shaves 40 bytes off a 4KB block still
; occupies the same allocation unit and buys nothing, while costing CPU on
; every subsequent read.
;
; Inputs:
;   RDI = Compressed length, excluding the header
;   RSI = Original length
;
; Returns:
;   EAX = 1 when storing compressed is worthwhile, 0 otherwise
; -----------------------------------------------------------------------------
align 32
uxfs_compress_worth_it:
    ; Header must fit alongside the payload.
    mov rax, rdi
    add rax, UXFS_CBLOCK_HEADER
    cmp rax, rsi
    jae .wi_no                      ; Same size or larger: keep it raw

    ; Require at least a one-eighth saving so marginal wins do not cost read
    ; CPU forever after.
    mov rcx, rsi
    shr rcx, 3                      ; original / 8
    add rax, rcx
    cmp rax, rsi
    ja .wi_no

    mov eax, 1
    ret

.wi_no:
    xor eax, eax
    ret

; -----------------------------------------------------------------------------
; uxfs_compress_block
;
; Compresses one block, falling back to raw storage when compression does not
; pay. The destination always receives a valid uxfs_cblock_t header.
;
; Inputs:
;   RDI = Source block pointer
;   RSI = Destination buffer pointer
;   EDX = Preferred UCMP_ALGO_*
;   ECX = Source length in bytes (<= UXFS_BLOCK_SIZE)
;
; Returns:
;   RAX = Total bytes written including the header, or a negative POSIX error
; -----------------------------------------------------------------------------
align 32
uxfs_compress_block:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi                    ; Source
    mov r12, rsi                    ; Destination
    mov r13d, edx                   ; Algorithm
    mov r14d, ecx                   ; Source length

    test rbx, rbx
    jz .cb_inval
    test r12, r12
    jz .cb_inval
    test r14d, r14d
    jz .cb_inval
    cmp r14d, UXFS_BLOCK_SIZE
    ja .cb_inval

    ; Caller explicitly asked for no compression.
    cmp r13d, UCMP_ALGO_NONE
    je .cb_store_raw

    ; Full struct, zeroed: src_pos and flags are read by the codec and stale
    ; stack contents would be interpreted as live state.
    sub rsp, ucmp_stream_t_size
    mov rdi, rsp
    mov rcx, ucmp_stream_t_size
    xor al, al
    rep stosb

    mov dword [rsp + ucmp_stream_t.algo_id], r13d
    mov [rsp + ucmp_stream_t.src_ptr], rbx
    mov rax, r14
    mov [rsp + ucmp_stream_t.src_len], rax
    lea rax, [r12 + UXFS_CBLOCK_HEADER]     ; Payload sits after the header
    mov [rsp + ucmp_stream_t.dst_ptr], rax
    mov rax, r14
    mov [rsp + ucmp_stream_t.dst_len], rax  ; Never exceed the original size

    mov rdi, rsp
    call ucmp_compress
    mov r15, rax                            ; Codec result

    mov rax, [rsp + ucmp_stream_t.dst_written]
    add rsp, ucmp_stream_t_size

    ; A codec failure is not fatal here — raw storage is always available.
    test r15, r15
    js .cb_store_raw
    test rax, rax
    jz .cb_store_raw

    mov r15, rax                            ; Compressed payload length

    mov rdi, r15
    mov rsi, r14
    call uxfs_compress_worth_it
    test eax, eax
    jz .cb_store_raw

    ; Worth it: stamp the header describing the compressed payload.
    mov byte [r12 + uxfs_cblock_t.algo], r13b
    mov byte [r12 + uxfs_cblock_t.flags], 0
    mov word [r12 + uxfs_cblock_t.orig_len], r14w
    mov dword [r12 + uxfs_cblock_t.comp_len], r15d

    mov rax, r15
    add rax, UXFS_CBLOCK_HEADER
    jmp .cb_return

.cb_store_raw:
    ; Incompressible: copy verbatim behind a NONE header.
    mov byte [r12 + uxfs_cblock_t.algo], UCMP_ALGO_NONE
    mov byte [r12 + uxfs_cblock_t.flags], 0
    mov word [r12 + uxfs_cblock_t.orig_len], r14w
    mov dword [r12 + uxfs_cblock_t.comp_len], r14d

    lea rdi, [r12 + UXFS_CBLOCK_HEADER]
    mov rsi, rbx
    mov ecx, r14d
    rep movsb

    mov rax, r14
    add rax, UXFS_CBLOCK_HEADER
    jmp .cb_return

.cb_inval:
    mov rax, POSIX_EINVAL

.cb_return:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_decompress_block
;
; Reverses uxfs_compress_block, dispatching on the stored header.
;
; The algorithm comes from the block itself, never from the caller: a block
; written before a policy change must still decode with whatever codec actually
; produced it.
;
; Inputs:
;   RDI = Source pointer (a uxfs_cblock_t header followed by its payload)
;   RSI = Destination buffer pointer
;   EDX = Destination capacity in bytes
;
; Returns:
;   RAX = Bytes written to the destination, or a negative POSIX error
; -----------------------------------------------------------------------------
align 32
uxfs_decompress_block:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi                    ; Source
    mov r12, rsi                    ; Destination
    mov r13d, edx                   ; Destination capacity

    test rbx, rbx
    jz .db_inval
    test r12, r12
    jz .db_inval

    movzx r14d, word [rbx + uxfs_cblock_t.orig_len]
    test r14d, r14d
    jz .db_corrupt
    cmp r14d, UXFS_BLOCK_SIZE
    ja .db_corrupt                  ; Header claims more than a block

    cmp r14d, r13d
    ja .db_nospc                    ; Will not fit in the caller's buffer

    mov r15d, dword [rbx + uxfs_cblock_t.comp_len]
    test r15d, r15d
    jz .db_corrupt
    cmp r15d, UXFS_BLOCK_SIZE
    ja .db_corrupt

    movzx eax, byte [rbx + uxfs_cblock_t.algo]
    cmp eax, UCMP_ALGO_NONE
    je .db_raw

    sub rsp, ucmp_stream_t_size
    mov rdi, rsp
    mov rcx, ucmp_stream_t_size
    push rax
    xor al, al
    rep stosb
    pop rax

    mov dword [rsp + ucmp_stream_t.algo_id], eax
    lea rcx, [rbx + UXFS_CBLOCK_HEADER]
    mov [rsp + ucmp_stream_t.src_ptr], rcx
    mov rcx, r15
    mov [rsp + ucmp_stream_t.src_len], rcx
    mov [rsp + ucmp_stream_t.dst_ptr], r12
    mov rcx, r14
    mov [rsp + ucmp_stream_t.dst_len], rcx

    mov rdi, rsp
    call ucmp_decompress
    mov rcx, rax

    mov rax, [rsp + ucmp_stream_t.dst_written]
    add rsp, ucmp_stream_t_size

    test rcx, rcx
    js .db_corrupt

    ; A short decode means the payload was truncated or tampered with.
    cmp rax, r14
    jne .db_corrupt

    jmp .db_return

.db_raw:
    ; Stored uncompressed: copy the payload straight out.
    mov rdi, r12
    lea rsi, [rbx + UXFS_CBLOCK_HEADER]
    mov ecx, r14d
    rep movsb

    mov rax, r14
    jmp .db_return

.db_nospc:
    mov rax, POSIX_ENOSPC
    jmp .db_return

.db_corrupt:
    mov rax, POSIX_EIO
    jmp .db_return

.db_inval:
    mov rax, POSIX_EINVAL

.db_return:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

%endif ; GUARD_STORAGE_UXFS_COMPRESS_COMPRESS_ASM
