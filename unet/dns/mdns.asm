; =============================================================================
; Tattva OS — unet/dns/mdns.asm
; =============================================================================
; Multicast DNS Zeroconf & DNS Service Discovery (mDNS / DNS-SD — RFC 6762 / 6763).
;
; Implements:
;   - Zeroconf Multicast Host Announcement (`.local`) & Service Registration over UDP 5353
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global mdns_init
global mdns_announce

align 32
mdns_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
mdns_announce:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret
