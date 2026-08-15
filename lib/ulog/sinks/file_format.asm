; =============================================================================
; Tattva OS — lib/ulog/sinks/file_format.asm
; =============================================================================
; Renders one record to JSON in a static scratch buffer for file_transport.asm
; to write out. Safe as a single static buffer because only the drain fiber
; ever calls this — one writer, never reentered mid-render.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_SINKS_FILE_FORMAT_ASM
%define LIB_ULOG_SINKS_FILE_FORMAT_ASM

[BITS 64]

%define FILE_FORMAT_BUF_SIZE  1024

section .bss
alignb 8
global ulog_file_format_scratch
ulog_file_format_scratch: resb FILE_FORMAT_BUF_SIZE

section .text

; -----------------------------------------------------------------------------
; file_format_record — Input: RDI = log_record_t*
; Output: RAX = length written into ulog_file_format_scratch
; -----------------------------------------------------------------------------
global file_format_record
file_format_record:
    mov rsi, ulog_file_format_scratch
    mov rdx, FILE_FORMAT_BUF_SIZE
    jmp json_render_line

%endif ; LIB_ULOG_SINKS_FILE_FORMAT_ASM
