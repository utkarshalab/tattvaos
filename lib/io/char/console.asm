; =============================================================================
; lib/io/char/console.asm
; Early console milestone logging routines.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_CHAR_CONSOLE_ASM
%define IO_CHAR_CONSOLE_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/io/io.inc"

section .rodata
milestone_prefix:   db "[Milestone] ", 0
milestone_newline:  db 13, 10, 0

section .text

extern serial_putc

; =============================================================================
; console_milestone — Emit a prefixed milestone string to the COM1 serial port.
; In : RDI = -> null-terminated ASCIIZ string (e.g. "IO:INIT")
; RSO: RDI owned-in (saved); RAX scratch
; =============================================================================
IO_FUNC console_milestone
    guard_null rdi
    push    rbx
    push    r12
    push    rdi                     ; Save RDI to satisfy RSO "RDI saved" contract

    mov     rbx, rdi                ; RBX = input string pointer

    ; 1. Output prefix "[Milestone] "
    lea     rdi, [rel milestone_prefix]
    call    .print_str

    ; 2. Iterate and output input string
    mov     rdi, rbx
    call    .print_str

    ; 3. Output newline (\r\n)
    lea     rdi, [rel milestone_newline]
    call    .print_str

    pop     rdi                     ; Restore RDI
    pop     r12
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; Helper: .print_str
; Write a null-terminated string to COM1.
; In: RDI = pointer to string
; -----------------------------------------------------------------------------
.print_str:
    push    rbp
    mov     rbp, rsp
    push    r12
    mov     r12, rdi                ; R12 = string pointer

.loop:
    movzx   rsi, byte [r12]
    test    sil, sil
    jz      .done                   ; Stop on null terminator

    mov     rdi, PORT_UART_COM1     ; COM1 UART base port
    call    serial_putc

    inc     r12
    jmp     .loop

.done:
    pop     r12
    pop     rbp
    ret
IO_ENDFUNC console_milestone

%endif ; IO_CHAR_CONSOLE_ASM
