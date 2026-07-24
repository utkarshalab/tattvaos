; =============================================================================
; Tattva OS — lib/ucmp/core/stream.asm
; =============================================================================
; Streaming Compression & Decompression State Machine Abstraction.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "lib/ucmp/include/ucmp.inc"
%include "lib/ucmp/arch/common/macros.inc"

section .text

global ucmp_stream_init
global ucmp_stream_reset

; -----------------------------------------------------------------------------
; ucmp_stream_init
;
; Inputs:
;   RDI = Pointer to ucmp_stream_t structure
;   ESI = Algorithm ID (UCMP_ALGO_LZ4, ZSTD, DEFLATE, etc.)
;   RDX = Source buffer pointer
;   RCX = Source length
;   R8  = Destination buffer pointer
;   R9  = Destination capacity
; -----------------------------------------------------------------------------
align 32
ucmp_stream_init:
    mov [rdi + ucmp_stream_t.algo_id], esi
    mov qword [rdi + ucmp_stream_t.flags], 0
    mov [rdi + ucmp_stream_t.src_ptr], rdx
    mov [rdi + ucmp_stream_t.src_len], rcx
    mov qword [rdi + ucmp_stream_t.src_pos], 0
    mov [rdi + ucmp_stream_t.dst_ptr], r8
    mov [rdi + ucmp_stream_t.dst_len], r9
    mov qword [rdi + ucmp_stream_t.dst_written], 0
    mov dword [rdi + ucmp_stream_t.checksum], 0xFFFFFFFF
    mov eax, UCMP_OK
    ret

; -----------------------------------------------------------------------------
; ucmp_stream_reset
; -----------------------------------------------------------------------------
align 32
ucmp_stream_reset:
    mov qword [rdi + ucmp_stream_t.src_pos], 0
    mov qword [rdi + ucmp_stream_t.dst_written], 0
    mov dword [rdi + ucmp_stream_t.checksum], 0xFFFFFFFF
    mov eax, UCMP_OK
    ret
