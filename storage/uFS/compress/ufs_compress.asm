; =============================================================================
; Tattva OS — ufs/compress/ufs_compress.asm
; =============================================================================
; Real-time Inline LZ4 & ZSTD Storage Block Compression Engine for uFS.
;
; Consumes master compression dispatcher API from `lib/ucmp/` (ucmp_compress,
; ucmp_decompress) to compress/decompress storage blocks during read/write.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "ufs/ufs.inc"
%include "lib/ucmp/include/ucmp.inc"

section .text

global ufs_compress_block
global ufs_decompress_block

extern ucmp_compress
extern ucmp_decompress

; -----------------------------------------------------------------------------
; ufs_compress_block
;
; Inputs:
;   RDI = Source block buffer pointer (4KB)
;   RSI = Destination compressed buffer pointer
;   EDX = Algorithm ID (UCMP_ALGO_LZ4, UCMP_ALGO_ZSTD...)
;
; Returns:
;   RAX = Compressed size in bytes
; -----------------------------------------------------------------------------
align 32
ufs_compress_block:
    push rbp
    mov rbp, rsp
    sub rsp, 64                     ; Allocate local ucmp_stream_t on stack

    mov [rsp + ucmp_stream_t.algo_id], edx
    mov [rsp + ucmp_stream_t.src_ptr], rdi
    mov qword [rsp + ucmp_stream_t.src_len], 4096
    mov [rsp + ucmp_stream_t.dst_ptr], rsi
    mov qword [rsp + ucmp_stream_t.dst_len], 4096

    mov rdi, rsp
    call ucmp_compress

    mov rsp, rbp
    pop rbp
    ret

; -----------------------------------------------------------------------------
; ufs_decompress_block
;
; Inputs:
;   RDI = Compressed source buffer pointer
;   ESI = Compressed byte length
;   RDX = Destination uncompressed buffer pointer (4KB)
;   ECX = Algorithm ID
;
; Returns:
;   RAX = Decompressed size in bytes (4096)
; -----------------------------------------------------------------------------
align 32
ufs_decompress_block:
    push rbp
    mov rbp, rsp
    sub rsp, 64

    mov [rsp + ucmp_stream_t.algo_id], ecx
    mov [rsp + ucmp_stream_t.src_ptr], rdi
    mov [rsp + ucmp_stream_t.src_len], rsi
    mov [rsp + ucmp_stream_t.dst_ptr], rdx
    mov qword [rsp + ucmp_stream_t.dst_len], 4096

    mov rdi, rsp
    call ucmp_decompress

    mov rsp, rbp
    pop rbp
    ret
