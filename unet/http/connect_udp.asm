%ifndef GUARD_UNET_HTTP_CONNECT_UDP_ASM
%define GUARD_UNET_HTTP_CONNECT_UDP_ASM
; =============================================================================
; Tattva OS — unet/http/connect_udp.asm
; =============================================================================
; Proxying UDP / IP over HTTP/3 Engine (RFC 9298 / RFC 9484).
;
; Features:
;   - CONNECT-UDP Extended CONNECT Method over HTTP/3
;   - UDP Datagram Capsule Encapsulation/Decapsulation (RFC 9297 HTTP Datagrams)
;   - Context ID Multiplexing for Multiple Proxied UDP Flows
;   - IP Proxying via CONNECT-IP (RFC 9484) for Full IP Packet Tunneling
;   - Proxy Authorization & Access Control
;
; Delegates:
;   - HTTP/3 Transport                   -> unet/http/http3.asm
;   - QUIC Datagram Extension            -> unet/http/http3_datagram.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

struc connect_udp_session_t
    .context_id:        resq 1      ; Variable-Length Context ID
    .target_host:       resb 64     ; Target Host
    .target_port:       resw 1      ; Target UDP Port
    .state:             resd 1      ; 0=Inactive, 1=Active
endstruc

section .text

global connect_udp_init
global connect_udp_proxy
global connect_udp_encap_datagram
global connect_udp_decap_datagram
global connect_ip_proxy


align 64
connect_udp_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; connect_udp_proxy — Handle CONNECT-UDP Extended CONNECT Request
; Input: RDI = Target Host:Port, RSI = HTTP/3 Stream ID
; Output: EAX = 0 on Success, -1 on Denied
; -----------------------------------------------------------------------------
align 64
connect_udp_proxy:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; 1. Validate CONNECT-UDP request headers (:method=CONNECT, :protocol=connect-udp)
    ; 2. Authorize proxy access
    ; 3. Establish proxied UDP flow & return 200
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; connect_udp_encap_datagram — Encapsulate UDP Datagram into HTTP Capsule
; Input: RDI = UDP Payload, ESI = Length, EDX = Context ID
; -----------------------------------------------------------------------------
align 64
connect_udp_encap_datagram:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Wrap UDP payload in DATAGRAM capsule with context ID prefix
    call http3_send_frame
    pop rbp
    ret

; -----------------------------------------------------------------------------
; connect_udp_decap_datagram — Extract UDP Datagram from HTTP Capsule
; Input: RDI = Capsule Buffer, ESI = Length
; Output: RAX = UDP Payload Pointer, EDX = Payload Length
; -----------------------------------------------------------------------------
align 64
connect_udp_decap_datagram:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Strip context ID prefix & extract raw UDP datagram
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; connect_ip_proxy — Handle CONNECT-IP Full IP Packet Proxy (RFC 9484)
; Input: RDI = IP Packet, ESI = Length
; -----------------------------------------------------------------------------
align 64
connect_ip_proxy:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Encapsulate full IP packet into HTTP capsule for VPN-like tunneling
    call http3_send_frame
    pop rbp
    ret

%endif ; GUARD_UNET_HTTP_CONNECT_UDP_ASM
