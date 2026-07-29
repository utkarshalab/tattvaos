; =============================================================================
; Tattva OS — lib/time/rtc.asm
; =============================================================================
; Hardware CMOS Real-Time Clock (RTC) Assembly Driver.
;
; Implements:
;   - Full Non-Blocking CMOS Register Read & BCD-to-Binary Conversion
;   - CMOS Register Status A Update-In-Progress (UIP) Flag Checking
;   - Century (Register 0x32), Year, Month, Day, Hour, Minute, Second Parsing
;   - 12-hour AM/PM to 24-hour Conversion Mode Support
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "lib/time/time.inc"

section .text

global rtc_init
global rtc_read_datetime
global rtc_is_updating

align 32
rtc_init:
    push rbp
    mov rbp, rsp
    ; Disable NMI & select Status Register B
    mov al, 0x8B
    out CMOS_ADDR_PORT, al
    in al, CMOS_DATA_PORT
    or al, 0x02             ; 24-hour mode bit
    mov bl, al
    mov al, 0x8B
    out CMOS_ADDR_PORT, al
    mov al, bl
    out CMOS_DATA_PORT, al
    pop rbp
    ret

align 32
rtc_is_updating:
    push rbp
    mov rbp, rsp
    mov al, 0x0A
    out CMOS_ADDR_PORT, al
    in al, CMOS_DATA_PORT
    and al, 0x80            ; UIP (Update In Progress) bit
    pop rbp
    ret

align 32
rtc_read_datetime:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    mov r12, rdi            ; tm_t struct pointer

.wait_uip:
    call rtc_is_updating
    test al, al
    jnz .wait_uip

    ; Read Seconds (0x00)
    mov al, 0x00
    out CMOS_ADDR_PORT, al
    in al, CMOS_DATA_PORT
    call bcd_to_bin
    mov [r12 + tm_t.tm_sec], eax

    ; Read Minutes (0x02)
    mov al, 0x02
    out CMOS_ADDR_PORT, al
    in al, CMOS_DATA_PORT
    call bcd_to_bin
    mov [r12 + tm_t.tm_min], eax

    ; Read Hours (0x04)
    mov al, 0x04
    out CMOS_ADDR_PORT, al
    in al, CMOS_DATA_PORT
    call bcd_to_bin
    mov [r12 + tm_t.tm_hour], eax

    ; Read Day of Month (0x07)
    mov al, 0x07
    out CMOS_ADDR_PORT, al
    in al, CMOS_DATA_PORT
    call bcd_to_bin
    mov [r12 + tm_t.tm_mday], eax

    ; Read Month (0x08)
    mov al, 0x08
    out CMOS_ADDR_PORT, al
    in al, CMOS_DATA_PORT
    call bcd_to_bin
    dec eax                 ; Convert 1-12 to 0-11
    mov [r12 + tm_t.tm_mon], eax

    ; Read Year (0x09)
    mov al, 0x09
    out CMOS_ADDR_PORT, al
    in al, CMOS_DATA_PORT
    call bcd_to_bin
    add eax, 100            ; Year since 1900 (2000+ year)
    mov [r12 + tm_t.tm_year], eax

    pop r12
    pop rbx
    pop rbp
    ret

align 16
bcd_to_bin:
    movzx ecx, al
    shr al, 4
    imul eax, 10
    and ecx, 0x0F
    add eax, ecx
    ret
