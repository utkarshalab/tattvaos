; =============================================================================
; lib/cal/cal.inc
; Calendar and Date utility definitions for Tattva OS.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_CAL_INC
%define IO_CAL_INC

; Re-use standard DateTime structure from time.inc
%include "lib/time/time.inc"

; Days of week codes
WEEKDAY_SUNDAY      equ 0
WEEKDAY_MONDAY      equ 1
WEEKDAY_TUESDAY     equ 2
WEEKDAY_WEDNESDAY   equ 3
WEEKDAY_THURSDAY    equ 4
WEEKDAY_FRIDAY      equ 5
WEEKDAY_SATURDAY    equ 6

; Epoch constants (Unix Time Base = 1970-01-01 00:00:00 UTC)
EPOCH_BASE_YEAR     equ 1970
SECONDS_PER_DAY     equ 86400
SECONDS_PER_HOUR    equ 3600
SECONDS_PER_MINUTE  equ 60

%endif ; IO_CAL_INC
