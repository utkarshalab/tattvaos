; =============================================================================
; Tattva OS — lib/ulog/sinks/rotate.asm
; =============================================================================
; Size-based rollover and retention for the file sink. Decides *when* and
; tracks *which segment*; file_transport.asm owns the actual uxfs open/close
; calls, since it's the one holding the current file path/handle.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_SINKS_ROTATE_ASM
%define LIB_ULOG_SINKS_ROTATE_ASM

[BITS 64]

%define ROTATE_MAX_BYTES     (16 * 1024 * 1024)
%define ROTATE_MAX_SEGMENTS  8            ; retention: oldest segment recycled past this

section .bss
alignb 8
global ulog_rotate_segment
ulog_rotate_segment: resd 1
global ulog_rotate_bytes_written
ulog_rotate_bytes_written: resq 1

section .text

; -----------------------------------------------------------------------------
; rotate_note_bytes — Input: RDI = bytes just written to the current segment
; Output: RAX = 1 if the segment just crossed ROTATE_MAX_BYTES and should roll
; -----------------------------------------------------------------------------
global rotate_note_bytes
rotate_note_bytes:
    add [ulog_rotate_bytes_written], rdi
    mov rax, [ulog_rotate_bytes_written]
    cmp rax, ROTATE_MAX_BYTES
    jl .no_roll
    mov rax, 1
    ret
.no_roll:
    xor rax, rax
    ret

; -----------------------------------------------------------------------------
; rotate_perform — advance to the next segment (retention wraps, mod
; ROTATE_MAX_SEGMENTS, so segment N+ROTATE_MAX_SEGMENTS reuses segment N's
; slot — file_transport.asm truncates on open when reusing a slot)
; Output: RAX = new segment index
; -----------------------------------------------------------------------------
global rotate_perform
rotate_perform:
    mov eax, [ulog_rotate_segment]
    inc eax
    xor edx, edx
    mov ecx, ROTATE_MAX_SEGMENTS
    div ecx                          ; wait: div here divides EDX:EAX by ECX —
                                      ; EDX must be 0 going in, which it is
    mov eax, edx                     ; EAX = new segment (the remainder)
    mov [ulog_rotate_segment], eax
    mov qword [ulog_rotate_bytes_written], 0
    ret

; -----------------------------------------------------------------------------
; rotate_current_segment — Output: RAX = current segment index
; -----------------------------------------------------------------------------
global rotate_current_segment
rotate_current_segment:
    movsxd rax, dword [ulog_rotate_segment]
    ret

%endif ; LIB_ULOG_SINKS_ROTATE_ASM
