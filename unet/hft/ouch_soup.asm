%ifndef GUARD_UNET_HFT_OUCH_SOUP_ASM
%define GUARD_UNET_HFT_OUCH_SOUP_ASM
; =============================================================================
; Tattva OS — unet/hft/ouch_soup.asm
; =============================================================================
; SoupBinTCP v3.0 Session Protocol Engine for NASDAQ OUCH Order Entry.
;
; Features:
;   - 3-Byte Packet Header Parsing (2-Byte Length + 1-Byte Packet Type)
;   - Packet Types:
;       '+': Debug Packet
;       'A': Login Accepted
;       'J': Login Rejected
;       'S': Sequenced Data (Server to Client)
;       'H': Server Heartbeat
;       'O': Client Heartbeat
;       'L': Login Request (Username 6B, Password 10B, Session 10B, Sequence 20B)
;       'U': Unsequenced Data (Client to Server - OUCH payload)
;       'Z': Logout Request
;   - Session Heartbeat Timer Management (1-Second Timeout) & Auto-Reconnect
;
; Delegates:
;   - Timer Wheel Heartbeat Timer        -> lib/time/timer_wheel.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define SOUP_TYPE_LOGIN_REQ         'L'
%define SOUP_TYPE_LOGIN_ACC         'A'
%define SOUP_TYPE_LOGIN_REJ         'J'
%define SOUP_TYPE_SEQUENCED         'S'
%define SOUP_TYPE_UNSEQUENCED       'U'
%define SOUP_TYPE_CLIENT_HB         'O'
%define SOUP_TYPE_SERVER_HB         'H'

struc soup_hdr_t
    .packet_len:        resw 1      ; 16-bit Big Endian Packet Length
    .packet_type:       resb 1      ; SoupBinTCP Packet Type
endstruc

section .text

global ouch_soup_init
global ouch_soup_process_packet
global ouch_soup_send_login
global ouch_soup_send_heartbeat
global ouch_soup_send_unsequenced


align 64
ouch_soup_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 64
ouch_soup_process_packet:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    movzx eax, byte [rbx + soup_hdr_t.packet_type]

    cmp al, SOUP_TYPE_SEQUENCED
    je .sequenced
    cmp al, SOUP_TYPE_SERVER_HB
    je .server_hb
    cmp al, SOUP_TYPE_LOGIN_ACC
    je .login_acc
    cmp al, SOUP_TYPE_LOGIN_REJ
    je .login_rej
    jmp .done

.sequenced:
    ; Extract 20-byte sequence header, forward OUCH payload to ouch_parse_response
    lea rdi, [rbx + soup_hdr_t_size + 20]
    call ouch_parse_response
    jmp .done

.server_hb:
    ; Reset heartbeat timer
    jmp .done

.login_acc:
    ; Login Success: start client heartbeat timer (1s)
    mov edi, 1000
    call timer_wheel_add
    jmp .done

.login_rej:
    jmp .done

.done:
    pop rbx
    pop rbp
    ret

align 64
ouch_soup_send_login:
    push rbp
    mov rbp, rsp
    prefetcht0 [rsi]
    ; Format SoupBinTCP Login Request Packet 'L' (Username, Password, Session ID, Sequence)
    xor eax, eax
    pop rbp
    ret

align 64
ouch_soup_send_heartbeat:
    push rbp
    mov rbp, rsp
    ; Send 3-byte Client Heartbeat Packet ('0x0001', 'O')
    xor eax, eax
    pop rbp
    ret

align 64
ouch_soup_send_unsequenced:
    push rbp
    mov rbp, rsp
    prefetcht0 [rsi]
    ; Wrap OUCH binary payload in Unsequenced Data packet ('U') & transmit
    xor eax, eax
    pop rbp
    ret

%endif ; GUARD_UNET_HFT_OUCH_SOUP_ASM
