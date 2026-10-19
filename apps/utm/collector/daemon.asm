; UTM Collector - Daemon Entry Point
; Pure Assembly Implementation

%ifndef _UTM_DAEMON_ASM_
%define _UTM_ENTERPRISE_DAEMON_ASM_

%include "constants.inc"
%include "structures.inc"
%include "syscalls.inc"

section .data
utm_daemon_running    dq 1
utm_daemon_pid        resq 1

section .bss

section .text

global _start
global utm_daemon_main
global utm_daemon_signal_handler
global utm_daemon_stop

extern utm_sampler_main
extern utm_ring_init_all

; ----------------------------------------------------------
; _start - Program entry point
; ----------------------------------------------------------
_start:
    call utm_daemon_main
    
    mov rax, 60
    xor rdi, rdi
    syscall

; ----------------------------------------------------------
; utm_daemon_main - Main daemon entry point
; ----------------------------------------------------------
utm_daemon_main:
    ; Get our PID for self-monitoring
    mov rax, 39          ; sys_getpid
    syscall
    mov [utm_daemon_pid], rax
    
    call utm_ring_init_all
    
    call utm_sampler_main
    
    ret

; ----------------------------------------------------------
; utm_daemon_signal_handler - Handle signals
; ----------------------------------------------------------
utm_daemon_signal_handler:
    mov qword [utm_daemon_running], 0
    ret

; ----------------------------------------------------------
; utm_daemon_stop - Stop the daemon gracefully
; ----------------------------------------------------------
utm_daemon_stop:
    mov qword [utm_daemon_running], 0
    ret

%endif