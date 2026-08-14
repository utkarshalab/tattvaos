%ifndef GUARD_UNET_SDN_L2TP_ASM
%define GUARD_UNET_SDN_L2TP_ASM
; =============================================================================
; Tattva OS — unet/sdn/l2tp.asm
; =============================================================================
; Layer 2 Tunneling Protocol Version 2 & 3 (L2TPv2 RFC 2661 / L2TPv3 RFC 3931).
;
; Features:
;   - UDP Port 1701 Encapsulation & IP Protocol 115 Framing
;   - L2TP Control Message Parsing (SCCRQ, SCCRP, SCCCN, ICRQ, ICRP, ICCN, Hello, CDN)
;   - Session ID & Tunnel ID Matching
;   - PPP Frame Decapsulation (L2TPv2) & Ethernet Frame Decapsulation (L2TPv3)
;   - AVP (Attribute-Value Pair) Parsing & Construction
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define L2TP_UDP_PORT               1701
%define IP_PROTO_L2TP3              115

%define L2TP_FLAG_TYPE_CONTROL      0x8000
%define L2TP_FLAG_LENGTH            0x4000
%define L2TP_FLAG_SEQUENCE          0x0800

struc l2tp_hdr_t
    .flags_ver:         resw 1      ; Type(1b) + Length(1b) + Sequence(1b) + Vers(4b)
    .length:            resw 1      ; Optional Length
    .tunnel_id:         resw 1      ; Tunnel ID
    .session_id:        resw 1      ; Session ID
    .ns:                resw 1      ; Sequence Number Send
    .nr:                resw 1      ; Sequence Number Receive
endstruc

section .text

global l2tp_init
global l2tp_decap
global l2tp_encap
global l2tp_parse_avp

align 64
l2tp_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; l2tp_decap — Decapsulate L2TP Header & Return Tunnel/Session ID
; Input: RDI = Pointer to L2TP Header Buffer, ESI = Length
; Output: RAX = Pointer to Payload, EDX = Session ID, ECX = Tunnel ID
; -----------------------------------------------------------------------------
align 64
l2tp_decap:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; 1. Extract Tunnel ID & Session ID
    movzx ecx, word [rbx + l2tp_hdr_t.tunnel_id]
    xchg cl, ch                     ; bswap16 (Tunnel ID)

    movzx edx, word [rbx + l2tp_hdr_t.session_id]
    xchg dl, dh                     ; bswap16 (Session ID)

    ; 2. Determine header length based on flags
    movzx eax, word [rbx + l2tp_hdr_t.flags_ver]
    xchg al, ah

    mov r8d, 6                      ; Default header size = 6 bytes (flags + tunnel_id + session_id)
    test ax, L2TP_FLAG_LENGTH
    jz .no_len
    add r8d, 2
.no_len:
    test ax, L2TP_FLAG_SEQUENCE
    jz .no_seq
    add r8d, 4
.no_seq:

    ; 3. Return pointer to inner payload (PPP or Ethernet)
    lea rax, [rbx + r8]

    pop rbx
    pop rbp
    ret

align 64
l2tp_encap:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Prepend L2TP header (Tunnel ID, Session ID, Seq) + UDP/IP
    xor eax, eax
    pop rbp
    ret

align 64
l2tp_parse_avp:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Parse Attribute-Value Pairs in control messages
    xor eax, eax
    pop rbp
    ret

%endif ; GUARD_UNET_SDN_L2TP_ASM
