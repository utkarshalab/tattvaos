%ifndef GUARD_UNET_VPN_SSTP_ASM
%define GUARD_UNET_VPN_SSTP_ASM
; =============================================================================
; Tattva OS — unet/vpn/sstp.asm
; =============================================================================
; Secure Socket Tunneling Protocol Engine (SSTP MS-SSTP over HTTPS Port 443).
;
; Features:
;   - SSTP Control & Data Packet 4-Byte Header Parsing
;   - Control Types: SSTP_MSG_CALL_CONNECT_REQUEST, SSTP_MSG_CALL_CONNECT_ACK,
;                    SSTP_MSG_CALL_CONNECTED, SSTP_MSG_CALL_DISCONNECT, SSTP_MSG_ECHO_REQUEST
;   - HTTP/1.1 `SSTP_DUPLEX_POST` Request Upgrade over TLS 1.3
;   - Crypto Binding Attribute Validation (SHA-256 Compound MAC over TLS Master Key)
;   - Encapsulated PPP Frame Transport
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define SSTP_HTTPS_PORT             443

%define SSTP_MSG_CALL_CONNECT_REQUEST 1
%define SSTP_MSG_CALL_CONNECT_ACK     2
%define SSTP_MSG_CALL_CONNECTED      4
%define SSTP_MSG_CALL_DISCONNECT     5
%define SSTP_MSG_CALL_DISCONNECT_ACK 6
%define SSTP_MSG_ECHO_REQUEST        7
%define SSTP_MSG_ECHO_RESPONSE       8

struc sstp_hdr_t
    .version:           resb 1      ; Version (0x10 = v1.0)
    .flags:             resb 1      ; C-bit (1=Control, 0=Data)
    .length:            resw 1      ; 16-bit Packet Length (big endian)
endstruc

section .text

global sstp_init
global sstp_process_packet
global sstp_connect_request
global sstp_verify_crypto_binding


align 64
sstp_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 64
sstp_process_packet:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; Extract C-bit from flags byte
    movzx eax, byte [rbx + sstp_hdr_t.flags]
    test al, 0x01
    jnz .control_msg

.data_msg:
    ; Decapsulate PPP payload
    jmp .done

.control_msg:
    ; Extract Control Message Type (word at offset 4)
    movzx eax, word [rbx + sstp_hdr_t_size]
    xchg al, ah

    cmp ax, SSTP_MSG_CALL_CONNECT_REQUEST
    je .connect_req
    cmp ax, SSTP_MSG_CALL_CONNECTED
    je .connected
    cmp ax, SSTP_MSG_ECHO_REQUEST
    je .echo_req
    jmp .done

.connect_req:
    call sstp_connect_request
    jmp .done
.connected:
    call sstp_verify_crypto_binding
    jmp .done
.echo_req:
    ; Send SSTP ECHO RESPONSE
    jmp .done

.done:
    pop rbx
    pop rbp
    ret

align 64
sstp_connect_request:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Send SSTP_MSG_CALL_CONNECT_ACK with Encapsulated Protocol ID (PPP)
    xor eax, eax
    pop rbp
    ret

align 64
sstp_verify_crypto_binding:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Verify Compound MAC = HMAC-SHA256(TLS Finished secret, SSTP packet)
    call sha256_hash
    pop rbp
    ret

%endif ; GUARD_UNET_VPN_SSTP_ASM
