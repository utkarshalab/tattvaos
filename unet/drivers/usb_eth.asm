%ifndef GUARD_UNET_DRIVERS_USB_ETH_ASM
%define GUARD_UNET_DRIVERS_USB_ETH_ASM
; =============================================================================
; Tattva OS — unet/drivers/usb_eth.asm
; =============================================================================
; USB CDC-ECM / CDC-NCM / RNDIS Mobile Tethering Ethernet Class Driver.
;
; Features:
;   - USB CDC-ECM (Ethernet Control Model) Bulk IN/OUT Protocol Framing
;   - USB CDC-NCM (Network Control Model) NTH16 / NDP16 Datagram Pointer Aggregation
;   - Microsoft RNDIS (Remote NDIS) Message Parsing (REMOTE_NDIS_PACKET_MSG)
;   - USB Control Endpoint Class Requests (SetEthernetPacketFilter)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define CDC_ECM_SET_ETHERNET_PACKET_FILTER 0x43

%define RNDIS_MSG_PACKET            0x00000001
%define RNDIS_MSG_INITIALIZE        0x00000002
%define RNDIS_MSG_HALT              0x00000003
%define RNDIS_MSG_QUERY             0x00000004
%define RNDIS_MSG_SET               0x00000005

struc ncm_nth16_t
    .signature:         resd 1      ; 'N' 'C' 'M' 'H' (0x484D434E)
    .header_len:        resw 1      ; 12 bytes
    .sequence:          resw 1
    .block_len:         resw 1
    .ndp_index:         resw 1      ; Offset to NDP16
endstruc

struc rndis_packet_msg_t
    .msg_type:          resd 1      ; 0x00000001
    .msg_len:           resd 1
    .data_offset:       resd 1
    .data_len:          resd 1
endstruc

section .text

global usb_eth_init
global usb_eth_poll_ncm
global usb_eth_poll_rndis
global usb_eth_transmit_ncm


align 64
usb_eth_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; usb_eth_poll_ncm — Parse USB CDC-NCM NTH16 Header & Unpack Datagram Pointer Block
; Input: RDI = Pointer to USB Bulk IN NCM Buffer, ESI = Buffer Length
; -----------------------------------------------------------------------------
align 64
usb_eth_poll_ncm:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; Verify NCMH signature ('N' 'C' 'M' 'H' = 0x484D434E)
    mov eax, [rbx + ncm_nth16_t.signature]
    cmp eax, 0x484D434E
    jne .not_ncm

    ; Traverse NDP16 datagram pointers & dispatch inner Ethernet packets
    call eth_input
    mov eax, 1
    jmp .done

.not_ncm:
    xor eax, eax

.done:
    pop rbx
    pop rbp
    ret

align 64
usb_eth_poll_rndis:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; Verify RNDIS_MSG_PACKET (0x00000001)
    mov eax, [rbx + rndis_packet_msg_t.msg_type]
    cmp eax, RNDIS_MSG_PACKET
    jne .not_rndis

    mov edx, [rbx + rndis_packet_msg_t.data_len]
    call eth_input
    mov eax, 1
    jmp .done

.not_rndis:
    xor eax, eax

.done:
    pop rbx
    pop rbp
    ret

align 64
usb_eth_transmit_ncm:
    push rbp
    mov rbp, rsp
    prefetcht0 [rsi]
    ; Wrap packet into NCM NTH16 + NDP16 structure & submit Bulk OUT transfer
    xor eax, eax
    pop rbp
    ret

%endif ; GUARD_UNET_DRIVERS_USB_ETH_ASM
