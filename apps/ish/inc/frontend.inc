; =============================================================================
; File     : apps/ish/inc/frontend.inc
; Project  : Tattva OS — Ishana Shell
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: I/O frontend interface — UART now, Canvas later.
; =============================================================================

%ifndef FRONTEND_INC
%define FRONTEND_INC

%include "inc/ish.inc"

; -----------------------------------------------------------------------------
; Frontend VTable — all I/O goes through this abstraction
; -----------------------------------------------------------------------------
struc io_frontend_t
    .name          resq 1      ; "uart0", "canvas_terminal", "pipe"
    .init          resq 1      ; fn() -> void
    .shutdown      resq 1      ; fn() -> void
    .read_line     resq 1      ; fn(buf, max_len) -> bytes_read (rax) or -1
    .write         resq 1      ; fn(ptr, len) -> void
    .write_str     resq 1      ; fn(str) -> void
    .write_char    resq 1      ; fn(char) -> void
    .set_prompt    resq 1      ; fn(str) -> void
    .clear_line    resq 1      ; fn() -> void
    .move_cursor   resq 1      ; fn(col, row) -> void
    .get_char      resq 1      ; fn() -> char (rax) or -1
    .is_tty        resq 1      ; fn() -> 1 if interactive terminal
    .get_size      resq 1      ; fn(&cols, &rows) -> void
    .private       resq 1      ; frontend-specific state
endstruc

IO_FRONTEND_SIZE          equ 144

; -----------------------------------------------------------------------------
; Standard Frontend IDs
; -----------------------------------------------------------------------------
FRONTEND_UART             equ 0
FRONTEND_CANVAS           equ 1
FRONTEND_PIPE             equ 2

%endif ; FRONTEND_INC