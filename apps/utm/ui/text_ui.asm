; UTM Task Manager - Text Mode UI
; Pure Assembly Implementation

%ifndef _UTM_TEXT_UI_ASM_
%define _UTM_ENTERPRISE_TEXT_UI_ASM_

%include "constants.inc"
%include "structures.inc"

section .rodata
utm_header_text:
    db "UTM Enterprise Task Manager", 10, 0

utm_footer_text:
    db "[1-8]Tabs [F]ilter [S]ort [K]ill [N]ice [Q]uit", 0

utm_cursor_fmt:
    db 27, '[%d;%dH', 0

utm_alt_screen_on:    db 27, '[?1049h', 0
utm_cursor_hide:      db 27, '[?25l', 0
utm_mouse_enable:     db 27, '[?1000;1002;1006h', 0

utm_alt_screen_off:   db 27, '[?1049l', 0
utm_cursor_show:      db 27, '[?25h', 0
utm_mouse_disable:    db 27, '[?1000;1002;1006l', 0

section .data
utm_ui_running      db 1
utm_current_page    db 0
utm_sort_column     db 1
utm_sort_descending db 1
utm_filter_len      db 0
utm_selected_pid    dq 0
utm_scroll_offset   dq 0

utm_screen_rows     dw 24
utm_screen_cols     dw 80

section .bss
align 4096
utm_screen_buffer:
    resb 160 * 60 * 4

utm_process_list_cache:
    resb MAX_PROCESSES * PROC_SAMPLE_SIZE / 10

section .text

global utm_ui_main
global utm_ui_update_data
global utm_ui_render
global utm_ui_render_cpu
global utm_ui_render_memory
global utm_ui_render_disk
global utm_ui_render_network
global utm_ui_render_energy
global utm_ui_render_thermal
global utm_term_write
global utm_term_poll_input
global utm_term_init
global utm_term_cleanup
global utm_term_get_size
global utm_term_swap_buffers
global utm_ui_frame_delay

extern utm_term_write

utm_ui_main:
    call utm_term_init

.main_loop:
    cmp byte [utm_ui_running], 0
    je .exit
    
    call utm_term_poll_input
    call utm_ui_update_data
    call utm_ui_render
    call utm_term_swap_buffers
    call utm_ui_frame_delay
    
    jmp .main_loop

.exit:
    call utm_term_cleanup
    ret

utm_term_init:
    mov rdi, utm_alt_screen_on
    call utm_term_write
    mov rdi, utm_cursor_hide
    call utm_term_write
    mov rdi, utm_mouse_enable
    call utm_term_write
    call utm_term_get_size
    ret

utm_term_cleanup:
    mov rdi, utm_mouse_disable
    call utm_term_write
    mov rdi, utm_cursor_show
    call utm_term_write
    mov rdi, utm_alt_screen_off
    call utm_term_write
    ret

utm_term_get_size:
    mov word [utm_screen_rows], 24
    mov word [utm_screen_cols], 80
    ret

utm_term_poll_input:
    ret

utm_term_write:
    mov rsi, rdi
    call utm_strlen
    mov rdx, rax
    mov rax, 1
    mov rdi, 1
    syscall
    ret

utm_strlen:
    xor rax, rax
.strlen_loop:
    cmp byte [rsi + rax], 0
    je .strlen_done
    inc rax
    jmp .strlen_loop
.strlen_done:
    ret

utm_term_swap_buffers:
    ret

utm_ui_frame_delay:
    ret

utm_ui_update_data:
    ret

utm_ui_render:
    cmp byte [utm_ui_running], 0
    je .exit
    cmp byte [utm_current_page], 0
    je .render_summary
    cmp byte [utm_current_page], 1
    je .render_processes
    cmp byte [utm_current_page], 2
    je utm_ui_render_cpu
    cmp byte [utm_current_page], 3
    je utm_ui_render_memory
    cmp byte [utm_current_page], 4
    je utm_ui_render_disk
    cmp byte [utm_current_page], 5
    je utm_ui_render_network
    cmp byte [utm_current_page], 6
    je utm_ui_render_energy
    cmp byte [utm_current_page], 7
    je utm_ui_render_thermal
    ret

.exit:
    ret

.render_summary:
    call utm_ui_render_summary
    ret

.render_processes:
    ret

utm_ui_render_cpu:
    ret

utm_ui_render_memory:
    ret

utm_ui_render_disk:
    ret

utm_ui_render_network:
    ret

utm_ui_render_energy:
    ret

utm_ui_render_thermal:
    ret

utm_ui_render_summary:
    call utm_ui_draw_header
    call utm_ui_draw_footer
    ret

utm_ui_draw_header:
    xor rdi, rdi
    xor rsi, rsi
    call utm_ui_set_cursor

    mov rdi, utm_header_text
    call utm_term_write
    ret

utm_ui_draw_footer:
    mov rdi, utm_footer_text
    call utm_ui_set_cursor_bottom
    call utm_term_write
    ret

utm_ui_draw_meter:
    ret

utm_ui_draw_io_graph:
    ret

utm_ui_draw_power_meter:
    ret

utm_ui_draw_top_processes:
    ret

utm_ui_draw_proc_headers:
    ret

utm_ui_draw_proc_rows:
    ret

utm_ui_set_cursor:
    push rdi
    push rsi
    mov rdi, utm_cursor_fmt
    call utm_term_write
    pop rsi
    pop rdi
    ret

utm_ui_set_cursor_bottom:
    mov rdi, [utm_screen_rows]
    dec rdi
    xor rsi, rsi
    call utm_ui_set_cursor
    ret

utm_ui_printf:
    ret

%endif