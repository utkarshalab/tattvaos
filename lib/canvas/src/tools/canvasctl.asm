; ============================================================================
; canvasctl — Runtime Control (inspect/control server at runtime)
; Usage: canvasctl <cmd> [args]  (commands via serial argv)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

section .text

global tool_main
tool_main:
    PROLOGUE_SAVE rbx, r12
    mov rdi, ctl_banner
    mov rsi, ctl_banner_len
    call tv_log_write
    ; TODO: parse argv, connect to canvasd debug interface
    xor rax, rax
    call tv_task_exit

; ---------------------------------------------------------------------------
; canvasctl subcommands (also callable in-process)
; ---------------------------------------------------------------------------
global canvasctl_clients
canvasctl_clients:
    PROLOGUE
    mov rdi, debug_client_list
    call tv_log_write
    xor rax, rax
    ret

global canvasctl_trace
canvasctl_trace:
    PROLOGUE
    ; rdi = mask
    call trace_set_mask
    ret

global canvasctl_record_start
canvasctl_record_start:
    PROLOGUE
    call record_start
    ret

global canvasctl_record_stop
canvasctl_record_stop:
    PROLOGUE
    call record_stop
    ret

section .rodata
ctl_banner: db "canvasctl 0.1.0", 10, 0
ctl_banner_len: equ $ - ctl_banner
debug_client_list: db "(client list via cw_debug)", 10, 0

section .data
global canvasctl_version
canvasctl_version: dq 0x010000
