; =============================================================================
; File     : apps/ish/src/io/frontend.asm
; Project  : Tattva OS — Ishana Shell
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Frontend dispatcher — calls vtable methods on io_frontend_t.
; =============================================================================

%ifndef ISH_FRONTEND_ASM
%define ISH_FRONTEND_ASM

%include "inc/frontend.inc"

bits 64

section .text

; -----------------------------------------------------------------------------
; frontend_init — Call frontend.init()
; Input:  rdi = ptr to io_frontend_t
; Output: none
; -----------------------------------------------------------------------------
global frontend_init
frontend_init:
    PROLOGUE_SAVE rbx
    mov     rbx, rdi                      ; rbx = frontend ptr
    mov     rdi, [rbx + io_frontend_t.init]
    test    rdi, rdi
    jz      .no_init
    call    rdi
.no_init:
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; frontend_shutdown — Call frontend.shutdown()
; -----------------------------------------------------------------------------
global frontend_shutdown
frontend_shutdown:
    PROLOGUE_SAVE rbx
    mov     rbx, rdi
    mov     rdi, [rbx + io_frontend_t.shutdown]
    test    rdi, rdi
    jz      .no_shutdown
    call    rdi
.no_shutdown:
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; frontend_read_line — Call frontend.read_line(buf, max_len)
; Input:  rdi = frontend ptr, rsi = buf, rdx = max_len
; Output: rax = bytes read or -1
; -----------------------------------------------------------------------------
global frontend_read_line
frontend_read_line:
    PROLOGUE_SAVE rbx
    mov     rbx, rdi                      ; rbx = frontend ptr
    mov     rdi, [rbx + io_frontend_t.read_line]
    test    rdi, rdi
    jz      .no_read
    ; rsi = buf, rdx = max_len already set by caller
    call    rdi
    jmp .done
.no_read:
    mov     rax, -1
.done:
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; frontend_write — Call frontend.write(ptr, len)
; Input:  rdi = frontend ptr, rsi = ptr, rdx = len
; -----------------------------------------------------------------------------
global frontend_write
frontend_write:
    PROLOGUE_SAVE rbx
    mov     rbx, rdi
    mov     rdi, [rbx + io_frontend_t.write]
    test    rdi, rdi
    jz      .no_write
    call    rdi
.no_write:
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; frontend_write_str — Call frontend.write_str(str)
; Input:  rdi = frontend ptr, rsi = str
; -----------------------------------------------------------------------------
global frontend_write_str
frontend_write_str:
    PROLOGUE_SAVE rbx
    mov     rbx, rdi
    mov     rdi, [rbx + io_frontend_t.write_str]
    test    rdi, rdi
    jz      .no_write_str
    mov     rdi, rsi
    call    rdi
.no_write_str:
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; frontend_write_char — Call frontend.write_char(char)
; Input:  rdi = frontend ptr, rsi = char (al)
; -----------------------------------------------------------------------------
global frontend_write_char
frontend_write_char:
    PROLOGUE_SAVE rbx
    mov     rbx, rdi
    mov     rdi, [rbx + io_frontend_t.write_char]
    test    rdi, rdi
    jz      .no_write_char
    call    rdi
.no_write_char:
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; frontend_set_prompt — Call frontend.set_prompt(str)
; Input:  rdi = frontend ptr, rsi = str
; -----------------------------------------------------------------------------
global frontend_set_prompt
frontend_set_prompt:
    PROLOGUE_SAVE rbx
    mov     rbx, rdi
    mov     rdi, [rbx + io_frontend_t.set_prompt]
    test    rdi, rdi
    jz      .no_set_prompt
    mov     rdi, rsi
    call    rdi
.no_set_prompt:
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; frontend_clear_line — Call frontend.clear_line()
; -----------------------------------------------------------------------------
global frontend_clear_line
frontend_clear_line:
    PROLOGUE_SAVE rbx
    mov     rbx, rdi
    mov     rdi, [rbx + io_frontend_t.clear_line]
    test    rdi, rdi
    jz      .no_clear_line
    call    rdi
.no_clear_line:
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; frontend_get_char — Call frontend.get_char()
; Input:  rdi = frontend ptr
; Output: rax = char or -1
; -----------------------------------------------------------------------------
global frontend_get_char
frontend_get_char:
    PROLOGUE_SAVE rbx
    mov     rbx, rdi
    mov     rdi, [rbx + io_frontend_t.get_char]
    test    rdi, rdi
    jz      .no_get_char
    call    rdi
    jmp .done
.no_get_char:
    mov     rax, -1
.done:
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; frontend_is_tty — Call frontend.is_tty()
; Input:  rdi = frontend ptr
; Output: rax = 1 if TTY, 0 otherwise
; -----------------------------------------------------------------------------
global frontend_is_tty
frontend_is_tty:
    PROLOGUE_SAVE rbx
    mov     rbx, rdi
    mov     rdi, [rbx + io_frontend_t.is_tty]
    test    rdi, rdi
    jz      .not_tty
    call    rdi
    jmp .done
.not_tty:
    xor     rax, rax
.done:
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; frontend_get_size — Call frontend.get_size(&cols, &rows)
; Input:  rdi = frontend ptr, rsi = ptr to cols, rdx = ptr to rows
; -----------------------------------------------------------------------------
global frontend_get_size
frontend_get_size:
    PROLOGUE_SAVE rbx
    mov     rbx, rdi
    mov     rdi, [rbx + io_frontend_t.get_size]
    test    rdi, rdi
    jz      .no_get_size
    call    rdi
.no_get_size:
    EPILOGUE_RESTORE rbx
    ret

%endif ; ISH_FRONTEND_ASM