; =============================================================================
; lib/time/time.inc
; Time and clock primitive definitions for Tattva OS.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_TIME_INC
%define IO_TIME_INC

; DateTime representation structure (56 bytes)
struc tm_t
    .year       resq 1      ; Full year (e.g. 2026)
    .month      resq 1      ; Month of year (1-12)
    .day        resq 1      ; Day of month (1-31)
    .hour       resq 1      ; Hour of day (0-23)
    .minute     resq 1      ; Minute of hour (0-59)
    .second     resq 1      ; Second of minute (0-59)
    .nanosecond resq 1      ; Nanosecond of second (0-999999999)
endstruc

; CMOS Real-Time Clock I/O Register mappings
CMOS_PORT_INDEX     equ 0x70
CMOS_PORT_DATA      equ 0x71

; CMOS Register Indices for time information
CMOS_REG_SECONDS    equ 0x00
CMOS_REG_MINUTES    equ 0x02
CMOS_REG_HOURS      equ 0x04
CMOS_REG_WEEKDAY    equ 0x06
CMOS_REG_DAY_MONTH  equ 0x07
CMOS_REG_MONTH      equ 0x08
CMOS_REG_YEAR       equ 0x09
CMOS_REG_CENTURY    equ 0x32

; CMOS Status Registers
CMOS_REG_STATUS_A   equ 0x0A
CMOS_REG_STATUS_B   equ 0x0B

; CMOS Status A flags
CMOS_STATUS_A_UIP   equ 0x80        ; Update in progress flag bit

; CMOS Status B flags
CMOS_STATUS_B_24H   equ 0x02        ; 24-hour mode flag bit (1 = 24H, 0 = 12H)
CMOS_STATUS_B_BIN   equ 0x04        ; Binary mode flag bit (1 = Binary, 0 = BCD)

%endif ; IO_TIME_INC
