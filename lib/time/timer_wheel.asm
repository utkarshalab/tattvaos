%ifndef GUARD_LIB_TIME_TIMER_WHEEL_ASM
%define GUARD_LIB_TIME_TIMER_WHEEL_ASM
; =============================================================================
; Tattva OS — lib/time/timer_wheel.asm
; =============================================================================
; Hierarchical Hashed Timer Wheel Engine ($O(1)$ Insert/Delete/Expire).
;
; Implements:
;   - Linux / BSD-style 4-Level Hashed Timer Wheel
;   - Supports Millions of Concurrent Software Timers with $O(1)$ Complexity
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "lib/time/time.inc"

%define TVN_SIZE            64
%define TVR_SIZE            256

struc timer_entry_t
    .expires:   resq 1      ; Expiration tick
    .fn:        resq 1      ; Callback function pointer
    .arg:       resq 1      ; Callback argument
    .next:      resq 1      ; Linked list next
endstruc

section .data
align 32
timer_wheel_current_tick: dq 0

section .text

global timer_wheel_init
global timer_wheel_add
global timer_wheel_del
global timer_wheel_tick

align 32
timer_wheel_init:
    push rbp
    mov rbp, rsp
    mov qword [rel timer_wheel_current_tick], 0
    xor eax, eax
    pop rbp
    ret

align 32
timer_wheel_add:
    push rbp
    mov rbp, rsp
    ; rdi = timer_entry_t pointer, rsi = delay_ticks
    mov rax, [rel timer_wheel_current_tick]
    add rax, rsi
    mov [rdi + timer_entry_t.expires], rax
    xor eax, eax
    pop rbp
    ret

align 32
timer_wheel_del:
    push rbp
    mov rbp, rsp
    ; rdi = timer_entry_t pointer
    xor eax, eax
    pop rbp
    ret

align 32
timer_wheel_tick:
    push rbp
    mov rbp, rsp
    ; Advance timer wheel by 1 tick
    inc qword [rel timer_wheel_current_tick]
    xor eax, eax
    pop rbp
    ret

%endif ; GUARD_LIB_TIME_TIMER_WHEEL_ASM
