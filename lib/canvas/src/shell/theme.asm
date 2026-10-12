; ============================================================================
; Theme Engine — Decoration and UI Theme Management
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

section .text

struc Theme {
    .name:              resq 1
    .colors:            resq 1
    .font:              resq 1
    .font_size:         resd 1
    .border_width:      resd 1
    .border_radius:     resd 1
    .titlebar_height:   resd 1
    .button_size:       resd 1
    .padding:           resd 1
    .spacing:           resd 1
    .cursor_theme:      resq 1
}
%define Theme_size    80

struc ThemeColors {
    .titlebar_active:       resd 1
    .titlebar_inactive:     resd 1
    .border_active:         resd 1
    .border_inactive:       resd 1
    .button_bg_normal:      resd 1
    .button_bg_hover:       resd 1
    .button_bg_pressed:     resd 1
    .button_bg_disabled:    resd 1
    .button_fg_normal:      resd 1
    .button_fg_disabled:    resd 1
    .text_normal:           resd 1
    .text_disabled:         resd 1
    .background:            resd 1
    .panel_bg:              resd 1
    .menu_bg:               resd 1
    .menu_border:           resd 1
    .tooltip_bg:            resd 1
    .tooltip_fg:            resd 1
}
%define ThemeColors_size    80

%define THEME_DEFAULT       0
%define THEME_DARK          1
%define THEME_LIGHT         2
%define THEME_HIGH_CONTRAST 3
%define THEME_CUSTOM        4

; ---------------------------------------------------------------------------
; theme_init
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
    call theme_create_default

    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; theme_create_default
; ---------------------------------------------------------------------------
theme_create_default:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Allocate theme
    mov rdi, r12
    mov rsi, Theme_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov r13, rax

    ; Fill default dark theme
    mov qword [r13 + Theme.name], default_theme_name
    mov qword [r13 + Theme.colors], 0
    mov qword [r13 + Theme.font], 0
    mov dword [r13 + Theme.font_size], 11
    mov dword [r13 + Theme.border_width], 2
    mov dword [r13 + Theme.border_radius], 4
    mov dword [r13 + Theme.titlebar_height], 32
    mov dword [r13 + Theme.button_size], 28
    mov dword [r13 + Theme.padding], 8
    mov dword [r13 + Theme.spacing], 4
    mov qword [r13 + Theme.cursor_theme], 0

    ; Allocate colors
    mov rdi, r12
    mov rsi, ThemeColors_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov qword [r13 + Theme.colors], rax

    ; Dark theme colors
    mov dword [rax + ThemeColors.titlebar_active], 0xFF2D2D2D
    mov dword [rax + ThemeColors.titlebar_inactive], 0xFF1E1E1E
    mov dword [rax + ThemeColors.border_active], 0xFF3D3D3D
    mov dword [rax + ThemeColors.border_inactive], 0xFF2D2D2D
    mov dword [rax + ThemeColors.button_bg_normal], 0xFF3D3D3D
    mov dword [rax + ThemeColors.button_bg_hover], 0xFF4D4D4D
    mov dword [rax + ThemeColors.button_bg_pressed], 0xFF2D2D2D
    mov dword [rax + ThemeColors.button_bg_disabled], 0xFF1D1D1D
    mov dword [rax + ThemeColors.button_fg_normal], 0xFFFFFFFF
    mov dword [rax + ThemeColors.button_fg_disabled], 0xFF808080
    mov dword [rax + ThemeColors.text_normal], 0xFFFFFFFF
    mov dword [rax + ThemeColors.text_disabled], 0xFF808080
    mov dword [rax + ThemeColors.background], 0xFF1A1A1A
    mov dword [rax + ThemeColors.panel_bg], 0xFF252525
    mov dword [rax + ThemeColors.menu_bg], 0xFF2D2D2D
    mov dword [rax + ThemeColors.menu_border], 0xFF3D3D3D
    mov dword [rax + ThemeColors.tooltip_bg], 0xFF333333
    mov dword [rax + ThemeColors.tooltip_fg], 0xFFFFFFFF

    mov qword [rbx + Server.theme], r13
    xor rax, rax
    ret

.oom:
    RETURN_ERROR ENOMEM

; ---------------------------------------------------------------------------
; theme_load
;   Load theme from file
; ---------------------------------------------------------------------------
global theme_load
theme_load:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13

    ; Read theme file
    push r12
    push r13
    mov rdi, r12
    mov rsi, r13
    call tv_fs_read
    pop r13
    pop r12
    test rax, rax
    js .fail

    ; Parse theme file (JSON-like format)
    ; TODO: Implement theme parser

    xor rax, rax
    ret

.fail:
    RETURN_ERROR EINVAL

; ---------------------------------------------------------------------------
; theme_get_color
; ---------------------------------------------------------------------------
global theme_get_color
theme_get_color:
    PROLOGUE
    ASSERT_PTR rdi
    mov rax, [rdi + Server.theme]
    test rax, rax
    jz .no_theme
    mov rax, [rax + Theme.colors]
    test rax, rax
    jz .no_theme
    mov eax, [rax + rsi]
    ret
.no_theme:
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; theme_set_color
; ---------------------------------------------------------------------------
global theme_set_color
theme_set_color:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov rax, [rbx + Server.theme]
    test rax, rax
    jz .no_theme
    mov rax, [rax + Theme.colors]
    test rax, rax
    jz .no_theme
    mov [rax + rsi], edx
    xor rax, rax
    ret

.no_theme:
    RETURN_ERROR EINVAL

; ---------------------------------------------------------------------------
; theme_set_font
; ---------------------------------------------------------------------------
global theme_set_font
theme_set_font:
    PROLOGUE
    mov rax, [rdi + Server.theme]
    test rax, rax
    jz .no_theme
    mov qword [rax + Theme.font], rsi
    mov dword [rax + Theme.font_size], edx
    xor rax, rax
    ret

.no_theme:
    RETURN_ERROR EINVAL

; ---------------------------------------------------------------------------
; theme_set_border
; ---------------------------------------------------------------------------
global theme_set_border
theme_set_border:
    PROLOGUE
    mov rax, [rdi + Server.theme]
    test rax, rax
    jz .no_theme
    mov dword [rax + Theme.border_width], esi
    mov dword [rax + Theme.border_radius], edx
    xor rax, rax
    ret

.no_theme:
    RETURN_ERROR EINVAL

; ---------------------------------------------------------------------------
; theme_get_font
; ---------------------------------------------------------------------------
global theme_get_font
theme_get_font:
    PROLOGUE
    mov rax, [rdi + Server.theme]
    test rax, rax
    jz .no_theme
    mov rax, [rax + Theme.font]
    mov rdx, [rax + Theme.font_size]
    ret
.no_theme:
    xor rax, rax
    xor rdx, rdx
    ret

section .rodata
default_theme_name: db "default-dark", 0

section .data
global theme_version
theme_version: dq 0x010000