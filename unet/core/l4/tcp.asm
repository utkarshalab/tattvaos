; =============================================================================
; Tattva OS — unet/core/l4/tcp.asm
; =============================================================================
; TCP State Machine Engine (RFC 9293).
;
; Delegates:
;   - TCP Control Block (TCB) Memory Allocation -> lib/mem/slab.asm (`slab_alloc`)
;   - Retransmission & Keepalive Timers         -> lib/time/timer_wheel.asm
;   - Congestion Control Pacing                 -> unet/core/l4/tcp_bbr.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define TCP_STATE_CLOSED            0
%define TCP_STATE_LISTEN            1
%define TCP_STATE_SYN_SENT          2
%define TCP_STATE_SYN_RECV          3
%define TCP_STATE_ESTABLISHED       4
%define TCP_STATE_FIN_WAIT_1        5
%define TCP_STATE_FIN_WAIT_2        6
%define TCP_STATE_CLOSE_WAIT        7
%define TCP_STATE_CLOSING           8
%define TCP_STATE_LAST_ACK          9
%define TCP_STATE_TIME_WAIT         10

struc tcb_t
    .state:             resd 1      ; TCP State (LISTEN, ESTABLISHED, etc.)
    .snd_una:           resd 1      ; Send Unacknowledged
    .snd_nxt:           resd 1      ; Send Next
    .snd_wnd:           resd 1      ; Send Window
    .rcv_nxt:           resd 1      ; Receive Next
    .rcv_wnd:           resd 1      ; Receive Window
    .timer_id:          resd 1      ; Timer Wheel Entry ID
    .src_port:          resw 1
    .dst_port:          resw 1
    .src_ip:            resd 1
    .dst_ip:            resd 1
endstruc

section .text

global tcp_init
global tcp_alloc_tcb
global tcp_process_segment
global tcp_free_tcb

extern slab_alloc
extern slab_free
extern timer_wheel_add

align 32
tcp_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; tcp_alloc_tcb — Allocate TCP Control Block from lib/mem/slab.asm
; Output: RAX = Pointer to tcb_t
; -----------------------------------------------------------------------------
align 32
tcp_alloc_tcb:
    push rbp
    mov rbp, rsp
    mov rdi, tcb_t_size
    call slab_alloc
    pop rbp
    ret

align 32
tcp_process_segment:
    push rbp
    mov rbp, rsp
    ; Process segment & schedule retransmission timer in lib/time/timer_wheel.asm
    call timer_wheel_add
    pop rbp
    ret

align 32
tcp_free_tcb:
    push rbp
    mov rbp, rsp
    call slab_free
    pop rbp
    ret
