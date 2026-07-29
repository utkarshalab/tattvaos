; =============================================================================
; Tattva OS — lib/time/leap_seconds.asm
; =============================================================================
; TAI (Temps Atomique International) & IERS Leap Second Table Engine.
;
; Implements:
;   - Conversion between UTC (Coordinated Universal Time) and TAI
;   - `TAI = UTC + 37 seconds` Leap Second Adjustment Table
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "lib/time/time.inc"

section .data
align 8
tai_utc_offset_sec: dq 37               ; Current TAI-UTC offset = 37 seconds

section .text

global leap_seconds_init
global utc_to_tai
global tai_to_utc
global get_tai_offset

align 32
leap_seconds_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
utc_to_tai:
    push rbp
    mov rbp, rsp
    ; rdi = utc_epoch_seconds -> returns TAI_seconds in RAX
    mov rax, rdi
    add rax, [rel tai_utc_offset_sec]
    pop rbp
    ret

align 32
tai_to_utc:
    push rbp
    mov rbp, rsp
    ; rdi = TAI_seconds -> returns utc_epoch_seconds in RAX
    mov rax, rdi
    sub rax, [rel tai_utc_offset_sec]
    pop rbp
    ret

align 32
get_tai_offset:
    mov rax, [rel tai_utc_offset_sec]
    ret
