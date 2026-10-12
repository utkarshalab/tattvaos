; ============================================================================
; canvas_record / canvas_replay — CLI Wrappers Around Record/Replay
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

section .text

global tool_main
tool_main:
    PROLOGUE_SAVE rbx
    mov rdi, rec_banner
    mov rsi, rec_banner_len
    call tv_log_write
    ; TODO: argv: canvas-record <out.cwprec> / canvas-replay <in.cwprec>
    xor rax, rax
    call tv_task_exit

global canvas_record_run
canvas_record_run:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov rdi, rbx
    mov rsi, r12
    mov rdx, 0
    ; path len computed by caller in rdx
    call record_start
    ret

section .rodata
rec_banner: db "canvas-record 0.1.0", 10, 0
rec_banner_len: equ $ - rec_banner

section .data
global canvas_record_version
canvas_record_version: dq 0x010000
