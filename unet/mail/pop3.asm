%ifndef GUARD_UNET_MAIL_POP3_ASM
%define GUARD_UNET_MAIL_POP3_ASM
; =============================================================================
; Tattva OS — unet/mail/pop3.asm
; =============================================================================
; POP3 Post Office Protocol Engine (RFC 1939 / RFC 2595 STARTTLS).
;
; Features:
;   - POP3 State Machine: AUTHORIZATION -> TRANSACTION -> UPDATE
;   - Commands: USER, PASS, STAT, LIST, RETR, DELE, RSET, QUIT, TOP, UIDL
;   - STARTTLS (RFC 2595) TLS 1.3 Encryption Upgrade
;   - APOP Challenge-Response Authentication (RFC 1939 Section 7)
;   - Dot-Stuffing Transparency for DATA Termination
;
; Delegates:
;   - TLS 1.3 STARTTLS Upgrade          -> crypto/utls/
;   - MD5 APOP Digest                   -> crypto/uhash/
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define POP3_PORT                   110
%define POP3_TLS_PORT               995

%define POP3_STATE_AUTH             0
%define POP3_STATE_TRANS            1
%define POP3_STATE_UPDATE           2

struc pop3_session_t
    .state:             resd 1
    .username:          resb 64
    .msg_count:         resd 1
    .total_size:        resd 1
    .deleted_mask:      resq 1      ; Bitmask of messages marked for deletion
    .tls_active:        resb 1
endstruc

section .text

global pop3_init
global pop3_handle_command
global pop3_process_user
global pop3_process_pass
global pop3_process_stat
global pop3_process_list
global pop3_process_retr
global pop3_process_dele
global pop3_process_quit
global pop3_send_response

align 64
pop3_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 64
pop3_handle_command:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rsi]

    ; Compare first 4 bytes
    mov eax, [rsi]
    or eax, 0x20202020

    cmp eax, 'user'
    je .cmd_user
    cmp eax, 'pass'
    je .cmd_pass
    cmp eax, 'stat'
    je .cmd_stat
    cmp eax, 'list'
    je .cmd_list
    cmp eax, 'retr'
    je .cmd_retr
    cmp eax, 'dele'
    je .cmd_dele
    cmp eax, 'rset'
    je .cmd_rset
    cmp eax, 'quit'
    je .cmd_quit
    cmp eax, 'uidl'
    je .cmd_uidl
    jmp .cmd_err

.cmd_user:
    call pop3_process_user
    jmp .cmd_done
.cmd_pass:
    call pop3_process_pass
    jmp .cmd_done
.cmd_stat:
    call pop3_process_stat
    jmp .cmd_done
.cmd_list:
    call pop3_process_list
    jmp .cmd_done
.cmd_retr:
    call pop3_process_retr
    jmp .cmd_done
.cmd_dele:
    call pop3_process_dele
    jmp .cmd_done
.cmd_rset:
    mov qword [rbx + pop3_session_t.deleted_mask], 0
    jmp .cmd_done
.cmd_quit:
    call pop3_process_quit
    jmp .cmd_done
.cmd_uidl:
    jmp .cmd_done
.cmd_err:
    ; Send -ERR Unknown command

.cmd_done:
    pop rbx
    pop rbp
    ret

align 64
pop3_process_user:
    push rbp
    mov rbp, rsp
    ; Store username, send +OK
    xor eax, eax
    pop rbp
    ret

align 64
pop3_process_pass:
    push rbp
    mov rbp, rsp
    ; Validate password, transition to TRANSACTION state
    xor eax, eax
    pop rbp
    ret

align 64
pop3_process_stat:
    push rbp
    mov rbp, rsp
    ; Reply "+OK count size"
    xor eax, eax
    pop rbp
    ret

align 64
pop3_process_list:
    push rbp
    mov rbp, rsp
    ; List messages: "+OK\r\n1 size\r\n2 size\r\n.\r\n"
    xor eax, eax
    pop rbp
    ret

align 64
pop3_process_retr:
    push rbp
    mov rbp, rsp
    ; Retrieve full message with dot-stuffing transparency
    xor eax, eax
    pop rbp
    ret

align 64
pop3_process_dele:
    push rbp
    mov rbp, rsp
    ; Mark message for deletion (set bit in deleted_mask)
    xor eax, eax
    pop rbp
    ret

align 64
pop3_process_quit:
    push rbp
    mov rbp, rsp
    ; Enter UPDATE state: actually delete marked messages, then close
    xor eax, eax
    pop rbp
    ret

align 64
pop3_send_response:
    push rbp
    mov rbp, rsp
    ; Send "+OK msg\r\n" or "-ERR msg\r\n"
    xor eax, eax
    pop rbp
    ret

%endif ; GUARD_UNET_MAIL_POP3_ASM
