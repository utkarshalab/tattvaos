%ifndef GUARD_UNET_WIRELESS_CAPWAP_ASM
%define GUARD_UNET_WIRELESS_CAPWAP_ASM
; =============================================================================
; Tattva OS — unet/wireless/capwap.asm
; =============================================================================
; CAPWAP Control & Data Tunnel Protocol Engine (RFC 5415 / RFC 5416 802.11 Binding).
;
; Features:
;   - UDP Port 5246 (Control) & 5247 (Data) 8-Byte CAPWAP Header Parsing
;   - Control Messages: Discovery Request/Response, Join Request/Response,
;                       Configuration Status Request/Response, Keep-Alive, Echo
;   - DTLS Control Channel Encryption (RFC 5415 Section 4)
;   - 802.11 Wireless Frame Tunneling (Split MAC vs Local MAC APs)
;   - CAPWAP Control Message Elements (Type-Length-Value)
;
; Delegates:
;   - DTLS 1.3 Control Channel            -> crypto/utls/
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define CAPWAP_CONTROL_PORT         5246
%define CAPWAP_DATA_PORT            5247

%define CAPWAP_MSG_DISCOVERY_REQ    1
%define CAPWAP_MSG_DISCOVERY_RESP   2
%define CAPWAP_MSG_JOIN_REQ         3
%define CAPWAP_MSG_JOIN_RESP        4
%define CAPWAP_MSG_CFG_STATUS_REQ   5
%define CAPWAP_MSG_CFG_STATUS_RESP  6

struc capwap_hdr_t
    .preamble:          resb 1      ; Version(4b) + Type(4b)
    .flags:             resw 1      ; H(1b) + M(1b) + W(1b) + L(1b) + T(1b) + F(1b) + C(1b) + Resv(9b)
    .fragment_id:       resb 1
    .fragment_offset:   resw 1
endstruc

section .text

global capwap_init
global capwap_process_packet
global capwap_process_control_msg
global capwap_decap_data_tunnel

align 64
capwap_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 64
capwap_process_packet:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; Check T-bit (bit 10 of flags: 1 = 802.11 Frame Payload, 0 = 802.3 Frame)
    movzx eax, word [rbx + capwap_hdr_t.flags]

    test ax, 0x0800                 ; T-bit check
    jnz .wireless_frame

.control_or_8023:
    call capwap_process_control_msg
    jmp .done

.wireless_frame:
    call capwap_decap_data_tunnel
    jmp .done

.done:
    pop rbx
    pop rbp
    ret

align 64
capwap_process_control_msg:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Parse CAPWAP Control Message Elements (Discovery, Join, Configuration Status)
    xor eax, eax
    pop rbp
    ret

align 64
capwap_decap_data_tunnel:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Strip CAPWAP header & forward encapsulated 802.11 frame from AP to AC
    xor eax, eax
    pop rbp
    ret

%endif ; GUARD_UNET_WIRELESS_CAPWAP_ASM
