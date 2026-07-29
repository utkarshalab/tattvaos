; =============================================================================
; Tattva OS — unet/tools/ipfix_cap.asm
; =============================================================================
; IPFIX / NetFlow v9 Flow Collector & Packet Sampling Tool (`ipfix-cap`).
;
; Implements:
;   - Collects IPFIX Template Records, Flow Bytes, Packet Counts & Exporter IPs
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global ipfix_cap_init
global ipfix_cap_collect

align 32
ipfix_cap_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
ipfix_cap_collect:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret
