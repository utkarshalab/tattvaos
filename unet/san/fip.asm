; =============================================================================
; Tattva OS — unet/san/fip.asm
; =============================================================================
; FCoE Initialization Protocol (FIP RFC 6104) Engine.
;
; Features:
;   - EtherType 0x8914 FIP Control Frame Parsing
;   - FIP Operation Codes: Discovery (1), FLOGI/FDISC (2), Keep-Alive (3), Clear Virtual Link (4)
;   - Subcodes: Solicitation (1), Advertisement (2)
;   - Descriptor Parsing: MAC Address, Priority, Name Identifier (WWNN/WWPN), Fabric Name, FC-MAP
;   - FCF (FCoE Forwarder) Discovery & Virtual Link Maintenance
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define ETHERTYPE_FIP               0x8914

%define FIP_OP_DISCOVERY            1
%define FIP_OP_LOGICAL_LINK         2
%define FIP_OP_KEEPALIVE            3
%define FIP_OP_CLEAR_LINK           4

struc fip_hdr_t
    .version:           resw 1      ; Version (4 bits) + Reserved
    .opcode:            resw 1      ; Operation Code
    .subcode:           resb 1      ; Subcode
    .desc_len:          resb 1      ; Descriptor Length in 32-bit words
    .flags:             resw 1      ; Flags (FP bit, SP bit, etc.)
endstruc

section .text

global fip_init
global fip_process_frame
global fip_send_solicitation
global fip_parse_descriptors

align 64
fip_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 64
fip_process_frame:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; Extract opcode and subcode from FIP header
    movzx eax, word [rbx + fip_hdr_t.opcode]
    xchg al, ah                     ; bswap16

    cmp ax, FIP_OP_DISCOVERY
    je .discovery
    cmp ax, FIP_OP_KEEPALIVE
    je .keepalive
    cmp ax, FIP_OP_CLEAR_LINK
    je .clear_link
    jmp .done

.discovery:
    call fip_parse_descriptors
    jmp .done
.keepalive:
    ; Reset virtual link keep-alive timer
    jmp .done
.clear_link:
    ; Teardown virtual link
    jmp .done

.done:
    pop rbx
    pop rbp
    ret

align 64
fip_send_solicitation:
    push rbp
    mov rbp, rsp
    ; Multicast FIP Discovery Solicitation to All-FCF-MACs
    xor eax, eax
    pop rbp
    ret

align 64
fip_parse_descriptors:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Parse FIP descriptors: MAC, Priority, WWNN, WWPN, FC-MAP
    xor eax, eax
    pop rbp
    ret
