; Primary selection shares the clipboard storage engine.
%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/canvas_client.inc"

extern clipboard_set
extern clipboard_get

section .text
global selection_init
selection_init:
    cmp qword [rdi + Server.primary_selection], 0
    setne al
    movzx eax, al
    dec eax
    ret

global selection_set
selection_set:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, [rbx + Server.clipboard]
    mov rax, [rbx + Server.primary_selection]
    test rax, rax
    jz .missing
    mov [rbx + Server.clipboard], rax
    call clipboard_set
    mov [rbx + Server.clipboard], r12
    EPILOGUE_RESTORE rbx, r12
    ret
.missing:
    mov rax, -(ENODEV)
    EPILOGUE_RESTORE rbx, r12
    ret

global selection_get
selection_get:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, [rbx + Server.clipboard]
    mov rax, [rbx + Server.primary_selection]
    test rax, rax
    jz .empty
    mov [rbx + Server.clipboard], rax
    call clipboard_get
    mov [rbx + Server.clipboard], r12
    EPILOGUE_RESTORE rbx, r12
    ret
.empty:
    xor eax, eax
    xor edx, edx
    EPILOGUE_RESTORE rbx, r12
    ret

global selection_send_event
selection_send_event:
    mov rax, [rsi + Clipboard.serial]
    ret

section .data
global selection_version
selection_version: dq 0x010000
