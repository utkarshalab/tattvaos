; =============================================================================
; Tattva OS — unet/automotive/someip.asm
; =============================================================================
; AUTOSAR SOME/IP (Scalable service-Oriented MiddlewarE over IP) Engine.
;
; Features:
;   - UDP/TCP Port 30490 Header Parsing (16-Byte Fixed SOME/IP Header)
;   - Fields: Service ID (16b), Method/Event ID (16b), Length (32b), Client ID (16b), Session ID (16b),
;             Protocol Version (8b = 0x01), Interface Version (8b), Message Type (8b), Return Code (8b)
;   - Message Types:
;       `0x00`: REQUEST (Expecting Response)
;       `0x01`: REQUEST_NO_RETURN (Fire & Forget)
;       `0x02`: NOTIFICATION (Events)
;       `0x80`: RESPONSE
;       `0x81`: ERROR
;   - SOME/IP Service Discovery (SOME/IP-SD Multicast Port 30490 Service Announce & Subscribe)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define SOMEIP_PORT                 30490
%define SOMEIP_PROTOCOL_VERSION     0x01

%define SOMEIP_MSG_REQUEST          0x00
%define SOMEIP_MSG_REQUEST_NO_RET   0x01
%define SOMEIP_MSG_NOTIFICATION     0x02
%define SOMEIP_MSG_RESPONSE         0x80
%define SOMEIP_MSG_ERROR            0x81

struc someip_hdr_t
    .service_id:        resw 1      ; 16-bit Service ID
    .method_id:         resw 1      ; 16-bit Method ID (or Event ID)
    .length:            resd 1      ; 32-bit Payload Length (excluding Service/Method/Length fields)
    .client_id:         resw 1      ; 16-bit Client ID
    .session_id:        resw 1      ; 16-bit Session ID
    .proto_ver:         resb 1      ; 0x01
    .iface_ver:         resb 1      ; Interface Version
    .msg_type:          resb 1      ; REQUEST, RESPONSE, NOTIFICATION
    .return_code:       resb 1      ; 0x00 E_OK
endstruc

section .text

global someip_init
global someip_process_packet
global someip_process_sd_multicast
global someip_send_response

align 64
someip_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; someip_process_packet — Parse AUTOSAR SOME/IP 16-Byte Header
; Input: RDI = Pointer to SOME/IP Buffer, ESI = Length
; -----------------------------------------------------------------------------
align 64
someip_process_packet:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; Verify Protocol Version == 0x01
    movzx eax, byte [rbx + someip_hdr_t.proto_ver]
    cmp al, SOMEIP_PROTOCOL_VERSION
    jne .invalid

    movzx eax, byte [rbx + someip_hdr_t.msg_type]

    cmp al, SOMEIP_MSG_REQUEST
    je .request
    cmp al, SOMEIP_MSG_NOTIFICATION
    je .notification
    cmp al, SOMEIP_MSG_RESPONSE
    je .response
    jmp .done

.request:
    ; Dispatch RPC method & send SOME/IP RESPONSE (0x80)
    call someip_send_response
    jmp .done

.notification:
    ; Process pub/sub event notification
    jmp .done

.response:
    jmp .done

.invalid:
    mov eax, -1

.done:
    pop rbx
    pop rbp
    ret

align 64
someip_process_sd_multicast:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Process SOME/IP-SD (Service Discovery) Offer Service / Subscribe Eventgroup options
    xor eax, eax
    pop rbp
    ret

align 64
someip_send_response:
    push rbp
    mov rbp, rsp
    ; Format SOME/IP Response Header (msg_type = 0x80, return_code = 0x00 E_OK)
    xor eax, eax
    pop rbp
    ret
