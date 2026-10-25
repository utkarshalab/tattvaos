; =============================================================================
; Utkarsha OS — lib/ugfx/tests/host/host_ctx.asm
; =============================================================================
; Host test tool: host_ctx <script> <out.raw> — drives a UgfxContext.
;   script: u32 width, height, background colour, mode (0: draw, 1: record
;           into a display list and replay it, 2: replay it twice); u64
;           command count;
;           then commands, each a u64 opcode followed by f64 arguments:
;   path (the current path, user space):
;     0 move x y   1 line x y   2 quad x1 y1 x2 y2   3 cubic x1 y1 x2 y2 x3 y3
;     4 close      5 rect x y w h   8 ellipse cx cy rx ry   9 circle cx cy r
;    30 new_path
;   context:
;    31 fill   32 stroke   33 clip   34 save   35 restore
;    36 set_transform a b c d e f   37 transform a b c d e f
;    38 translate tx ty   39 scale sx sy   40 rotate radians
;    41 fill_color c   42 stroke_color c          (premultiplied BGRA)
;    43 fill_gradient / 44 stroke_gradient kind spread g0..g5 n
;       (offset colour) x n m0..m5   (kind 1 linear, 2 radial, 3 conic,
;       4 radial2; m = paint -> user)
;    45 stroke_style width miter join cap
;    46 dash offset n i0 .. (n = 0: solid)
;    47 alpha a   48 rule r   49 tolerance t
;    50 fill_rect x y w h   51 stroke_rect x y w h
;    52 draw_image x y w h iw ih colour x (iw * ih)
;    53 clear c   54 begin_layer a   55 end_layer
;    56 uic bytes <pack, padded to 8> name_len <name, padded to 8> pixels
;       expected x y size weight n colour x n: open the pack, look the
;       name up (exit 5 unless the index is `expected`; -2 = any), and
;       draw it onto the context (directly, also when recording)
;    57 svg bytes <document, padded to 8> current_colour x y size: parse the
;       document and draw it onto the context (exit 5 if parsing fails);
;       its images decode as farbfeld (host_image), its text uses
;       host_font
;    58 clip_begin   59 clip_add (the current path)   60 clip_end
;    61 begin_mask   62 end_mask mode   63 clip_stroke (the current path)
;    64 filter x0 y0 x1 y1 n, then per primitive: type in1 in2 linear sx0
;       sy0 sx1 sy1 p0..p7 nvar var x nvar
; Exit status: 0 ok, 1 usage, 2 read error, 3 setup error, 4 write error,
;   5 a call returned an error, 6 unknown opcode.
; Development-machine tool only.
; =============================================================================

%define UGFX_PANIC_IMPL 1
%include "ugfx.inc"

extern pixbuf_create
extern ugfx_path_init
extern ugfx_path_reset
extern ugfx_path_move_to
extern ugfx_path_line_to
extern ugfx_path_quad_to
extern ugfx_path_cubic_to
extern ugfx_path_close
extern ugfx_path_add_rect
extern ugfx_path_add_ellipse
extern ugfx_path_add_circle
extern ugfx_paint_linear
extern ugfx_paint_radial
extern ugfx_paint_radial2
extern ugfx_paint_conic
extern ugfx_ctx_init
extern ugfx_ctx_fill
extern ugfx_ctx_stroke
extern ugfx_ctx_clip
extern ugfx_ctx_clip_begin
extern ugfx_ctx_clip_add
extern ugfx_ctx_clip_end
extern ugfx_list_clip_begin
extern ugfx_list_clip_add
extern ugfx_list_clip_end
extern ugfx_ctx_begin_mask
extern ugfx_ctx_end_mask
extern ugfx_list_begin_mask
extern ugfx_list_end_mask
extern ugfx_ctx_clip_stroke
extern ugfx_list_clip_stroke
extern ugfx_ctx_filter
extern ugfx_list_filter
extern ugfx_ctx_save
extern ugfx_ctx_restore
extern ugfx_ctx_set_transform
extern ugfx_ctx_transform
extern ugfx_ctx_translate
extern ugfx_ctx_scale
extern ugfx_ctx_rotate
extern ugfx_ctx_set_fill_color
extern ugfx_ctx_set_stroke_color
extern ugfx_ctx_set_fill_paint
extern ugfx_ctx_set_stroke_paint
extern ugfx_ctx_set_stroke_style
extern ugfx_ctx_set_dash
extern ugfx_ctx_set_alpha
extern ugfx_ctx_set_fill_rule
extern ugfx_ctx_set_tolerance
extern ugfx_ctx_fill_rect
extern ugfx_ctx_stroke_rect
extern ugfx_ctx_draw_image
extern ugfx_ctx_clear
extern ugfx_ctx_begin_layer
extern ugfx_ctx_end_layer
extern ugfx_list_begin_layer
extern ugfx_list_clear
extern ugfx_list_clip
extern ugfx_list_draw_image
extern ugfx_list_end_layer
extern ugfx_list_fill
extern ugfx_list_fill_rect
extern ugfx_list_restore
extern ugfx_list_rotate
extern ugfx_list_save
extern ugfx_list_scale
extern ugfx_list_set_alpha
extern ugfx_list_set_dash
extern ugfx_list_set_fill_color
extern ugfx_list_set_fill_paint
extern ugfx_list_set_fill_rule
extern ugfx_list_set_stroke_color
extern ugfx_list_set_stroke_paint
extern ugfx_list_set_stroke_style
extern ugfx_list_set_tolerance
extern ugfx_list_set_transform
extern ugfx_list_stroke
extern ugfx_list_stroke_rect
extern ugfx_list_transform
extern ugfx_list_translate
extern ugfx_list_init
extern ugfx_uic_open
extern ugfx_uic_find
extern ugfx_uic_draw
extern ugfx_svg_parse_opts
extern ugfx_path_add_rect
extern ugfx_svg_draw
extern ugfx_list_replay

%define SYS_WRITE   1
%define SYS_OPEN    2
%define SYS_FSTAT   5
%define SYS_MMAP    9
%define SYS_EXIT    231
%define ARENA_BYTES (256 * 1024 * 1024)
%define MAX_STOPS   64
%define MAX_DASH    64

section .rodata
align 8
; path opcodes 0..9: function, f64 argument count (0 = none here)
path_table:
    dq ugfx_path_move_to, 2
    dq ugfx_path_line_to, 2
    dq ugfx_path_quad_to, 4
    dq ugfx_path_cubic_to, 6
    dq ugfx_path_close, 0
    dq ugfx_path_add_rect, 4
    dq 0, 0
    dq 0, 0
    dq ugfx_path_add_ellipse, 4
    dq ugfx_path_add_circle, 3
PATH_OPS equ ($ - path_table) / 16

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
    cmp r15, 24
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
    mov rbx, rax
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
    jle .setup_fail
    mov [rel pixbuf], rax
    mov rdi, [rax + PixBuf_data]
    mov rcx, [rax + PixBuf_size]
    shr rcx, 2
    mov eax, [rbx + 8]
    rep stosd
    lea rdi, [rel ctx]
    lea rsi, [rel arena_state]
    mov rdx, [rel pixbuf]
    call ugfx_ctx_init
    test rax, rax
    jnz .setup_fail
    ; mode 0: draw; 1: record, replay once; 2: record, replay twice
    lea rax, [rel ctx]
    mov [rel obj], rax
    lea rsi, [rel ctx_fns]
    cmp dword [rbx + 12], 0
    je .fns
    lea rdi, [rel list]
    lea rsi, [rel arena_state]
    call ugfx_list_init
    test rax, rax
    jnz .setup_fail
    lea rax, [rel list]
    mov [rel obj], rax
    lea rsi, [rel list_fns]
.fns:
    lea rdi, [rel fns]
    mov ecx, FN_COUNT * 8
    rep movsb
    lea rdi, [rel path]
    lea rsi, [rel arena_state]
    call ugfx_path_init
    test rax, rax
    jnz .setup_fail
    mov r12, [rbx + 16]                 ; count
    lea r14, [rbx + 24]                 ; cursor
.command:
    test r12, r12
    jz .done
    mov rax, [r14]
    add r14, 8
    cmp rax, PATH_OPS
    jb .path_op
    cmp rax, 30
    jb .bad_op
    cmp rax, 56
    je .c_uic
    cmp rax, 57
    je .c_svg
    cmp rax, 58
    je .c_clip_begin
    cmp rax, 59
    je .c_clip_add
    cmp rax, 60
    je .c_clip_end
    cmp rax, 61
    je .c_begin_mask
    cmp rax, 62
    je .c_end_mask
    cmp rax, 63
    je .c_clip_stroke
    cmp rax, 64
    je .c_filter
    cmp rax, 55
    ja .bad_op
    sub rax, 30
    lea rdx, [rel ctx_jumps]
    jmp [rdx + rax * 8]
.path_op:
    shl rax, 4
    lea rdx, [rel path_table]
    mov r15, [rdx + rax]
    test r15, r15
    jz .bad_op
    mov rcx, [rdx + rax + 8]
    call load6
    lea r14, [r14 + rcx * 8]
    lea rdi, [rel path]
    call r15
    jmp .checked
.c_new_path:
    lea rdi, [rel path]
    call ugfx_path_reset
    jmp .next
.c_fill:
    mov rax, [rel fns + 5 * 8]   ; fill
    jmp .ctx_path
.c_stroke:
    mov rax, [rel fns + 21 * 8]   ; stroke
    jmp .ctx_path
.c_clip_begin:
    mov rdi, [rel obj]
    call [rel fns + 25 * 8]   ; clip_begin
    jmp .checked
.c_clip_end:
    mov rdi, [rel obj]
    call [rel fns + 27 * 8]   ; clip_end
    jmp .checked
.c_clip_add:
    mov rax, [rel fns + 26 * 8]   ; clip_add
    jmp .ctx_path
.c_begin_mask:
    mov rdi, [rel obj]
    call [rel fns + 28 * 8]   ; begin_mask
    jmp .checked
.c_end_mask:
    mov rax, [rel fns + 29 * 8]   ; end_mask
    jmp .ctx_int
.c_clip_stroke:
    mov rax, [rel fns + 30 * 8]   ; clip_stroke
    jmp .ctx_path
.c_filter:
    ; a UgfxFilter from the script, in the arena (rbx, r13 kept)
    push rbx
    push r13
    lea rdi, [rel arena_state]
    mov esi, UgfxFilter_SIZE
    call arena_alloc
    test rax, rax
    jz .bad_op
    mov r15, rax
    xor ecx, ecx
.cf_region:
    cvttsd2si rax, qword [r14 + rcx * 8]
    mov [r15 + UgfxFilter_region + rcx * 4], eax
    inc ecx
    cmp ecx, 4
    jb .cf_region
    cvttsd2si rax, qword [r14 + 32]
    mov [r15 + UgfxFilter_count], eax
    add r14, 40
    lea rdi, [rel arena_state]
    imul esi, eax, UgfxFe_SIZE
    add esi, 8
    call arena_alloc
    test rax, rax
    jz .bad_op
    mov [r15 + UgfxFilter_prims], rax
    mov rbx, rax
    xor r13d, r13d
.cf_prim:
    cmp r13d, [r15 + UgfxFilter_count]
    jae .cf_done
    xor ecx, ecx
.cf_int:
    cvttsd2si rax, qword [r14 + rcx * 8]
    mov [rbx + rcx * 4], eax            ; type, in1, in2, linear, sub x4
    inc ecx
    cmp ecx, 8
    jb .cf_int
    xor ecx, ecx
.cf_p:
    mov rax, [r14 + 64 + rcx * 8]
    mov [rbx + UgfxFe_p + rcx * 8], rax
    inc ecx
    cmp ecx, 8
    jb .cf_p
    cvttsd2si rax, qword [r14 + 128]
    mov [rbx + UgfxFe_nvar], eax
    lea rcx, [r14 + 136]
    mov [rbx + UgfxFe_var], rcx         ; (the script stays mapped)
    lea r14, [rcx + rax * 8]
    add rbx, UgfxFe_SIZE
    inc r13d
    jmp .cf_prim
.cf_done:
    pop r13
    pop rbx
    mov rdi, [rel obj]
    mov rsi, r15
    call [rel fns + 31 * 8]   ; filter
    jmp .checked
.c_clip:
    mov rax, [rel fns + 2 * 8]   ; clip
.ctx_path:
    mov rdi, [rel obj]
    lea rsi, [rel path]
    call rax
    jmp .checked
.c_save:
    mov rdi, [rel obj]
    call [rel fns + 9 * 8]   ; save
    jmp .checked
.c_restore:
    mov rdi, [rel obj]
    call [rel fns + 7 * 8]   ; restore
    jmp .checked
.c_set_transform:
    mov rax, [rel fns + 20 * 8]   ; set_transform
    jmp .ctx_matrix
.c_transform:
    mov rax, [rel fns + 23 * 8]   ; transform
.ctx_matrix:
    mov rdi, [rel obj]
    mov rsi, r14
    add r14, 48
    call rax
    jmp .checked
.c_translate:
    mov rax, [rel fns + 24 * 8]   ; translate
    jmp .ctx_two
.c_scale:
    mov rax, [rel fns + 10 * 8]   ; scale
.ctx_two:
    movsd xmm0, [r14]
    movsd xmm1, [r14 + 8]
    add r14, 16
    mov rdi, [rel obj]
    call rax
    jmp .checked
.c_rotate:
    movsd xmm0, [r14]
    add r14, 8
    mov rdi, [rel obj]
    call [rel fns + 8 * 8]   ; rotate
    jmp .checked
.c_fill_color:
    mov rax, [rel fns + 13 * 8]   ; set_fill_color
    jmp .ctx_int
.c_stroke_color:
    mov rax, [rel fns + 16 * 8]   ; set_stroke_color
    jmp .ctx_int
.c_alpha:
    mov rax, [rel fns + 11 * 8]   ; set_alpha
    jmp .ctx_int
.c_rule:
    mov rax, [rel fns + 15 * 8]   ; set_fill_rule
    jmp .ctx_int
.c_clear:
    mov rax, [rel fns + 1 * 8]   ; clear
    jmp .ctx_int
.c_begin_layer:
    mov rax, [rel fns + 0 * 8]   ; begin_layer
.ctx_int:
    cvttsd2si rsi, qword [r14]
    add r14, 8
    mov rdi, [rel obj]
    call rax
    jmp .checked
.c_end_layer:
    mov rdi, [rel obj]
    call [rel fns + 4 * 8]   ; end_layer
    jmp .checked
.c_tolerance:
    movsd xmm0, [r14]
    add r14, 8
    mov rdi, [rel obj]
    call [rel fns + 19 * 8]   ; set_tolerance
    jmp .checked
.c_fill_gradient:
    mov rax, [rel fns + 14 * 8]   ; set_fill_paint
    jmp .ctx_gradient
.c_stroke_gradient:
    mov rax, [rel fns + 17 * 8]   ; set_stroke_paint
.ctx_gradient:
    mov [rel setter], rax
    ; stops
    cvttsd2si rcx, qword [r14 + 64]
    cmp rcx, MAX_STOPS
    ja .call_fail
    lea rsi, [r14 + 72]
    lea rdi, [rel stops]
    xor edx, edx
.g_stop:
    cmp rdx, rcx
    jae .g_stops_done
    movsd xmm0, [rsi]
    movsd [rdi + UgfxStop_offset], xmm0
    cvttsd2si rax, qword [rsi + 8]
    mov [rdi + UgfxStop_color], eax
    add rsi, 16
    add rdi, UgfxStop_SIZE
    inc rdx
    jmp .g_stop
.g_stops_done:
    mov [rel matrix_ptr], rsi           ; m0..m5 follow the stops
    lea rax, [rsi + 48]
    mov [rel next_cmd], rax
    cvttsd2si eax, qword [r14]          ; kind
    cvttsd2si r8d, qword [r14 + 8]      ; spread
    movsd xmm0, [r14 + 16]
    movsd xmm1, [r14 + 24]
    movsd xmm2, [r14 + 32]
    movsd xmm3, [r14 + 40]
    movsd xmm4, [r14 + 48]
    movsd xmm5, [r14 + 56]
    lea rdi, [rel paint]
    lea rsi, [rel arena_state]
    lea rdx, [rel stops]
    cmp eax, 1
    je .g_linear
    cmp eax, 2
    je .g_radial
    cmp eax, 4
    je .g_radial2
    cmp eax, 3
    jne .bad_op
    call ugfx_paint_conic
    jmp .g_made
.g_linear:
    call ugfx_paint_linear
    jmp .g_made
.g_radial:
    call ugfx_paint_radial
    jmp .g_made
.g_radial2:
    call ugfx_paint_radial2
.g_made:
    test rax, rax
    jnz .call_fail
    mov r14, [rel next_cmd]
    mov rdi, [rel obj]
    lea rsi, [rel paint]
    mov rdx, [rel matrix_ptr]
    call [rel setter]
    jmp .checked
.c_stroke_style:
    movsd xmm0, [r14]
    movsd [rel style + UgfxStroke_width], xmm0
    movsd xmm0, [r14 + 8]
    movsd [rel style + UgfxStroke_miter_limit], xmm0
    cvttsd2si eax, qword [r14 + 16]
    mov [rel style + UgfxStroke_join], eax
    cvttsd2si eax, qword [r14 + 24]
    mov [rel style + UgfxStroke_cap], eax
    add r14, 32
    mov rdi, [rel obj]
    lea rsi, [rel style]
    call [rel fns + 18 * 8]   ; set_stroke_style
    jmp .checked
.c_dash:
    movsd xmm0, [r14]                   ; offset
    cvttsd2si rcx, qword [r14 + 8]      ; n
    cmp rcx, MAX_DASH
    ja .call_fail
    lea rsi, [r14 + 16]
    lea r14, [rsi + rcx * 8]            ; the next command
    test rcx, rcx
    jz .dash_none
    mov [rel dash + UgfxDash_count], ecx
    movsd [rel dash + UgfxDash_offset], xmm0
    lea rdi, [rel dash_values]
    shl rcx, 3
    rep movsb
    lea rax, [rel dash_values]
    mov [rel dash + UgfxDash_intervals], rax
    mov rdi, [rel obj]
    lea rsi, [rel dash]
    call [rel fns + 12 * 8]   ; set_dash
    jmp .checked
.dash_none:
    mov rdi, [rel obj]
    xor esi, esi
    call [rel fns + 12 * 8]   ; set_dash
    jmp .checked
.c_uic:
    cvttsd2si rcx, qword [r14]          ; pack bytes
    lea rdx, [r14 + 8]                  ; pack
    lea rax, [rcx + 7]
    and rax, -8
    lea r14, [rdx + rax]
    mov [rel uic_pack], rdx
    mov [rel uic_bytes], rcx
    cvttsd2si rcx, qword [r14]          ; name length
    lea rdx, [r14 + 8]
    mov [rel uic_name], rdx
    mov [rel uic_name_len], rcx
    lea rax, [rcx + 7]
    and rax, -8
    lea r14, [rdx + rax]
    lea rdi, [rel uic]
    lea rsi, [rel arena_state]
    mov rdx, [rel uic_pack]
    mov rcx, [rel uic_bytes]
    call ugfx_uic_open
    test rax, rax
    jnz .call_fail
    lea rdi, [rel uic]
    mov rsi, [rel uic_name]
    mov edx, [rel uic_name_len]
    cvttsd2si ecx, qword [r14]          ; pixels
    call ugfx_uic_find
    cvttsd2si rdx, qword [r14 + 8]      ; expected
    cmp rdx, -2
    je .uic_any
    cmp rax, rdx
    jne .call_fail
.uic_any:
    test rax, rax
    js .uic_skip
    mov esi, eax
    cvttsd2si r8, qword [r14 + 48]      ; colours
    lea rcx, [rel uic_colours]
    xor edx, edx
.uic_colour:
    cmp rdx, r8
    jae .uic_colours_done
    cvttsd2si rax, qword [r14 + 56 + rdx * 8]
    mov [rcx + rdx * 4], eax
    inc rdx
    jmp .uic_colour
.uic_colours_done:
    movsd xmm0, [r14 + 16]
    movsd xmm1, [r14 + 24]
    movsd xmm2, [r14 + 32]
    movsd xmm3, [r14 + 40]
    lea r14, [r14 + 56 + r8 * 8]
    lea rdi, [rel uic]
    lea rdx, [rel ctx]
    call ugfx_uic_draw
    jmp .checked
.uic_skip:
    cvttsd2si r8, qword [r14 + 48]
    lea r14, [r14 + 56 + r8 * 8]
    jmp .next
.c_svg:
    cvttsd2si rcx, qword [r14]          ; bytes
    lea rdx, [r14 + 8]
    lea rax, [rcx + 7]
    and rax, -8
    lea r14, [rdx + rax]
    lea rdi, [rel svg]
    lea rsi, [rel arena_state]
    lea r8, [rel svg_options]
    call ugfx_svg_parse_opts
    test rax, rax
    jnz .call_fail
    lea rdi, [rel svg]
    lea rsi, [rel ctx]
    cvttsd2si rdx, qword [r14]          ; current colour
    movsd xmm0, [r14 + 8]
    movsd xmm1, [r14 + 16]
    movsd xmm2, [r14 + 24]
    add r14, 32
    call ugfx_svg_draw
    jmp .checked
.c_fill_rect:
    mov rax, [rel fns + 6 * 8]   ; fill_rect
    jmp .ctx_rect
.c_stroke_rect:
    mov rax, [rel fns + 22 * 8]   ; stroke_rect
.ctx_rect:
    movsd xmm0, [r14]
    movsd xmm1, [r14 + 8]
    movsd xmm2, [r14 + 16]
    movsd xmm3, [r14 + 24]
    add r14, 32
    mov rdi, [rel obj]
    call rax
    jmp .checked
.c_draw_image:
    lea rdi, [rel arena_state]
    cvttsd2si rsi, qword [r14 + 32]     ; iw
    cvttsd2si rdx, qword [r14 + 40]     ; ih
    xor ecx, ecx
    call pixbuf_create
    test rax, rax
    jle .call_fail
    mov [rel image], rax
    lea rsi, [r14 + 48]
    xor r8d, r8d
.di_row:
    cmp r8, [rax + PixBuf_height]
    jae .di_done
    mov rdi, r8
    imul rdi, [rax + PixBuf_stride]
    add rdi, [rax + PixBuf_data]
    xor ecx, ecx
.di_px:
    cmp rcx, [rax + PixBuf_width]
    jae .di_next
    cvttsd2si rdx, qword [rsi]
    mov [rdi + rcx * 4], edx
    add rsi, 8
    inc rcx
    jmp .di_px
.di_next:
    inc r8
    jmp .di_row
.di_done:
    movsd xmm0, [r14]
    movsd xmm1, [r14 + 8]
    movsd xmm2, [r14 + 16]
    movsd xmm3, [r14 + 24]
    mov r14, rsi
    mov rdi, [rel obj]
    mov rsi, [rel image]
    call [rel fns + 3 * 8]   ; draw_image
.checked:
    test rax, rax
    jnz .call_fail
.next:
    dec r12
    jmp .command
.done:
    mov r15d, [rbx + 12]                ; replays
.replay:
    test r15d, r15d
    jz .write_out
    lea rdi, [rel list]
    lea rsi, [rel ctx]
    call ugfx_list_replay
    test rax, rax
    jnz .call_fail
    dec r15d
    jmp .replay
.write_out:
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
.setup_fail:
    mov edi, 3
    jmp .exit
.write_fail:
    mov edi, 4
    jmp .exit
.call_fail:
    mov edi, 5
    jmp .exit
.bad_op:
    mov edi, 6
.exit:
    mov eax, SYS_EXIT
    syscall
    hlt

; rcx = argument count, r14 = arguments -> xmm0..xmm5 loaded (count kept)
load6:
    movsd xmm0, [r14]
    movsd xmm1, [r14 + 8]
    movsd xmm2, [r14 + 16]
    movsd xmm3, [r14 + 24]
    movsd xmm4, [r14 + 32]
    movsd xmm5, [r14 + 40]
    ret

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

; host_image — the image callback for SVG documents: rdi = user, rsi =
;   bytes, rdx = length, ecx = kind (0: a data URI's bytes), r8 = arena ->
;   rax = a premultiplied PixBuf for a farbfeld image (16-bit RGBA, big
;   endian; the high bytes), else 0
host_image:
    push rbx
    push r12
    push r13
    push r14
    push r15
    xor eax, eax
    test ecx, ecx
    jnz .hi_out
    cmp rdx, 16
    jb .hi_out
    mov rcx, 'farbfeld'
    cmp [rsi], rcx
    jne .hi_out
    mov rbx, rsi
    mov r15, rdx
    mov r12d, [rsi + 8]
    bswap r12d                          ; width
    mov r13d, [rsi + 12]
    bswap r13d                          ; height
    mov rax, r12
    imul rax, r13
    shl rax, 3
    add rax, 16
    cmp rax, r15
    ja .hi_none
    mov rdi, r8
    mov rsi, r12
    mov rdx, r13
    xor ecx, ecx
    call pixbuf_create
    test rax, rax
    jle .hi_none
    mov r14, rax
    lea rsi, [rbx + 16]                 ; the pixels
    xor r15d, r15d                      ; row
.hi_row:
    cmp r15, r13
    jae .hi_done
    mov rdi, r15
    imul rdi, [r14 + PixBuf_stride]
    add rdi, [r14 + PixBuf_data]
    xor ecx, ecx
.hi_px:
    cmp rcx, r12
    jae .hi_next
    movzx r8d, byte [rsi + 6]           ; alpha
    mov r9d, r8d
    shl r9d, 24
    movzx eax, byte [rsi]               ; red
    call .hi_pm
    shl eax, 16
    or r9d, eax
    movzx eax, byte [rsi + 2]           ; green
    call .hi_pm
    shl eax, 8
    or r9d, eax
    movzx eax, byte [rsi + 4]           ; blue
    call .hi_pm
    or r9d, eax
    mov [rdi + rcx * 4], r9d
    add rsi, 8
    inc rcx
    jmp .hi_px
.hi_next:
    inc r15
    jmp .hi_row
.hi_done:
    mov rax, r14
    jmp .hi_out
.hi_none:
    xor eax, eax
.hi_out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
; eax = channel, r8d = alpha -> eax = round(channel x alpha / 255)
.hi_pm:
    imul eax, r8d
    add eax, 128
    mov edx, eax
    shr edx, 8
    add eax, edx
    shr eax, 8
    ret

; host_font — the test font: rdi = user, rsi = UgfxSvgFont*, edx = code
;   point, xmm0 = size s, rcx = UgfxPath* or 0 -> xmm0 = advance: a space
;   0.3 s; else ((cp mod 7) x 0.08 + 0.4) s, x 1.25 at weight >= 600, and
;   the outline a box (0.05 s, -0.7 s, advance - 0.1 s, 0.7 s), odd code
;   points with a notch (0.05 s, -0.9 s, 0.15 s, 0.15 s)
host_font:
    push rbx
    push r12
    push r13
    sub rsp, 32
    movsd [rsp], xmm0                   ; s
    mov rbx, rcx
    mov r12d, edx
    cmp edx, ' '
    jne .hf_glyph
    mulsd xmm0, [rel hf_space]
    jmp .hf_out
.hf_glyph:
    mov eax, edx
    xor edx, edx
    mov ecx, 7
    div ecx
    cvtsi2sd xmm1, edx
    mulsd xmm1, [rel hf_step]
    addsd xmm1, [rel hf_base]
    mulsd xmm1, xmm0
    cmp dword [rsi + UgfxSvgFont_weight], 600
    jb .hf_weight
    mulsd xmm1, [rel hf_bold]
.hf_weight:
    movsd [rsp + 8], xmm1               ; advance
    test rbx, rbx
    jz .hf_adv
    movsd xmm0, [rsp]
    mulsd xmm0, [rel hf_x0]
    movsd xmm1, [rsp]
    mulsd xmm1, [rel hf_y0]
    movsd xmm2, [rsp]
    mulsd xmm2, [rel hf_inset]
    movsd xmm3, [rsp + 8]
    subsd xmm3, xmm2
    movapd xmm2, xmm3
    movsd xmm3, [rsp]
    mulsd xmm3, [rel hf_h]
    mov rdi, rbx
    call ugfx_path_add_rect
    test r12d, 1
    jz .hf_adv
    movsd xmm0, [rsp]
    mulsd xmm0, [rel hf_x0]
    movsd xmm1, [rsp]
    mulsd xmm1, [rel hf_ny]
    movsd xmm2, [rsp]
    mulsd xmm2, [rel hf_nw]
    movapd xmm3, xmm2
    mov rdi, rbx
    call ugfx_path_add_rect
.hf_adv:
    movsd xmm0, [rsp + 8]
.hf_out:
    add rsp, 32
    pop r13
    pop r12
    pop rbx
    ret

global panic_null_ptr
panic_null_ptr:
    mov edi, 134
    mov eax, SYS_EXIT
    syscall
    hlt

section .data
align 8
svg_options:    dq host_image, 0, host_font, 0
hf_space:       dq 0.3
hf_step:        dq 0.08
hf_base:        dq 0.4
hf_bold:        dq 1.25
hf_x0:          dq 0.05
hf_y0:          dq -0.7
hf_inset:       dq 0.1
hf_h:           dq 0.7
hf_ny:          dq -0.9
hf_nw:          dq 0.15
ctx_fns:
    dq ugfx_ctx_begin_layer
    dq ugfx_ctx_clear
    dq ugfx_ctx_clip
    dq ugfx_ctx_draw_image
    dq ugfx_ctx_end_layer
    dq ugfx_ctx_fill
    dq ugfx_ctx_fill_rect
    dq ugfx_ctx_restore
    dq ugfx_ctx_rotate
    dq ugfx_ctx_save
    dq ugfx_ctx_scale
    dq ugfx_ctx_set_alpha
    dq ugfx_ctx_set_dash
    dq ugfx_ctx_set_fill_color
    dq ugfx_ctx_set_fill_paint
    dq ugfx_ctx_set_fill_rule
    dq ugfx_ctx_set_stroke_color
    dq ugfx_ctx_set_stroke_paint
    dq ugfx_ctx_set_stroke_style
    dq ugfx_ctx_set_tolerance
    dq ugfx_ctx_set_transform
    dq ugfx_ctx_stroke
    dq ugfx_ctx_stroke_rect
    dq ugfx_ctx_transform
    dq ugfx_ctx_translate
    dq ugfx_ctx_clip_begin
    dq ugfx_ctx_clip_add
    dq ugfx_ctx_clip_end
    dq ugfx_ctx_begin_mask
    dq ugfx_ctx_end_mask
    dq ugfx_ctx_clip_stroke
    dq ugfx_ctx_filter
list_fns:
    dq ugfx_list_begin_layer
    dq ugfx_list_clear
    dq ugfx_list_clip
    dq ugfx_list_draw_image
    dq ugfx_list_end_layer
    dq ugfx_list_fill
    dq ugfx_list_fill_rect
    dq ugfx_list_restore
    dq ugfx_list_rotate
    dq ugfx_list_save
    dq ugfx_list_scale
    dq ugfx_list_set_alpha
    dq ugfx_list_set_dash
    dq ugfx_list_set_fill_color
    dq ugfx_list_set_fill_paint
    dq ugfx_list_set_fill_rule
    dq ugfx_list_set_stroke_color
    dq ugfx_list_set_stroke_paint
    dq ugfx_list_set_stroke_style
    dq ugfx_list_set_tolerance
    dq ugfx_list_set_transform
    dq ugfx_list_stroke
    dq ugfx_list_stroke_rect
    dq ugfx_list_transform
    dq ugfx_list_translate
    dq ugfx_list_clip_begin
    dq ugfx_list_clip_add
    dq ugfx_list_clip_end
    dq ugfx_list_begin_mask
    dq ugfx_list_end_mask
    dq ugfx_list_clip_stroke
    dq ugfx_list_filter
FN_COUNT equ 32
ctx_jumps:
    dq _start.c_new_path, _start.c_fill, _start.c_stroke, _start.c_clip
    dq _start.c_save, _start.c_restore, _start.c_set_transform, _start.c_transform
    dq _start.c_translate, _start.c_scale, _start.c_rotate, _start.c_fill_color
    dq _start.c_stroke_color, _start.c_fill_gradient, _start.c_stroke_gradient, _start.c_stroke_style
    dq _start.c_dash, _start.c_alpha, _start.c_rule, _start.c_tolerance
    dq _start.c_fill_rect, _start.c_stroke_rect, _start.c_draw_image, _start.c_clear
    dq _start.c_begin_layer, _start.c_end_layer

section .bss
alignb 16
arena_state:    resq 2
script_end:     resq 1
pixbuf:         resq 1
image:          resq 1
setter:         resq 1
matrix_ptr:     resq 1
next_cmd:       resq 1
alignb 16
ctx:            resb UgfxContext_SIZE
alignb 16
list:           resb UgfxList_SIZE
obj:            resq 1
alignb 16
uic:            resb UgfxUic_SIZE
uic_pack:       resq 1
uic_bytes:      resq 1
uic_name:       resq 1
uic_name_len:   resq 1
uic_colours:    resd 16
alignb 16
svg:            resb UgfxSvg_SIZE
fns:            resq 32
alignb 16
path:           resb UgfxPath_SIZE
alignb 16
paint:          resb UgfxPaint_SIZE
stops:          resb UgfxStop_SIZE * MAX_STOPS
style:          resb UgfxStroke_SIZE
alignb 8
dash:           resb UgfxDash_SIZE
dash_values:    resq MAX_DASH
alignb 4096
arena_memory:   resb ARENA_BYTES
