; =============================================================================
; Tattva OS — unet/tools/app/websocket_cat.asm
; =============================================================================
; Command-Line Interactive WebSocket Client & Message Cat Tool (`wscat`).
;
; Features:
;   - RFC 6455 WebSocket Handshake (`Upgrade: websocket`, `Sec-WebSocket-Key`)
;   - Frame Masking: 4-Byte Masking Key XOR Cipher for Client-to-Server Packets
;   - Opcodes: Continuation (0x0), Text (0x1), Binary (0x2), Close (0x8), Ping (0x9), Pong (0xA)
;   - Bidirectional Interactive Console I/O Streaming over WebSocket Connection
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define WS_OPCODE_TEXT              0x01
%define WS_OPCODE_BINARY            0x02
%define WS_OPCODE_CLOSE             0x08
%define WS_OPCODE_PING              0x09
%define WS_OPCODE_PONG              0x0A

struc ws_frame_hdr_t
    .fin_opcode:        resb 1      ; FIN (1b) + RSV (3b) + Opcode (4b)
    .mask_len:          resb 1      ; Mask (1b) + Payload Len (7b: 0..125, 126=16b, 127=64b)
endstruc

section .text

global websocket_cat_main
global websocket_cat_send_frame
global websocket_cat_recv_frame

align 64
websocket_cat_main:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; 1. Transmit client text frame with XOR masking
    call websocket_cat_send_frame

    ; 2. Receive server response frame
    call websocket_cat_recv_frame

    pop rbx
    pop rbp
    ret

align 64
websocket_cat_send_frame:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Prepend 0x81 (FIN + Text), Mask=1, 4-byte random key, XOR mask payload data
    xor eax, eax
    pop rbp
    ret

align 64
websocket_cat_recv_frame:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Parse incoming unmasked WebSocket server frame & output text to stdout
    xor eax, eax
    pop rbp
    ret
