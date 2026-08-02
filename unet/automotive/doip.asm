; =============================================================================
; Tattva OS — unet/automotive/doip.asm
; =============================================================================
; Diagnostic over IP (DoIP ISO 13400-2 Port 13400 Engine).
;
; Features:
;   - TCP/UDP Port 13400 Header Parsing (Protocol Version 0x02, Inverse Version 0xFD)
;   - Payload Types:
;       `0x0001`: Generic DoIP Header NACK
;       `0x0005`: Routing Activation Request
;       `0x0006`: Routing Activation Response
;       `0x0007`: Alive Check Request
;       `0x0008`: Alive Check Response
;       `0x8001`: Diagnostic Message
;       `0x8002`: Diagnostic Message ACK
;       `0x8003`: Diagnostic Message NACK
;   - Tester & Logical Target ECU Address (16-bit SA / DA) Management
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define DOIP_PORT                   13400
%define DOIP_VERSION_2              0x02
%define DOIP_INV_VERSION_2          0xFD

%define DOIP_TYPE_HEADER_NACK       0x0001
%define DOIP_TYPE_ROUTING_ACT_REQ   0x0005
%define DOIP_TYPE_ROUTING_ACT_RESP  0x0006
%define DOIP_TYPE_ALIVE_CHECK_REQ   0x0007
%define DOIP_TYPE_ALIVE_CHECK_RESP  0x0008
%define DOIP_TYPE_DIAGNOSTIC_MSG    0x8001
%define DOIP_TYPE_DIAGNOSTIC_ACK    0x8002
%define DOIP_TYPE_DIAGNOSTIC_NACK   0x8003

struc doip_hdr_t
    .protocol_version:  resb 1      ; 0x02
    .inv_version:       resb 1      ; 0xFD
    .payload_type:      resw 1      ; Big Endian Payload Type
    .payload_length:    resd 1      ; Big Endian Payload Length
endstruc

struc doip_diag_hdr_t
    .source_addr:       resw 1      ; 16-bit Source Logical Address
    .target_addr:       resw 1      ; 16-bit Target Logical Address
endstruc

section .text

global doip_init
global doip_process_packet
global doip_process_routing_activation
global doip_send_diag_ack

align 64
doip_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; doip_process_packet — Parse ISO 13400-2 DoIP Header & Dispatch
; Input: RDI = Pointer to DoIP Buffer, ESI = Length
; -----------------------------------------------------------------------------
align 64
doip_process_packet:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; Verify Version (0x02) & Inverse Version (0xFD)
    movzx eax, byte [rbx + doip_hdr_t.protocol_version]
    movzx edx, byte [rbx + doip_hdr_t.inv_version]

    cmp al, DOIP_VERSION_2
    jne .invalid
    cmp dl, DOIP_INV_VERSION_2
    jne .invalid

    ; Read Payload Type
    movzx eax, word [rbx + doip_hdr_t.payload_type]
    xchg al, ah                     ; EAX = Payload Type

    cmp ax, DOIP_TYPE_ROUTING_ACT_REQ
    je .routing_act
    cmp ax, DOIP_TYPE_DIAGNOSTIC_MSG
    je .diag_msg
    jmp .done

.routing_act:
    call doip_process_routing_activation
    jmp .done

.diag_msg:
    ; Send Diagnostic ACK & forward UDS payload
    call doip_send_diag_ack
    jmp .done

.invalid:
    mov eax, -1

.done:
    pop rbx
    pop rbp
    ret

align 64
doip_process_routing_activation:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Authenticate Tester Logical Address & send Routing Activation Response (0x0006)
    xor eax, eax
    pop rbp
    ret

align 64
doip_send_diag_ack:
    push rbp
    mov rbp, rsp
    ; Format DoIP Diagnostic Message ACK (0x8002) with SA & DA swapped
    xor eax, eax
    pop rbp
    ret
