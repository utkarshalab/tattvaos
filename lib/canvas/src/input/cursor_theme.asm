; ============================================================================
; Cursor Theme — Loading and Managing Cursor Themes
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/canvas_client.inc"

; struct offsets (hoisted above use)
%define CursorTheme_SIZE 40
%define MAX_CURSORS_PER_THEME  64

section .text

struc CursorTheme
    .name:          resq 1
    .cursors:       resq 1
    .count:         resd 1
    .size:          resd 1
    .fallback:      resq 1
endstruc


; ---------------------------------------------------------------------------
; cursor_theme_init
; ---------------------------------------------------------------------------
global cursor_theme_init
cursor_theme_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rdi, r12
    mov rsi, CursorTheme_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax

    mov qword [rbx + CursorTheme.name], 0
    mov qword [rbx + CursorTheme.cursors], 0
    mov dword [rbx + CursorTheme.count], 0
    mov dword [rbx + CursorTheme.size], 32
    mov qword [rbx + CursorTheme.fallback], 0

    EPILOGUE_RESTORE rbx, r12
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; cursor_theme_load
;   Load cursor theme from directory
;   IN:  rdi = server*, rsi = theme_name
;   OUT: rax = theme*, 0 on error
; ---------------------------------------------------------------------------
global cursor_theme_load
cursor_theme_load:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r13, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Allocate theme
    mov rdi, [rbx + Server.arena]
    mov rsi, CursorTheme_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax
    mov qword [rbx + CursorTheme.name], r12
    mov dword [rbx + CursorTheme.size], 32
    mov dword [rbx + CursorTheme.count], 0

    ; Allocate cursor array
    mov rdi, [r13 + Server.arena]
    mov rsi, MAX_CURSORS_PER_THEME
    shl rsi, 3
    call arena_alloc
    test rax, rax
    jz .oom
    mov qword [rbx + CursorTheme.cursors], rax

    mov rcx, [r13 + Server.cursors]
    mov [rax], rcx
    mov [rbx + CursorTheme.fallback], rcx
    test rcx, rcx
    setnz al
    movzx eax, al
    mov [rbx + CursorTheme.count], eax

    mov rax, rbx
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; cursor_theme_load_default
; ---------------------------------------------------------------------------
cursor_theme_load_default:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    ASSERT_PTR rbx

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; cursor_theme_get_cursor
; ---------------------------------------------------------------------------
global cursor_theme_get_cursor
cursor_theme_get_cursor:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    cmp dword [rbx + CursorTheme.count], 0
    je .theme_fallback
    mov rax, [rbx + CursorTheme.cursors]
    mov rax, [rax]
    test rax, rax
    jnz .theme_out
.theme_fallback:
    mov rax, [rbx + CursorTheme.fallback]
.theme_out:
    EPILOGUE_RESTORE rbx, r12
    ret

section .data
global cursor_theme_version
cursor_theme_version: dq 0x010000
