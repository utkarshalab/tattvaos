; ============================================================================
; Theme Engine — Decoration and UI Theme Management
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/struct_offsets.inc"
%include "inc/externs.inc"

%define THEME_DEFAULT       0
%define THEME_DARK          1
%define THEME_LIGHT         2
%define THEME_HIGH_CONTRAST 3
%define THEME_CUSTOM        4

section .text

; ---------------------------------------------------------------------------
; theme_init
;   Initialize theme engine
;   IN:  rdi = server*, rsi = arena
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global theme_init
theme_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + Server.theme], 0
    mov qword [rbx + Server.arena], r12

    ; Create default theme
    mov rdi, r12
    mov rsi, Theme_SIZE
    call arena_alloc
    test rax, rax
    jz .oom
    mov r12, rax

    ; Initialize default theme
    mov qword [r12 + Theme.name], default_theme_name
    mov qword [r12 + Theme.colors], 0
    mov qword [r12 + Theme.font], 0
    mov dword [r12 + Theme.font_size], 12
    mov dword [r12 + Theme.border_width], 2
    mov dword [r12 + Theme.border_radius], 4
    mov dword [r12 + Theme.titlebar_height], 32
    mov dword [r12 + Theme.button_size], 24
    mov dword [r12 + Theme.padding], 8

    mov [rbx + Server.theme], r12
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.oom:
    mov rax, -(ENOMEM)
    ret

; ---------------------------------------------------------------------------
; theme_create_default
; ---------------------------------------------------------------------------
global theme_create_default
theme_create_default:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13

    mov rdi, [rbx + Server.arena]
    mov rsi, Theme_SIZE
    call arena_alloc
    test rax, rax
    jz .oom
    mov r12, rax

    mov qword [r12 + Theme.name], r13
    mov qword [r12 + Theme.colors], 0
    mov qword [r12 + Theme.font], 0
    mov dword [r12 + Theme.font_size], 12
    mov dword [r12 + Theme.border_width], 2
    mov dword [r12 + Theme.border_radius], 4
    mov dword [r12 + Theme.titlebar_height], 32
    mov dword [r12 + Theme.button_size], 24
    mov dword [r12 + Theme.padding], 8

    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.oom:
    mov rax, -(ENOMEM)
    ret

; ---------------------------------------------------------------------------
; theme_set_colors
; ---------------------------------------------------------------------------
global theme_set_colors
theme_set_colors:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13

    mov rax, [r12 + Theme.colors]
    test rax, rax
    jz .create_colors

    ; Update existing colors
    mov rdi, r12
    mov rsi, r13
    call theme_update_colors
    jmp .done

.create_colors:
    mov rdi, [rbx + Server.arena]
    mov rsi, ThemeColors_SIZE
    call arena_alloc
    test rax, rax
    jz .oom
    mov [r12 + Theme.colors], rax

    mov rdi, rax
    mov rsi, r13
    call theme_update_colors

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; theme_update_colors
; ---------------------------------------------------------------------------
global theme_update_colors
theme_update_colors:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Copy color values
    mov rax, [r12 + ThemeColors.background]
    mov [rbx + ThemeColors.background], rax
    mov rax, [r12 + ThemeColors.foreground]
    mov [rbx + ThemeColors.foreground], rax
    mov rax, [r12 + ThemeColors.accent]
    mov [rbx + ThemeColors.accent], rax
    mov rax, [r12 + ThemeColors.border]
    mov [rbx + ThemeColors.border], rax
    mov rax, [r12 + ThemeColors.titlebar_bg]
    mov [rbx + ThemeColors.titlebar_bg], rax
    mov rax, [r12 + ThemeColors.titlebar_fg]
    mov [rbx + ThemeColors.titlebar_fg], rax
    mov rax, [r12 + ThemeColors.button_bg]
    mov [rbx + ThemeColors.button_bg], rax
    mov rax, [r12 + ThemeColors.button_fg]
    mov [rbx + ThemeColors.button_fg], rax
    mov rax, [r12 + ThemeColors.button_hover_bg]
    mov [rbx + ThemeColors.button_hover_bg], rax
    mov rax, [r12 + ThemeColors.button_hover_fg]
    mov [rbx + ThemeColors.button_hover_fg], rax
    mov rax, [r12 + ThemeColors.button_pressed_bg]
    mov [rbx + ThemeColors.button_pressed_bg], rax
    mov rax, [r12 + ThemeColors.button_pressed_fg]
    mov [rbx + ThemeColors.button_pressed_fg], rax

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

section .data

default_theme_name: db "default", 0

global theme_version
theme_version: dq 0x010000