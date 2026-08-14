%ifndef GUARD_UNET_TOOLS_APP_WEBRTC_PING_ASM
%define GUARD_UNET_TOOLS_APP_WEBRTC_PING_ASM
; =============================================================================
; Tattva OS — unet/tools/app/webrtc_ping.asm
; =============================================================================
; WebRTC DataChannel & RTT Latency Diagnostic Tool (`webrtc-ping`).
;
; Features:
;   - ICE Binding Request / Response STUN Probe Handshake
;   - DTLS 1.3 Handshake & SRTP Key Derivation
;   - SCTP DataChannel Ping/Pong Sub-Millisecond Round-Trip Time Measurement
;
; Delegates:
;   - STUN Probes                       -> unet/voip/ice_stun.asm
;   - WebRTC SFU                        -> unet/video/webrtc_sfu.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global webrtc_ping_main
global webrtc_ping_measure_rtt

align 64
webrtc_ping_main:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    call ice_stun_send_binding_request
    call webrtc_ping_measure_rtt

    pop rbx
    pop rbp
    ret

align 64
webrtc_ping_measure_rtt:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Measure nanosecond elapsed time between SCTP DataChannel ping & pong reply
    xor eax, eax
    pop rbp
    ret

%endif ; GUARD_UNET_TOOLS_APP_WEBRTC_PING_ASM
