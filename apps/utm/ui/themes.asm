; UTM Task Manager - Theme Engine
; Pure Assembly Implementation

%ifndef _UTM_THEMES_ASM_
%define _UTM_ENTERPRISE_THEMES_ASM_

%include "constants.inc"

section .rodata
utm_theme_table:
    dq utm_theme_green_def
    dq utm_theme_amber_def
    dq utm_theme_blue_def
    dq utm_theme_white_def
    dq utm_theme_mono_def
    dq utm_theme_light_def
    dq utm_theme_dark_def
    dq 0

utm_theme_green_def:
    .name       dq utm_str_green
    .bg         dd 0x000000FF
    .fg         dd 0x00FF00FF
    .highlight  dd 0x00FF80FF
    .dim        dd 0x004000FF
    .graph      dd 0x00FF00FF
    .warn       dd 0xFFFF00FF
    .crit       dd 0xFF0000FF
    .is_dark    db 1
    .pad        db 0, 0, 0

utm_theme_amber_def:
    .name       dq utm_str_amber
    .bg         dd 0x000000FF
    .fg         dd 0xFFBF00FF
    .highlight  dd 0xFFDF40FF
    .dim        dd 0x806000FF
    .graph      dd 0xFFBF00FF
    .warn       dd 0xFFFF00FF
    .crit       dd 0xFF4000FF
    .is_dark    db 1
    .pad        db 0, 0, 0

utm_theme_blue_def:
    .name       dq utm_str_blue
    .bg         dd 0x000000FF
    .fg         dd 0x00BFFFFF
    .highlight  dd 0x40DFFFFF
    .dim        dd 0x006080FF
    .graph      dd 0x00BFFFFF
    .warn       dd 0xFFFF40FF
    .crit       dd 0xFF0080FF
    .is_dark    db 1
    .pad        db 0, 0, 0

utm_theme_white_def:
    .name       dq utm_str_white
    .bg         dd 0x000000FF
    .fg         dd 0xFFFFFFFF
    .highlight  dd 0xFFFFFFFF
    .dim        dd 0x808080FF
    .graph      dd 0xC8C8C8FF
    .warn       dd 0xFFFF00FF
    .crit       dd 0xFF0000FF
    .is_dark    db 1
    .pad        db 0, 0, 0

utm_theme_mono_def:
    .name       dq utm_str_mono
    .bg         dd 0x000000FF
    .fg         dd 0xC0C0C0FF
    .highlight  dd 0xFFFFFFFF
    .dim        dd 0x404040FF
    .graph      dd 0xA0A0A0FF
    .warn       dd 0xDCDCDCFF
    .crit       dd 0xFFFFFFFF
    .is_dark    db 1
    .pad        db 0, 0, 0

utm_theme_light_def:
    .name       dq utm_str_light
    .bg         dd 0xFFFFFFFF
    .fg         dd 0x000000FF
    .highlight  dd 0x0064C8FF
    .dim        dd 0x808080FF
    .graph      dd 0x0096FFFF
    .warn       dd 0xC89600FF
    .crit       dd 0xC80000FF
    .is_dark    db 0
    .pad        db 0, 0, 0

utm_theme_dark_def:
    .name       dq utm_str_dark
    .bg         dd 0x202020FF
    .fg         dd 0xDCDCDCFF
    .highlight  dd 0x64C8FFFF
    .dim        dd 0x606060FF
    .graph      dd 0x50B4FFFF
    .warn       dd 0xFFC800FF
    .crit       dd 0xFF5050FF
    .is_dark    db 1
    .pad        db 0, 0, 0

utm_str_green:  db "Green Phosphor", 0
utm_str_amber:  db "Amber Phosphor", 0
utm_str_blue:   db "Blue Phosphor", 0
utm_str_white:  db "White Phosphor", 0
utm_str_mono:   db "Monochrome", 0
utm_str_light:  db "Light", 0
utm_str_dark:   db "Dark", 0

section .bss
utm_current_theme_idx resd 1
utm_saturation        resd 1
utm_theme_override    resd 1

utm_theme_workspace:
    .fg         dd 0
    .highlight  dd 0
    .dim        dd 0
    .graph      dd 0
    .warn       dd 0
    .crit       dd 0
    .bg         dd 0
    .is_dark    db 0

section .text

global utm_theme_init
global utm_theme_detect_capabilities
global utm_theme_load_config
global utm_theme_save_config
global utm_theme_apply
global utm_theme_saturate_color
global utm_theme_get_color
global utm_theme_get_ansi_fg
global utm_theme_get_ansi_bg
global utm_theme_next
global utm_theme_prev
global utm_theme_set_saturation
global utm_theme_inc_saturation
global utm_theme_dec_saturation
global utm_theme_is_dark

utm_theme_init:
    call utm_theme_detect_capabilities
    mov dword [utm_saturation], 7000
    call utm_theme_load_config
    call utm_theme_apply
    ret

utm_theme_detect_capabilities:
    ret

utm_theme_load_config:
    ret

utm_theme_save_config:
    ret

utm_theme_apply:
    mov eax, [utm_current_theme_idx]
    mov rcx, 56
    mul rcx
    mov rsi, utm_theme_table
    add rsi, rax
    mov rsi, [rsi]
    
    mov rdi, utm_theme_workspace
    mov rcx, 6
    add rsi, 8
    mov r8, [utm_saturation]
    
.sat_loop:
    mov eax, [rsi]
    call utm_theme_saturate_color
    mov [rdi], eax
    add rsi, 4
    add rdi, 4
    loop .sat_loop
    
    mov eax, [rsi - 28]
    mov [utm_theme_workspace + 24], eax
    mov al, [rsi + 20]
    mov [utm_theme_workspace + 28], al
    ret

utm_theme_saturate_color:
    mov r9, rax
    shr r9, 24
    mov r10b, al
    mov r11d, eax
    shr r11, 8
    and r11b, 0xFF
    shr rax, 16
    mov r12b, al
    
    movzx eax, r10b
    imul eax, 299
    movzx edx, r11b
    imul edx, 587
    add eax, edx
    movzx edx, r12b
    imul edx, 114
    add eax, edx
    shr eax, 10
    mov r13d, eax
    
    mov eax, r10d
    sub eax, r13d
    imul eax, r8d
    mov ecx, 10000
    idiv ecx
    add eax, r13d
    mov r10d, eax
    
    mov eax, r11d
    sub eax, r13d
    imul eax, r8d
    idiv ecx
    add eax, r13d
    mov r11d, eax
    
    mov eax, r12d
    sub eax, r13d
    imul eax, r8d
    idiv ecx
    add eax, r13d
    mov r12d, eax
    
    mov eax, r10d
    shl eax, 8
    mov al, r11b
    shl eax, 8
    mov al, r12b
    shl r9, 24
    or rax, r9
    ret

utm_theme_get_color:
    mov rax, [utm_theme_workspace + rdi*4]
    ret

utm_theme_next:
    inc dword [utm_current_theme_idx]
    cmp dword [utm_current_theme_idx], 7
    jl .ok
    mov dword [utm_current_theme_idx], 0
.ok:
    call utm_theme_apply
    call utm_theme_save_config
    ret

utm_theme_prev:
    cmp dword [utm_current_theme_idx], 0
    jg .ok
    mov dword [utm_current_theme_idx], 6
    jmp .done
.ok:
    dec dword [utm_current_theme_idx]
.done:
    call utm_theme_apply
    call utm_theme_save_config
    ret

utm_theme_set_saturation:
    cmp rdi, 10000
    jle .ok
    mov rdi, 10000
.ok:
    mov [utm_saturation], edi
    call utm_theme_apply
    call utm_theme_save_config
    ret

utm_theme_inc_saturation:
    add dword [utm_saturation], 500
    cmp dword [utm_saturation], 10000
    jle .ok
    mov dword [utm_saturation], 10000
.ok:
    call utm_theme_apply
    ret

utm_theme_dec_saturation:
    cmp dword [utm_saturation], 500
    jl .ok
    sub dword [utm_saturation], 500
    jmp .done
.ok:
    mov dword [utm_saturation], 0
.done:
    call utm_theme_apply
    ret

utm_theme_is_dark:
    mov al, [utm_theme_workspace + 28]
    ret

%endif