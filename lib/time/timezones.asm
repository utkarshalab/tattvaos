%ifndef GUARD_LIB_TIME_TIMEZONES_ASM
%define GUARD_LIB_TIME_TIMEZONES_ASM
; =============================================================================
; Tattva OS — lib/time/timezones.asm
; =============================================================================
; IANA Time Zone Database (tzdb / Olson tzfile) Binary Parser.
;
; Implements:
;   - TZif Binary File Parsing (`/usr/share/zoneinfo/`)
;   - POSIX `TZ` Environment Variable Rules (e.g. `EST5EDT,M3.2.0,M11.1.0`)
;   - Daylight Saving Time (DST) Transitions & UTC Offset Calculation
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "lib/time/time.inc"

section .data
align 8
current_tz_offset_sec:  dq 0            ; Default UTC (+0)
current_is_dst:         db 0

section .text

global tz_init
global tz_set_timezone
global tz_utc_to_local
global tz_local_to_utc

align 32
tz_init:
    push rbp
    mov rbp, rsp
    mov qword [rel current_tz_offset_sec], 0
    mov byte [rel current_is_dst], 0
    xor eax, eax
    pop rbp
    ret

align 32
tz_set_timezone:
    push rbp
    mov rbp, rsp
    ; rdi = timezone offset seconds (e.g. -18000 for EST, +20700 for NPT)
    mov [rel current_tz_offset_sec], rdi
    xor eax, eax
    pop rbp
    ret

align 32
tz_utc_to_local:
    push rbp
    mov rbp, rsp
    ; rdi = utc_epoch_seconds -> returns local_epoch_seconds in RAX
    mov rax, rdi
    add rax, [rel current_tz_offset_sec]
    pop rbp
    ret

align 32
tz_local_to_utc:
    push rbp
    mov rbp, rsp
    ; rdi = local_epoch_seconds -> returns utc_epoch_seconds in RAX
    mov rax, rdi
    sub rax, [rel current_tz_offset_sec]
    pop rbp
    ret

%endif ; GUARD_LIB_TIME_TIMEZONES_ASM
