; =============================================================================
; Utkarsha OS — lib/ugfx/tests/host/host_path.asm
; =============================================================================
; Host test tool: host_path <script> <out.raw>
;   script: u32 width, height, rule, colour, background, has_matrix;
;           f64 matrix[6], tolerance; u64 command count; then commands,
;           each a u64 opcode followed by its f64 arguments:
;     0 move x y          1 line x y          2 quad x1 y1 x2 y2
;     3 cubic x1 y1 x2 y2 x3 y3               4 close
;     5 rect x y w h      6 rounded_rect x y w h r
;     7 rounded_rect_radii x y w h r_tl r_tr r_br r_bl
;     8 ellipse cx cy rx ry                   9 circle cx cy r
;    10 arc cx cy rx ry start sweep          11 pie (same)
;    12 ring_sector cx cy r_outer r_inner start sweep
;    13 polygon n x0 y0 ... (n as f64)       14 star cx cy ro ri tips rotation
;    15 transform a b c d e f
;    16 stroke width miter_limit join cap: the path becomes its stroke outline
;    17 dash offset n i0 ... (n as f64): the path becomes its dashes
;    18 flatten: the path becomes its flattened copy
;    19 length expected max_error: fails (exit 5) unless the path's length
;       is within max_error of expected
;    20 paint kind spread g0 .. g5 n (offset colour) x n: fill with a
;       gradient instead of the colour (kind 1 linear x0 y0 x1 y1, 2 radial
;       cx cy r, 3 conic cx cy start, 4 radial2 x0 y0 r0 x1 y1 r1; unused
;       g are ignored; colour as f64, straight BGRA)
;    21 paint_transform a b c d e f
;    22 image w h extend_x extend_y filter colour x (w * h): fill with an
;       image pattern (colours premultiplied BGRA as f64, row by row)
;   The path is rasterized with the matrix (if any) and tolerance, filled
;   with the colour over the background, and written as BGRA.
; Exit status: 0 ok, 1 usage, 2 read error, 3 raster error, 4 write error,
;   5 a command returned an error, 6 unknown opcode.
; Development-machine tool only.
; =============================================================================

%define UGFX_PANIC_IMPL 1
%include "ugfx.inc"

extern pixbuf_create
extern ugfx_raster_init
extern ugfx_raster_fill
extern ugfx_path_init
extern ugfx_path_move_to
extern ugfx_path_line_to
extern ugfx_path_quad_to
extern ugfx_path_cubic_to
extern ugfx_path_close
extern ugfx_path_transform
extern ugfx_path_rasterize
extern ugfx_path_add_rect
extern ugfx_path_add_rounded_rect
extern ugfx_path_add_rounded_rect_radii
extern ugfx_path_add_ellipse
extern ugfx_path_add_circle
extern ugfx_path_add_arc
extern ugfx_path_add_pie
extern ugfx_path_add_ring_sector
extern ugfx_path_add_polygon
extern ugfx_path_add_star
extern ugfx_path_stroke
extern ugfx_path_reset
extern ugfx_path_dash
extern ugfx_path_flatten
extern ugfx_path_length
extern ugfx_raster_fill_paint
extern ugfx_paint_linear
extern ugfx_paint_radial
extern ugfx_paint_conic
extern ugfx_paint_radial2
extern ugfx_paint_image
extern ugfx_paint_set_transform

%define SYS_WRITE   1
%define SYS_OPEN    2
%define SYS_FSTAT   5
%define SYS_MMAP    9
%define SYS_EXIT    231
%define ARENA_BYTES (256 * 1024 * 1024)
%define MAX_STOPS   64

section .rodata
align 8
; opcode -> function, number of f64 arguments (-1 = special handling)
op_table:
    dq ugfx_path_move_to, 2
    dq ugfx_path_line_to, 2
    dq ugfx_path_quad_to, 4
    dq ugfx_path_cubic_to, 6
    dq ugfx_path_close, 0
    dq ugfx_path_add_rect, 4
    dq ugfx_path_add_rounded_rect, 5
    dq ugfx_path_add_rounded_rect_radii, -1
    dq ugfx_path_add_ellipse, 4
    dq ugfx_path_add_circle, 3
    dq ugfx_path_add_arc, 6
    dq ugfx_path_add_pie, 6
    dq ugfx_path_add_ring_sector, 6
    dq ugfx_path_add_polygon, -1
    dq ugfx_path_add_star, -1
    dq ugfx_path_transform, -1
    dq ugfx_path_stroke, -1
    dq ugfx_path_dash, -1
    dq ugfx_path_flatten, -1
    dq ugfx_path_length, -1
    dq ugfx_paint_linear, -1
    dq ugfx_paint_set_transform, -1
    dq ugfx_paint_image, -1
OP_COUNT equ ($ - op_table) / 16
align 16
abs_mask: dq 0x7FFFFFFFFFFFFFFF, 0x7FFFFFFFFFFFFFFF

section .text

global _start
_start:
    mov r12, [rsp + 16]
    mov r13, [rsp + 24]
    mov rax, [rsp]
    and rsp, -16
    cmp rax, 3
    jne .usage
    mov rdi, r12
    xor esi, esi
    mov eax, SYS_OPEN
    syscall
    test rax, rax
    js .read_fail
    mov r14, rax
    sub rsp, 144
    mov rdi, r14
    mov rsi, rsp
    mov eax, SYS_FSTAT
    syscall
    mov r15, [rsp + 48]
    add rsp, 144
    cmp r15, 88
    jb .read_fail
    xor edi, edi
    mov rsi, r15
    mov edx, 1
    mov r10d, 2
    mov r8, r14
    xor r9d, r9d
    mov eax, SYS_MMAP
    syscall
    test rax, rax
    js .read_fail
    mov rbx, rax                        ; script
    lea rax, [rbx + r15]
    mov [rel script_end], rax
    lea rax, [rel arena_memory]
    mov [rel arena_state], rax
    add rax, ARENA_BYTES
    mov [rel arena_state + 8], rax
    lea rdi, [rel arena_state]
    mov esi, [rbx]
    mov edx, [rbx + 4]
    xor ecx, ecx
    call pixbuf_create
    test rax, rax
    jle .raster_fail
    mov [rel pixbuf], rax
    mov rdi, [rax + PixBuf_data]
    mov rcx, [rax + PixBuf_size]
    shr rcx, 2
    mov eax, [rbx + 16]
    rep stosd
    lea rdi, [rel raster]
    lea rsi, [rel arena_state]
    mov edx, [rbx]
    mov ecx, [rbx + 4]
    call ugfx_raster_init
    test rax, rax
    jnz .raster_fail
    lea rdi, [rel path]
    lea rsi, [rel arena_state]
    call ugfx_path_init
    test rax, rax
    jnz .raster_fail
    lea rdi, [rel path2]
    lea rsi, [rel arena_state]
    call ugfx_path_init
    test rax, rax
    jnz .raster_fail
    lea rax, [rel path]
    mov [rel cur_path], rax
    lea rax, [rel path2]
    mov [rel other_path], rax
    ; commands
    mov r12, [rbx + 80]                 ; count
    lea r14, [rbx + 88]                 ; cursor
.command:
    test r12, r12
    jz .commands_done
    lea rax, [r14 + 8]
    cmp rax, [rel script_end]
    ja .read_fail
    mov rax, [r14]                      ; opcode
    add r14, 8
    cmp rax, OP_COUNT
    jae .bad_op
    shl rax, 4
    lea rdx, [rel op_table]
    mov r15, [rdx + rax]                ; function
    mov rcx, [rdx + rax + 8]            ; argument count
    cmp rcx, -1
    je .special
    lea rax, [r14 + rcx * 8]
    cmp rax, [rel script_end]
    ja .read_fail
    movsd xmm0, [r14]
    movsd xmm1, [r14 + 8]
    movsd xmm2, [r14 + 16]
    movsd xmm3, [r14 + 24]
    movsd xmm4, [r14 + 32]
    movsd xmm5, [r14 + 40]
    lea r14, [r14 + rcx * 8]
    mov rdi, [rel cur_path]
    call r15
    test rax, rax
    jnz .command_fail
    dec r12
    jmp .command
.special:
    mov rdi, [rel cur_path]
    lea rax, [rel ugfx_path_stroke]
    cmp r15, rax
    je .sp_stroke
    lea rax, [rel ugfx_path_dash]
    cmp r15, rax
    je .sp_dash
    lea rax, [rel ugfx_path_flatten]
    cmp r15, rax
    je .sp_flatten
    lea rax, [rel ugfx_path_length]
    cmp r15, rax
    je .sp_length
    lea rax, [rel ugfx_paint_linear]
    cmp r15, rax
    je .sp_paint
    lea rax, [rel ugfx_paint_set_transform]
    cmp r15, rax
    je .sp_paint_transform
    lea rax, [rel ugfx_paint_image]
    cmp r15, rax
    je .sp_image
    lea rax, [rel ugfx_path_add_rounded_rect_radii]
    cmp r15, rax
    je .sp_radii
    lea rax, [rel ugfx_path_add_polygon]
    cmp r15, rax
    je .sp_polygon
    lea rax, [rel ugfx_path_add_star]
    cmp r15, rax
    je .sp_star
    ; transform: rsi = matrix
    mov rsi, r14
    add r14, 48
    call r15
    dec r12
    jmp .command
.sp_stroke:
    movsd xmm0, [r14]
    movsd [rel stroke_style + UgfxStroke_width], xmm0
    movsd xmm0, [r14 + 8]
    movsd [rel stroke_style + UgfxStroke_miter_limit], xmm0
    cvttsd2si eax, qword [r14 + 16]
    mov [rel stroke_style + UgfxStroke_join], eax
    cvttsd2si eax, qword [r14 + 24]
    mov [rel stroke_style + UgfxStroke_cap], eax
    add r14, 32
    mov rdi, [rel other_path]
    call ugfx_path_reset
    mov rdi, [rel other_path]
    mov rsi, [rel cur_path]
    lea rdx, [rel stroke_style]
    movsd xmm0, [rbx + 72]
    call ugfx_path_stroke
    test rax, rax
    jnz .command_fail
    mov rax, [rel cur_path]
    mov rdx, [rel other_path]
    mov [rel cur_path], rdx
    mov [rel other_path], rax
    dec r12
    jmp .command
.sp_dash:
    movsd xmm0, [r14]
    movsd [rel dash_style + UgfxDash_offset], xmm0
    cvttsd2si rax, qword [r14 + 8]      ; n
    mov [rel dash_style + UgfxDash_count], eax
    lea rdx, [r14 + 16]
    mov [rel dash_style + UgfxDash_intervals], rdx
    lea r14, [r14 + rax * 8 + 16]
    mov rdi, [rel other_path]
    call ugfx_path_reset
    mov rdi, [rel other_path]
    mov rsi, [rel cur_path]
    lea rdx, [rel dash_style]
    movsd xmm0, [rbx + 72]
    call ugfx_path_dash
    jmp .sp_swap
.sp_flatten:
    mov rdi, [rel other_path]
    call ugfx_path_reset
    mov rdi, [rel other_path]
    mov rsi, [rel cur_path]
    movsd xmm0, [rbx + 72]
    call ugfx_path_flatten
.sp_swap:
    test rax, rax
    jnz .command_fail
    mov rax, [rel cur_path]
    mov rdx, [rel other_path]
    mov [rel cur_path], rdx
    mov [rel other_path], rax
    dec r12
    jmp .command
.sp_length:
    lea rsi, [rel arena_state]
    movsd xmm0, [rbx + 72]
    call ugfx_path_length
    test rax, rax
    jnz .command_fail
    subsd xmm0, [r14]
    andpd xmm0, [rel abs_mask]
    ucomisd xmm0, [r14 + 8]
    ja .command_fail
    jp .command_fail
    add r14, 16
    dec r12
    jmp .command
.sp_paint:
    ; stops: (offset, colour) pairs of f64 -> UgfxStop
    cvttsd2si rcx, qword [r14 + 64]     ; n
    cmp rcx, MAX_STOPS
    ja .command_fail
    lea rsi, [r14 + 72]
    lea rdi, [rel stops]
    xor edx, edx
.sp_stop:
    cmp rdx, rcx
    jae .sp_stops_done
    movsd xmm0, [rsi]
    movsd [rdi + UgfxStop_offset], xmm0
    cvttsd2si rax, qword [rsi + 8]
    mov [rdi + UgfxStop_color], eax
    add rsi, 16
    add rdi, UgfxStop_SIZE
    inc rdx
    jmp .sp_stop
.sp_stops_done:
    push rsi                            ; the next command
    push rcx
    cvttsd2si eax, qword [r14]          ; kind
    cvttsd2si r8d, qword [r14 + 8]      ; spread
    movsd xmm0, [r14 + 16]
    movsd xmm1, [r14 + 24]
    movsd xmm2, [r14 + 32]
    movsd xmm3, [r14 + 40]
    movsd xmm4, [r14 + 48]
    movsd xmm5, [r14 + 56]
    pop rcx
    lea rdi, [rel paint]
    lea rsi, [rel arena_state]
    lea rdx, [rel stops]
    cmp eax, 1
    je .sp_linear
    cmp eax, 2
    je .sp_radial
    cmp eax, 4
    je .sp_radial2
    cmp eax, 3
    jne .bad_op
    call ugfx_paint_conic
    jmp .sp_paint_done
.sp_radial2:
    call ugfx_paint_radial2
    jmp .sp_paint_done
.sp_linear:
    call ugfx_paint_linear
    jmp .sp_paint_done
.sp_radial:
    call ugfx_paint_radial
.sp_paint_done:
    pop r14
    test rax, rax
    jnz .command_fail
    mov byte [rel use_paint], 1
    dec r12
    jmp .command
.sp_image:
    lea rdi, [rel arena_state]
    cvttsd2si rsi, qword [r14]          ; w
    cvttsd2si rdx, qword [r14 + 8]      ; h
    xor ecx, ecx
    call pixbuf_create
    test rax, rax
    jle .command_fail
    mov [rel image], rax
    ; rows of f64 colours -> pixels
    lea rsi, [r14 + 40]
    xor r8d, r8d                        ; row
.sp_image_row:
    cmp r8, [rax + PixBuf_height]
    jae .sp_image_done
    mov rdi, r8
    imul rdi, [rax + PixBuf_stride]
    add rdi, [rax + PixBuf_data]
    xor ecx, ecx
.sp_image_px:
    cmp rcx, [rax + PixBuf_width]
    jae .sp_image_next
    cvttsd2si rdx, qword [rsi]
    mov [rdi + rcx * 4], edx
    add rsi, 8
    inc rcx
    jmp .sp_image_px
.sp_image_next:
    inc r8
    jmp .sp_image_row
.sp_image_done:
    push rsi                            ; the next command
    sub rsp, 8
    lea rdi, [rel paint]
    mov rsi, [rel image]
    cvttsd2si edx, qword [r14 + 16]
    cvttsd2si ecx, qword [r14 + 24]
    cvttsd2si r8d, qword [r14 + 32]
    call ugfx_paint_image
    add rsp, 8
    pop r14
    test rax, rax
    jnz .command_fail
    mov byte [rel use_paint], 1
    dec r12
    jmp .command
.sp_paint_transform:
    lea rdi, [rel paint]
    mov rsi, r14
    add r14, 48
    call ugfx_paint_set_transform
    test rax, rax
    jnz .command_fail
    dec r12
    jmp .command
.sp_radii:
    movsd xmm0, [r14]
    movsd xmm1, [r14 + 8]
    movsd xmm2, [r14 + 16]
    movsd xmm3, [r14 + 24]
    lea rsi, [r14 + 32]
    add r14, 64
    call r15
    test rax, rax
    jnz .command_fail
    dec r12
    jmp .command
.sp_polygon:
    cvttsd2si rdx, qword [r14]          ; n
    lea rsi, [r14 + 8]
    mov rax, rdx
    shl rax, 4
    lea r14, [r14 + rax + 8]
    call r15
    test rax, rax
    jnz .command_fail
    dec r12
    jmp .command
.sp_star:
    movsd xmm0, [r14]
    movsd xmm1, [r14 + 8]
    movsd xmm2, [r14 + 16]
    movsd xmm3, [r14 + 24]
    cvttsd2si rsi, qword [r14 + 32]     ; tips
    movsd xmm4, [r14 + 40]
    add r14, 48
    call r15
    test rax, rax
    jnz .command_fail
    dec r12
    jmp .command
.commands_done:
    mov rdi, [rel cur_path]
    lea rsi, [rel raster]
    xor edx, edx
    cmp dword [rbx + 20], 0
    je .no_matrix
    lea rdx, [rbx + 24]
.no_matrix:
    movsd xmm0, [rbx + 72]
    call ugfx_path_rasterize
    test rax, rax
    jnz .raster_fail
    lea rdi, [rel raster]
    mov rsi, [rel pixbuf]
    mov edx, [rbx + 12]
    mov ecx, [rbx + 8]
    cmp byte [rel use_paint], 0
    je .fill_solid
    lea rdx, [rel paint]
    call ugfx_raster_fill_paint
    jmp .filled
.fill_solid:
    call ugfx_raster_fill
.filled:
    test rax, rax
    jnz .raster_fail
    mov rdi, r13
    mov esi, 0x241
    mov edx, 0644o
    mov eax, SYS_OPEN
    syscall
    test rax, rax
    js .write_fail
    mov r14, rax
    mov rax, [rel pixbuf]
    mov r12, [rax + PixBuf_data]
    mov r13, [rax + PixBuf_size]
.write:
    test r13, r13
    jz .ok
    mov rdi, r14
    mov rsi, r12
    mov rdx, r13
    mov eax, SYS_WRITE
    syscall
    test rax, rax
    jle .write_fail
    add r12, rax
    sub r13, rax
    jmp .write
.ok:
    xor edi, edi
    jmp .exit
.usage:
    mov edi, 1
    jmp .exit
.read_fail:
    mov edi, 2
    jmp .exit
.raster_fail:
    mov edi, 3
    jmp .exit
.write_fail:
    mov edi, 4
    jmp .exit
.command_fail:
    mov edi, 5
    jmp .exit
.bad_op:
    mov edi, 6
.exit:
    mov eax, SYS_EXIT
    syscall
    hlt

global arena_alloc
arena_alloc:
    mov rax, [rdi]
    add rax, 15
    and rax, -16
    lea rdx, [rax + rsi]
    cmp rdx, [rdi + 8]
    ja .full
    mov [rdi], rdx
    ret
.full:
    xor eax, eax
    ret

global panic_null_ptr
panic_null_ptr:
    mov edi, 134
    mov eax, SYS_EXIT
    syscall
    hlt

section .bss
alignb 16
arena_state:    resq 2
script_end:     resq 1
pixbuf:         resq 1
raster:         resb UgfxRaster_SIZE
alignb 16
path:           resb UgfxPath_SIZE
alignb 16
path2:          resb UgfxPath_SIZE
cur_path:       resq 1
other_path:     resq 1
stroke_style:   resb UgfxStroke_SIZE
alignb 8
dash_style:     resb UgfxDash_SIZE
alignb 16
paint:          resb UgfxPaint_SIZE
stops:          resb UgfxStop_SIZE * MAX_STOPS
use_paint:      resb 1
alignb 8
image:          resq 1
alignb 4096
arena_memory:   resb ARENA_BYTES
