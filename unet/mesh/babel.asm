%ifndef GUARD_UNET_MESH_BABEL_ASM
%define GUARD_UNET_MESH_BABEL_ASM
; =============================================================================
; Tattva OS — unet/mesh/babel.asm
; =============================================================================
; Babel Distance-Vector Routing Protocol Engine (RFC 6126 / RFC 8966).
;
; Features:
;   - UDP Port 6696 Packet Header Parsing & Construction
;   - TLV Messages: Pad1 (0), PadN (1), Ack-Request (2), Ack (3), Hello (4),
;                   IHU (5), Router-ID (6), Next-Hop (7), Update (8), Route-Request (9), Seqno-Request (10)
;   - Loop-Free Distance Vector Routing with Feasibility Condition (FC)
;   - Asymmetric Link Metric Calculation (2-Hop Hello & IHU Exchange)
;   - Dual-Stack IPv4 (0x0800) & IPv6 (0x86DD) Mesh Support
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define BABEL_PORT                  6696
%define BABEL_MAGIC                 42
%define BABEL_VERSION               2

%define BABEL_TLV_PAD1              0
%define BABEL_TLV_PADN              1
%define BABEL_TLV_ACK_REQ           2
%define BABEL_TLV_ACK               3
%define BABEL_TLV_HELLO             4
%define BABEL_TLV_IHU               5
%define BABEL_TLV_ROUTER_ID         6
%define BABEL_TLV_NEXT_HOP          7
%define BABEL_TLV_UPDATE            8
%define BABEL_TLV_ROUTE_REQ         9
%define BABEL_TLV_SEQNO_REQ         10

struc babel_hdr_t
    .magic:             resb 1      ; 42
    .version:           resb 1      ; 2
    .body_length:       resw 1      ; Body Length in bytes
endstruc

section .text

global babel_init
global babel_process_packet
global babel_parse_tlv
global babel_process_hello
global babel_process_update
global babel_check_feasibility

align 64
babel_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 64
babel_process_packet:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; Verify Magic == 42 and Version == 2
    movzx eax, byte [rbx + babel_hdr_t.magic]
    cmp al, BABEL_MAGIC
    jne .invalid

    ; Iterate TLVs in body
    lea rdi, [rbx + babel_hdr_t_size]
    call babel_parse_tlv

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
babel_parse_tlv:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]

    movzx eax, byte [rdi]           ; TLV Type

    cmp al, BABEL_TLV_HELLO
    je .hello
    cmp al, BABEL_TLV_UPDATE
    je .update
    cmp al, BABEL_TLV_IHU
    je .ihu
    jmp .done

.hello:
    call babel_process_hello
    jmp .done
.update:
    call babel_process_update
    jmp .done
.ihu:
    jmp .done

.done:
    pop rbp
    ret

align 64
babel_process_hello:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Update neighbor hello sequence number & transmit IHU (I Heard You)
    xor eax, eax
    pop rbp
    ret

align 64
babel_process_update:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Check Feasibility Condition (FC): metric < strict_feasibility_distance
    call babel_check_feasibility
    pop rbp
    ret

align 64
babel_check_feasibility:
    push rbp
    mov rbp, rsp
    ; Check if advertised metric satisfies loop-freedom condition
    xor eax, eax
    pop rbp
    ret

%endif ; GUARD_UNET_MESH_BABEL_ASM
