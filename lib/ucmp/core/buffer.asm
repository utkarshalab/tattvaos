%ifndef GUARD_LIB_UCMP_CORE_BUFFER_ASM
%define GUARD_LIB_UCMP_CORE_BUFFER_ASM
; =============================================================================
; Tattva OS — lib/ucmp/core/buffer.asm
; =============================================================================
; Sliding Window Ring Buffer Manager (32KB / 64KB).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "lib/ucmp/include/ucmp.inc"
%include "lib/ucmp/arch/common/macros.inc"

struc ucmp_window_buffer_t
    .buffer_ptr:        resq 1      ; Ring buffer memory address
    .capacity:          resq 1      ; Window capacity (32KB / 64KB)
    .head_pos:          resq 1      ; Current write position
endstruc

section .text

global ucmp_buffer_init
global ucmp_buffer_write_byte

; -----------------------------------------------------------------------------
; ucmp_buffer_init
; -----------------------------------------------------------------------------
align 32
ucmp_buffer_init:
    mov [rdi + ucmp_window_buffer_t.buffer_ptr], rsi
    mov [rdi + ucmp_window_buffer_t.capacity], rdx
    mov qword [rdi + ucmp_window_buffer_t.head_pos], 0
    ret

; -----------------------------------------------------------------------------
; ucmp_buffer_write_byte
; -----------------------------------------------------------------------------
align 32
ucmp_buffer_write_byte:
    mov rax, [rdi + ucmp_window_buffer_t.head_pos]
    mov r8, [rdi + ucmp_window_buffer_t.buffer_ptr]
    mov byte [r8 + rax], sil

    inc rax
    cmp rax, [rdi + ucmp_window_buffer_t.capacity]
    jl .no_wrap
    xor rax, rax

.no_wrap:
    mov [rdi + ucmp_window_buffer_t.head_pos], rax
    ret

%endif ; GUARD_LIB_UCMP_CORE_BUFFER_ASM
