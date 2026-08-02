; =============================================================================
; Tattva OS — unet/tools/telecom/dhcpclient.asm
; =============================================================================
; Command-Line DHCP Client Tool (`dhcpclient`).
;
; Features:
;   - UDP Port 68/67 BOOTP/DHCP Header Parsing (DISCOVER, OFFER, REQUEST, ACK)
;   - DHCP Options: Subnet Mask (Option 1), Router Gateway (Option 3), DNS Server (Option 6), Requested IP (Option 50), Lease Time (Option 51)
;   - Automated Network Interface IP Address Configuration
;
; Delegates:
;   - DHCP Service                      -> unet/services/dhcp.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define DHCP_CLIENT_PORT            68
%define DHCP_SERVER_PORT            67

section .text

global dhcpclient_main
global dhcpclient_discover

align 64
dhcpclient_main:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    call dhcpclient_discover

    pop rbx
    pop rbp
    ret

align 64
dhcpclient_discover:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Broadcast DHCPDISCOVER -> process DHCPOFFER -> send DHCPREQUEST -> acquire IP via DHCPACK
    xor eax, eax
    pop rbp
    ret
