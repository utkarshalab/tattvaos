; =============================================================================
; Tattva OS — lib/ucmp/ucmp.asm
; =============================================================================
; Master Compression Subsystem Dispatcher API (`ucmp_init`, `ucmp_compress`,
; `ucmp_decompress`).
;
; Dispatches compression and decompression requests to LZ4, ZSTD, DEFLATE,
; Zlib, Gzip, or Snappy algorithms based on stream settings.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM flat binary)
; =============================================================================

%include "lib/ucmp/include/ucmp.inc"
%include "lib/ucmp/arch/common/macros.inc"

; -----------------------------------------------------------------------------
; Child Subsystem NASM File Includes
; -----------------------------------------------------------------------------
%include "lib/ucmp/arch/x86_64/simd/scan.asm"
%include "lib/ucmp/core/stream.asm"
%include "lib/ucmp/core/buffer.asm"
%include "lib/ucmp/core/bitstream.asm"
%include "lib/ucmp/algo/lz4/lz4.asm"
%include "lib/ucmp/algo/lz4/lz4_decomp.asm"
%include "lib/ucmp/algo/snappy/snappy.asm"
%include "lib/ucmp/algo/zstd/zstd.asm"
%include "lib/ucmp/algo/deflate/deflate.asm"
%include "lib/ucmp/algo/deflate/inflate.asm"
%include "lib/ucmp/algo/zlib/zlib.asm"
%include "lib/ucmp/algo/gzip/gzip.asm"
%include "lib/ucmp/checksum/crc32.asm"
%include "lib/ucmp/mem/arena.asm"

section .text

global ucmp_init
global ucmp_compress
global ucmp_decompress

; -----------------------------------------------------------------------------
; ucmp_init
;
; Initializes master compression subsystem.
;
; Returns:
;   EAX = UCMP_OK (0)
; -----------------------------------------------------------------------------
align 32
ucmp_init:
    mov eax, UCMP_OK
    ret

; -----------------------------------------------------------------------------
; ucmp_compress
;
; Master compression dispatcher.
;
; Inputs:
;   RDI = Pointer to ucmp_stream_t stream descriptor
;
; Returns:
;   RAX = Bytes written to destination (or negative error code)
; -----------------------------------------------------------------------------
align 32
ucmp_compress:
    UCMP_SAVE_REGS

    mov rbx, rdi                    ; RBX = stream pointer
    mov eax, [rbx + ucmp_stream_t.algo_id]

    mov rdi, [rbx + ucmp_stream_t.src_ptr]
    mov rsi, [rbx + ucmp_stream_t.src_len]
    mov rdx, [rbx + ucmp_stream_t.dst_ptr]
    mov rcx, [rbx + ucmp_stream_t.dst_len]

    cmp eax, UCMP_ALGO_LZ4
    je .do_lz4
    cmp eax, UCMP_ALGO_ZSTD
    je .do_zstd
    cmp eax, UCMP_ALGO_SNAPPY
    je .do_snappy
    cmp eax, UCMP_ALGO_DEFLATE
    je .do_deflate
    cmp eax, UCMP_ALGO_ZLIB
    je .do_zlib
    cmp eax, UCMP_ALGO_GZIP
    je .do_gzip

.do_lz4:
    call ucmp_lz4_compress
    jmp .done

.do_zstd:
    call ucmp_zstd_compress
    jmp .done

.do_snappy:
    call ucmp_snappy_compress
    jmp .done

.do_deflate:
    call ucmp_deflate_compress
    jmp .done

.do_zlib:
    call ucmp_zlib_compress
    jmp .done

.do_gzip:
    call ucmp_gzip_compress
    jmp .done

.done:
    test rax, rax
    js .exit
    mov [rbx + ucmp_stream_t.dst_written], rax

.exit:
    UCMP_RESTORE_REGS
    ret

; -----------------------------------------------------------------------------
; ucmp_decompress
;
; Master decompression dispatcher.
;
; Inputs:
;   RDI = Pointer to ucmp_stream_t stream descriptor
;
; Returns:
;   RAX = Bytes written to destination (or negative error code)
; -----------------------------------------------------------------------------
align 32
ucmp_decompress:
    UCMP_SAVE_REGS

    mov rbx, rdi                    ; RBX = stream pointer
    mov eax, [rbx + ucmp_stream_t.algo_id]

    mov rdi, [rbx + ucmp_stream_t.src_ptr]
    mov rsi, [rbx + ucmp_stream_t.src_len]
    mov rdx, [rbx + ucmp_stream_t.dst_ptr]
    mov rcx, [rbx + ucmp_stream_t.dst_len]

    cmp eax, UCMP_ALGO_LZ4
    je .do_lz4_decomp
    cmp eax, UCMP_ALGO_ZSTD
    je .do_zstd_decomp
    cmp eax, UCMP_ALGO_SNAPPY
    je .do_snappy_decomp
    cmp eax, UCMP_ALGO_DEFLATE
    je .do_deflate_decomp
    cmp eax, UCMP_ALGO_ZLIB
    je .do_zlib_decomp
    cmp eax, UCMP_ALGO_GZIP
    je .do_gzip_decomp

.do_lz4_decomp:
    call ucmp_lz4_decompress
    jmp .done_decomp

.do_zstd_decomp:
    call ucmp_zstd_decompress
    jmp .done_decomp

.do_snappy_decomp:
    call ucmp_snappy_decompress
    jmp .done_decomp

.do_deflate_decomp:
    call ucmp_inflate_decompress
    jmp .done_decomp

.do_zlib_decomp:
    call ucmp_zlib_decompress
    jmp .done_decomp

.do_gzip_decomp:
    call ucmp_gzip_decompress
    jmp .done_decomp

.done_decomp:
    test rax, rax
    js .exit_decomp
    mov [rbx + ucmp_stream_t.dst_written], rax

.exit_decomp:
    UCMP_RESTORE_REGS
    ret
