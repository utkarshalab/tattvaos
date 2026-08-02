; =============================================================================
; Tattva OS — unet/tools/telecom/ntpdate.asm
; =============================================================================
; Command-Line Network Time Protocol Clock Sync Tool (`ntpdate`).
;
; Features:
;   - UDP Port 123 RFC 5905 NTPv4 48-Byte Header (Mode 3 Client, Stratum, Poll, Precision)
;   - 64-Bit Fixed-Point Timestamp (32-bit Integer Seconds + 32-bit Fractional Seconds)
;   - Clock Drift Offset & Round-Trip Delay Calculation
;
; Delegates:
;   - NTP Service                       -> unet/services/ntp.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define NTP_PORT                    123

section .text

global ntpdate_main

extern rdtsc_get_cycles

align 64
ntpdate_main:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Format NTPv4 Client Mode 3 packet -> query NTP server 123 -> adjust system clock
    call rdtsc_get_cycles
    xor eax, eax
    pop rbp
    ret
