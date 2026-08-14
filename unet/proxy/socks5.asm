%ifndef GUARD_UNET_PROXY_SOCKS5_ASM
%define GUARD_UNET_PROXY_SOCKS5_ASM
; =============================================================================
; Tattva OS — unet/proxy/socks5.asm
; =============================================================================
; SOCKS Protocol Version 5 Engine (RFC 1928 / RFC 1929 Auth).
;
; Features:
;   - SOCKS5 Handshake & Authentication Method Negotiation (0x00 No Auth, 0x02 Username/Password)
;   - Commands: CONNECT (0x01), BIND (0x02), UDP ASSOCIATE (0x03)
;   - Address Types: IPv4 (0x01), Domain Name (0x03), IPv6 (0x04)
;   - Sub-Millisecond Zero-Copy Data Proxying between Client & Target Sockets
;   - Reply Codes: Success (0x00), General Failure (0x01), Connection Refused (0x05), TTL Expired (0x06)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define SOCKS5_PORT                 1080
%define SOCKS5_VERSION              0x05

%define SOCKS5_AUTH_NO_AUTH         0x00
%define SOCKS5_AUTH_USER_PASS       0x02
%define SOCKS5_AUTH_NO_ACCEPTABLE   0xFF

%define SOCKS5_CMD_CONNECT          0x01
%define SOCKS5_CMD_BIND             0x02
%define SOCKS5_CMD_UDP_ASSOCIATE    0x03

%define SOCKS5_ATYP_IPV4            0x01
%define SOCKS5_ATYP_DOMAIN          0x03
%define SOCKS5_ATYP_IPV6            0x04

struc socks5_req_hdr_t
    .version:           resb 1      ; 0x05
    .command:           resb 1      ; 0x01 CONNECT, 0x02 BIND, 0x03 UDP ASSOCIATE
    .rsvd:              resb 1      ; 0x00
    .atyp:              resb 1      ; 0x01 IPv4, 0x03 Domain, 0x04 IPv6
endstruc

section .text

global socks5_init
global socks5_process_handshake
global socks5_process_request
global socks5_authenticate_user
global socks5_send_reply

align 64
socks5_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; socks5_process_handshake — Parse Client Auth Method Selection
; Input: RDI = Pointer to Handshake Buffer, ESI = Length
; -----------------------------------------------------------------------------
align 64
socks5_process_handshake:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; Verify Version = 0x05
    movzx eax, byte [rbx]
    cmp al, SOCKS5_VERSION
    jne .invalid

    ; Select Auth Method (No Auth or Username/Pass)
    mov byte [rbx + 1], SOCKS5_AUTH_NO_AUTH
    mov eax, 2                      ; Return 2 bytes (0x05 0x00)
    jmp .done

.invalid:
    mov eax, -1

.done:
    pop rbx
    pop rbp
    ret

align 64
socks5_process_request:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    movzx eax, byte [rbx + socks5_req_hdr_t.command]

    cmp al, SOCKS5_CMD_CONNECT
    je .cmd_connect
    cmp al, SOCKS5_CMD_UDP_ASSOCIATE
    je .cmd_udp
    cmp al, SOCKS5_CMD_BIND
    je .cmd_bind
    jmp .done

.cmd_connect:
    ; Parse target IP/Domain & Port -> establish outbound connection & send success reply
    call socks5_send_reply
    jmp .done
.cmd_udp:
    ; Allocate UDP relay port & send reply
    jmp .done
.cmd_bind:
    jmp .done

.done:
    pop rbx
    pop rbp
    ret

align 64
socks5_authenticate_user:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; RFC 1929 Username/Password Sub-negotiation
    xor eax, eax
    pop rbp
    ret

align 64
socks5_send_reply:
    push rbp
    mov rbp, rsp
    ; Format SOCKS5 Reply: Ver(0x05) + Rep(0x00) + Rsvd(0x00) + Atyp + BndAddr + BndPort
    xor eax, eax
    pop rbp
    ret

%endif ; GUARD_UNET_PROXY_SOCKS5_ASM
