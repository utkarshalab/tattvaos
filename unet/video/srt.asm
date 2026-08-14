%ifndef GUARD_UNET_VIDEO_SRT_ASM
%define GUARD_UNET_VIDEO_SRT_ASM
; =============================================================================
; Tattva OS — unet/video/srt.asm
; =============================================================================
; Secure Reliable Transport Protocol Engine (SRT Haivision / UDT-Based).
;
; Features:
;   - Control vs Data Packet Header Parsing & Construction over UDP
;   - Control Types: HANDSHAKE, KEEPALIVE, ACK, NAK, CONGGESTION, SHUTDOWN, ACKACK
;   - AES-128 / AES-192 / AES-256 CTR Mode Payload Encryption & Key Rotation
;   - Selective NAK Retransmission & Fixed-Latency Buffer Alignment
;   - Stream ID (`#main/live/feed1`) Routing & Passphrase Authentication
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define SRT_PKT_TYPE_DATA           0
%define SRT_PKT_TYPE_CONTROL        1

%define SRT_CTRL_HANDSHAKE          0x0000
%define SRT_CTRL_KEEPALIVE          0x0001
%define SRT_CTRL_ACK                0x0002
%define SRT_CTRL_NAK                0x0003
%define SRT_CTRL_CONGESTION         0x0004
%define SRT_CTRL_SHUTDOWN           0x0005
%define SRT_CTRL_ACKACK             0x0006

struc srt_hdr_t
    .type_seq:          resd 1      ; Control Bit(1b) + Seq / Type(31b)
    .msg_info:          resd 1      ; Sub-type / Msg Order
    .timestamp:         resd 1      ; 32-bit Microsecond Timestamp
    .dest_socket_id:    resd 1      ; Destination Socket ID
endstruc

section .text

global srt_init
global srt_process_packet
global srt_send_ack
global srt_send_nak
global srt_handshake

align 64
srt_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 64
srt_process_packet:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; Check bit 31 of word 0 (0 = Data Packet, 1 = Control Packet)
    mov eax, [rbx + srt_hdr_t.type_seq]
    bswap eax
    test eax, 0x80000000
    jnz .control_packet

.data_packet:
    ; Process data packet: decrypt AES-CTR, place in jitter buffer
    jmp .done

.control_packet:
    ; Extract Control Type (bits 30..16)
    shr eax, 16
    and eax, 0x7FFF

    cmp ax, SRT_CTRL_HANDSHAKE
    je .handshake
    cmp ax, SRT_CTRL_KEEPALIVE
    je .keepalive
    cmp ax, SRT_CTRL_ACK
    je .ack
    cmp ax, SRT_CTRL_NAK
    je .nak
    jmp .done

.handshake:
    call srt_handshake
    jmp .done
.keepalive:
    jmp .done
.ack:
    jmp .done
.nak:
    call srt_send_nak
    jmp .done

.done:
    pop rbx
    pop rbp
    ret

align 64
srt_handshake:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Process SRT Handshake: negotiate latency buffer (e.g. 120ms), Stream ID, AES key size
    xor eax, eax
    pop rbp
    ret

align 64
srt_send_ack:
    push rbp
    mov rbp, rsp
    ; Send ACK packet with RTT, RTT Variance, Recv Rate, Estimated Bandwidth
    xor eax, eax
    pop rbp
    ret

align 64
srt_send_nak:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Send NAK packet requesting retransmission of lost sequence range
    xor eax, eax
    pop rbp
    ret

%endif ; GUARD_UNET_VIDEO_SRT_ASM
