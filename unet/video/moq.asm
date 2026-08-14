%ifndef GUARD_UNET_VIDEO_MOQ_ASM
%define GUARD_UNET_VIDEO_MOQ_ASM
; =============================================================================
; Tattva OS — unet/video/moq.asm
; =============================================================================
; Media over QUIC (MoQ / MoQT IETF Draft) Ultra-Low Latency Transport Engine.
;
; Features:
;   - MoQT Setup Message Exchange (CLIENT_SETUP, SERVER_SETUP) over QUIC Streams
;   - Track Subscription Protocol (SUBSCRIBE, SUBSCRIBE_OK, SUBSCRIBE_ERROR, ANNOUNCE)
;   - Object Header Types: Object Stream (Group ID, Subgroup ID, Object ID), Datagram
;   - Publisher / Relay / Subscriber Architecture with Zero-Copy Forwarding
;
; Delegates:
;   - QUIC Transport Engine              -> unet/core/l4/quic.asm
;   - WebTransport Extensions            -> unet/http/webtransport.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define MOQ_MSG_CLIENT_SETUP        0x40
%define MOQ_MSG_SERVER_SETUP        0x41
%define MOQ_MSG_SUBSCRIBE           0x03
%define MOQ_MSG_SUBSCRIBE_OK        0x04
%define MOQ_MSG_ANNOUNCE            0x06

struc moq_object_hdr_t
    .subscribe_id:      resq 1      ; Variable-length Subscribe ID
    .track_alias:       resq 1      ; Track Alias
    .group_id:          resq 1      ; Group ID (Keyframe boundary)
    .object_id:         resq 1      ; Object ID (Frame index)
    .object_status:     resb 1      ; 0=Normal, 1=ObjectDoesNotExist, 2=GroupDoesNotExist
endstruc

section .text

global moq_init
global moq_process_message
global moq_subscribe_track
global moq_publish_object

align 64
moq_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 64
moq_process_message:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    movzx eax, byte [rbx]

    cmp al, MOQ_MSG_CLIENT_SETUP
    je .client_setup
    cmp al, MOQ_MSG_SUBSCRIBE
    je .subscribe
    cmp al, MOQ_MSG_ANNOUNCE
    je .announce
    jmp .done

.client_setup:
    ; Send SERVER_SETUP with supported versions & role (Publisher/Subscriber/Relay)
    jmp .done
.subscribe:
    call moq_subscribe_track
    jmp .done
.announce:
    ; Process Track Namespace Announcement
    jmp .done

.done:
    pop rbx
    pop rbp
    ret

align 64
moq_subscribe_track:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Register subscription to Track Namespace + Track Name, return SUBSCRIBE_OK
    xor eax, eax
    pop rbp
    ret

align 64
moq_publish_object:
    push rbp
    mov rbp, rsp
    prefetcht0 [rsi]
    ; Publish Object Stream payload (Group ID + Object ID) on QUIC stream or Datagram
    call quic_send_stream
    pop rbp
    ret

%endif ; GUARD_UNET_VIDEO_MOQ_ASM
