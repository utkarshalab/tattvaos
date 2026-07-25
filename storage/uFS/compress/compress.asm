; =============================================================================
; Tattva OS — ufs/compress/compress.asm
; =============================================================================
; Real-time Inline LZ4 & ZSTD Storage Block Compression Engine.
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

align 32
ufs_compress_block:
    push rbp
    mov rbp, rsp
    sub rsp, 64

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
