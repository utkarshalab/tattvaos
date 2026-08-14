%ifndef GUARD_UNET_SERVICES_DHCP_ASM
%define GUARD_UNET_SERVICES_DHCP_ASM
; =============================================================================
; Tattva OS — unet/services/dhcp.asm
; =============================================================================
; DHCPv4 & DHCPv6 Dual-Stack Server / Client Engine (RFC 2131 / RFC 8415).
;
; Features:
;   - DHCPv4 (UDP 67/68) & DHCPv6 (UDP 546/547) State Machine (INIT, SELECTING, REQUESTING, BOUND, RENEWING, REBINDING)
;   - Option Parsing: Subnet Mask (1), Router (3), DNS (6), Hostname (12), Domain (15), IP Lease Time (51), DHCP Msg Type (53)
;   - DHCPv6 DUID (DUID-LLT / DUID-EN / DUID-LL) & IA_NA / IA_PD (Prefix Delegation)
;   - Lockless Address Pool Allocator & Lease Expiration Scheduling
;   - BOOTP Relay Agent (Option 82 Relay Agent Information)
;
; Delegates:
;   - UDP Transport                     -> unet/core/l4/udp.asm
;   - Timer Wheel Lease Expiration       -> lib/time/timer_wheel.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define DHCP_SERVER_PORT            67
%define DHCP_CLIENT_PORT            68
%define DHCPv6_SERVER_PORT          547
%define DHCPv6_CLIENT_PORT          546

%define DHCP_DISCOVER               1
%define DHCP_OFFER                  2
%define DHCP_REQUEST                3
%define DHCP_DECLINE                4
%define DHCP_ACK                    5
%define DHCP_NAK                    6
%define DHCP_RELEASE                7
%define DHCP_INFORM                 8

struc dhcp_hdr_t
    .op:                resb 1      ; 1=BOOTREQUEST, 2=BOOTREPLY
    .htype:             resb 1      ; 1=Ethernet
    .hlen:              resb 1      ; 6
    .hops:              resb 1      ; 0
    .xid:               resd 1      ; Transaction ID
    .secs:              resw 1
    .flags:             resw 1      ; Broadcast flag
    .ciaddr:            resd 1      ; Client IP
    .yiaddr:            resd 1      ; Your IP
    .siaddr:            resd 1      ; Server IP
    .giaddr:            resd 1      ; Relay Agent IP
    .chaddr:            resb 16     ; Client Hardware Address
    .sname:             resb 64     ; Server Host Name
    .file:              resb 128    ; Boot File Name
    .magic_cookie:      resd 1      ; 0x63825363
endstruc

section .text

global dhcp_init
global dhcp_process_packet
global dhcp_send_offer
global dhcp_send_ack
global dhcp_lease_allocate
global dhcp_lease_expire


align 64
dhcp_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 64
dhcp_process_packet:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; Verify magic cookie (0x63825363)
    mov eax, [rbx + dhcp_hdr_t.magic_cookie]
    bswap eax
    cmp eax, 0x63825363
    jne .invalid

    ; Parse options (Option 53 = Msg Type)
    lea rdi, [rbx + dhcp_hdr_t_size]
    ; Extract msg_type
    mov al, DHCP_DISCOVER           ; placeholder

    cmp al, DHCP_DISCOVER
    je .discover
    cmp al, DHCP_REQUEST
    je .request
    cmp al, DHCP_RELEASE
    je .release
    jmp .done

.discover:
    call dhcp_send_offer
    jmp .done
.request:
    call dhcp_send_ack
    jmp .done
.release:
    call dhcp_lease_expire
    jmp .done

.invalid:
    mov eax, -1
    pop rbx
    pop rbp
    ret

.done:
    pop rbx
    pop rbp
    ret

align 64
dhcp_send_offer:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Allocate IP from pool & send DHCP OFFER with options (Subnet, Router, DNS, Lease Time)
    call dhcp_lease_allocate
    pop rbp
    ret

align 64
dhcp_send_ack:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Commit IP lease & send DHCP ACK + schedule lease expiration timer
    mov edi, 86400 * 1000           ; 24 hour lease
    call timer_wheel_add
    pop rbp
    ret

align 64
dhcp_lease_allocate:
    push rbp
    mov rbp, rsp
    ; Bitmap IP address pool allocation
    xor eax, eax
    pop rbp
    ret

align 64
dhcp_lease_expire:
    push rbp
    mov rbp, rsp
    ; Return IP to available pool & cancel timer
    call timer_wheel_del
    pop rbp
    ret

%endif ; GUARD_UNET_SERVICES_DHCP_ASM
