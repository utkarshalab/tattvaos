; =============================================================================
; Tattva OS — unet/tools/industrial/mil1553_mon.asm
; =============================================================================
; MIL-STD-1553B Military Serial Bus Monitor & Protocol Analyzer Tool (`1553-mon`).
;
; Features:
;   - Real-Time Command Word, Data Word, Status Word Bus Traffic Logging
;   - Bus A vs Bus B Active Channel Monitoring
;
; Delegates:
;   - MIL-STD-1553B Engine             -> unet/avionics/mil1553.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global mil1553_mon_main

extern mil1553_parse_cmd_word

align 64
mil1553_mon_main:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Monitor 20-bit MIL-STD-1553B words on Bus A / Bus B & parse RT addresses
    call mil1553_parse_cmd_word
    pop rbp
    ret
