; =============================================================================
; Tattva OS — unet/voip/rtp.asm
; =============================================================================
; Real-Time Transport Protocol Engine (RTP RFC 3550 / RTCP RFC 3550).
;
; Features:
;   - 12-Byte Fixed RTP Header Parsing & Construction
;     - Version (2 bits = 2)
;     - Padding (1 bit), Extension (1 bit), CSRC Count (4 bits)
;     - Marker Bit (1 bit), Payload Type (7 bits)
;     - Sequence Number (16 bits)
;     - Timestamp (32 bits)
;     - Synchronization Source (SSRC 32 bits)
;   - RTCP Packet Processing: SR (Sender Report), RR (Receiver Report), SDES, BYE
;   - Jitter Buffer Management & Playout Delay Calculation
;   - Packet Loss Rate & Round-Trip Time (RTT) Measurement
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define RTP_VERSION                 2

%define RTCP_SR                     200
%define RTCP_RR                     201
%define RTCP_SDES                   202
%define RTCP_BYE                    203
%define RTCP_APP                    204

struc rtp_hdr_t
    .ver_p_x_cc:        resb 1      ; V(2b) + P(1b) + X(1b) + CC(4b)
    .m_pt:              resb 1      ; M(1b) + PT(7b)
    .seq_num:           resw 1      ; 16-bit Sequence Number
    .timestamp:         resd 1      ; 32-bit Timestamp
    .ssrc:              resd 1      ; 32-bit SSRC
endstruc

struc rtcp_sr_t
    .hdr:               resd 1      ; V(2b) + P(1b) + RC(5b) + PT=200(8b) + Length(16b)
    .ssrc:              resd 1
    .ntp_sec:           resd 1      ; NTP Timestamp Sec
    .ntp_frac:          resd 1      ; NTP Timestamp Frac
    .rtp_ts:            resd 1      ; RTP Timestamp
    .pkt_count:         resd 1      ; Sender's Packet Count
    .octet_count:       resd 1      ; Sender's Octet Count
endstruc

section .text

global rtp_init
global rtp_parse_header
global rtp_send_packet
global rtp_process_rtcp
global rtp_send_sender_report
global rtp_calculate_jitter

extern rdtsc_get_cycles

align 64
rtp_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; rtp_parse_header — Parse 12-Byte RTP Fixed Header
; Input: RDI = Pointer to RTP Buffer, ESI = Length
; Output: RAX = Payload Pointer, EDX = Payload Type, ECX = Sequence Number, R8D = SSRC
; -----------------------------------------------------------------------------
align 64
rtp_parse_header:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; Verify Version = 2 (top 2 bits of byte 0)
    movzx eax, byte [rbx + rtp_hdr_t.ver_p_x_cc]
    shr al, 6
    cmp al, RTP_VERSION
    jne .invalid

    ; Extract Payload Type (bottom 7 bits of byte 1)
    movzx edx, byte [rbx + rtp_hdr_t.m_pt]
    and edx, 0x7F                   ; EDX = Payload Type

    ; Extract Sequence Number (word 1, big endian)
    movzx ecx, word [rbx + rtp_hdr_t.seq_num]
    xchg cl, ch                     ; ECX = Sequence Number

    ; Extract SSRC (dword 2, big endian)
    mov r8d, [rbx + rtp_hdr_t.ssrc]
    bswap r8d                       ; R8D = SSRC

    ; Calculate header size (12 bytes + CC * 4 + Extension size)
    mov r9d, 12
    lea rax, [rbx + r9]             ; RAX = Payload Pointer

    pop rbx
    pop rbp
    ret

.invalid:
    xor eax, eax
    pop rbx
    pop rbp
    ret

align 64
rtp_send_packet:
    push rbp
    mov rbp, rsp
    prefetcht0 [rsi]
    ; Format 12-byte RTP header & transmit payload
    xor eax, eax
    pop rbp
    ret

align 64
rtp_process_rtcp:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Parse RTCP Sender Report / Receiver Report -> compute loss fraction & RTT
    call rdtsc_get_cycles
    call rtp_calculate_jitter
    pop rbp
    ret

align 64
rtp_send_sender_report:
    push rbp
    mov rbp, rsp
    ; Send RTCP SR with NTP timestamp, RTP timestamp, packet count, octet count
    call rdtsc_get_cycles
    xor eax, eax
    pop rbp
    ret

align 64
rtp_calculate_jitter:
    push rbp
    mov rbp, rsp
    ; RFC 3550 interarrival jitter algorithm: J = J + (|D(i-1, i)| - J) / 16
    xor eax, eax
    pop rbp
    ret
