; UTM Task Manager - Graph Rendering
; Pure Assembly Implementation

%ifndef _UTM_GRAPHS_ASM_
%define _UTM_ENTERPRISE_GRAPHS_ASM_

%include "constants.inc"

extern utm_term_write

section .rodata
utm_graph_blocks:
    db ' ', 0xE2, 0x96, 0x8F, 0
    db ' ', 0xE2, 0x96, 0x8E, 0
    db ' ', 0xE2, 0x96, 0x8D, 0
    db ' ', 0xE2, 0x96, 0x8C, 0
    db ' ', 0xE2, 0x96, 0x8B, 0
    db ' ', 0xE2, 0x96, 0x8A, 0
    db ' ', 0xE2, 0x96, 0x89, 0
    db ' ', 0xE2, 0x96, 0x88, 0

utm_graph_ascii:
    db ' ', '.', ':', '-', '=', '+', '*', '#', '@'

section .text

global utm_graph_draw_bar
global utm_graph_draw_sparkline
global utm_graph_draw_histogram
global utm_graph_draw_scatter
global utm_graph_ansi_color
global utm_graph_clear_line
global utm_graph_move_cursor

utm_graph_draw_bar:
    ret

utm_graph_draw_sparkline:
    ret

utm_graph_draw_histogram:
    ret

utm_graph_draw_scatter:
    ret

utm_graph_ansi_color:
    ret

utm_graph_clear_line:
    mov rdi, utm_clear_line
    call utm_term_write
    ret

utm_clear_line:
    db 27, '[2K', 0

utm_graph_move_cursor:
    ret

%endif