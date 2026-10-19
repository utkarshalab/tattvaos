; =============================================================================
; File     : apps/ish/src/line/history.asm
; Project  : Tattva OS — Ishana Shell
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Command history ring buffer.
; =============================================================================

%ifndef ISH_HISTORY_ASM
%define ISH_HISTORY_ASM

%include "inc/ish.inc"

bits 64

section .bss
align 16
history_entries:    resb ISH_MAX_HISTORY * 256   ; 256 bytes per entry
history_count:      resq 1
history_index:      resq 1

section .text

; -----------------------------------------------------------------------------
; history_init — Initialize history subsystem
; -----------------------------------------------------------------------------
global history_init
history_init:
    PROLOGUE_SAVE rbx
    mov     rdi, history_entries
    mov     rcx, ISH_MAX_HISTORY * 256 / 8
    xor     rax, rax
    cld
    rep     stosq
    mov     qword [history_count], 0
    mov     qword [history_index], 0
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; history_add — Add a command to history
; Input:  rdi = command string
; -----------------------------------------------------------------------------
global history_add
history_add:
    PROLOGUE_SAVE rbx, rcx

    test    rdi, rdi
    jz      .history_done

    mov     rbx, [history_count]
    cmp     rbx, ISH_MAX_HISTORY
    jge     .history_full

    ; Copy command to history slot
    mov     rcx, 256 / 8
    xor     rax, rax
    cld
    rep     stosq

    mov     rdi, history_entries
    mov     rax, [history_count]
    imul    rax, 256
    add     rdi, rax
    mov     rsi, rdi
    mov     rdi, [rsp + 8]   ; original rdi (command string) - simplified
    call    str_cpy

    inc     qword [history_count]
    mov     qword [history_index], 0

.history_full:
    EPILOGUE_RESTORE rbx, rcx
    ret

; -----------------------------------------------------------------------------
; history_list_all — Print all history entries
; -----------------------------------------------------------------------------
global history_list_all
history_list_all:
    PROLOGUE_SAVE rbx, rcx, rdx

    mov     rbx, history_entries
    mov     rcx, [history_count]
    test    rcx, rcx
    jz      .history_empty

.history_loop:
    mov     rdi, rbx
    call    frontend_write_str
    mov     al, 0x0A
    call    frontend_write_char
    add     rbx, 256
    dec     rcx
    jnz     .history_loop

.history_empty:
    EPILOGUE_RESTORE rbx, rcx, rdx
    ret

; -----------------------------------------------------------------------------
; history_save — Save history to disk (stub)
; -----------------------------------------------------------------------------
global history_save
history_save:
    ret

%endif ; ISH_HISTORY_ASM