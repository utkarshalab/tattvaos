; =============================================================================
; Utkarsha OS — lib/ugfx/core/raster.asm
; =============================================================================
; Anti-aliased scanline rasterizer with exact area coverage.
;
; Edges (24.8 fixed point, device pixels) are walked cell by cell; each pixel
; cell an edge crosses collects a signed "cover" (vertical extent inside the
; cell) and "area" (cover weighted by horizontal position). Sorting the cells
; by row and column and sweeping each row left to right turns the running
; cover plus the cell's own area into the exact fraction of the pixel inside
; the shape, for the nonzero or even-odd rule. Rows become coverage spans that
; go to the span compositor, the same path 3D triangles will use.
;
; This is the cell/area method of the classic AGG and FreeType "gray"
; rasterizers. All arithmetic is 64-bit, so coordinates cannot overflow.
; Cells left of the clip area collapse into column -1 (they still carry
; cover); cells right of it or outside its rows are dropped.
; =============================================================================

%include "ugfx.inc"

extern arena_alloc
extern ugfx_span_fill_solid
extern ugfx_span_mask_union

%define SHIFT   UGFX_SUBPIXEL_SHIFT
%define SCALE   UGFX_SUBPIXEL_SCALE
%define MASK    (UGFX_SUBPIXEL_SCALE - 1)
%define RASTER_INITIAL_CELLS 1024

; rax = p (signed), %1 = divisor > 0 -> rax = floor(p / d), rdx = p - rax * d
%macro FLOORDIV 1
    cqo
    idiv %1
    test rdx, rdx
    jns %%done
    dec rax
    add rdx, %1
%%done:
%endmacro

section .text

; -----------------------------------------------------------------------------
; ugfx_raster_init
;   IN:  rdi = UgfxRaster*, rsi = arena, edx = clip width, ecx = clip height
;   OUT: rax = 0, -EINVAL, -ENOMEM
; -----------------------------------------------------------------------------
global ugfx_raster_init
ugfx_raster_init:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    test rdi, rdi
    jz .init_bad
    test rsi, rsi
    jz .init_bad
    test edx, edx
    jle .init_bad
    test ecx, ecx
    jle .init_bad
    cmp edx, 32768
    ja .init_bad
    cmp ecx, 32768
    ja .init_bad
    mov [rbx + UgfxRaster_arena], rsi
    mov [rbx + UgfxRaster_width], edx
    mov [rbx + UgfxRaster_height], ecx
    mov rdi, rsi
    mov esi, RASTER_INITIAL_CELLS * UgfxCell_SIZE
    call arena_alloc
    test rax, rax
    jz .init_nomem
    mov [rbx + UgfxRaster_cells], rax
    mov dword [rbx + UgfxRaster_cap], RASTER_INITIAL_CELLS
    mov qword [rbx + UgfxRaster_clip], 0
    mov dword [rbx + UgfxRaster_alpha], 255
    mov rdi, rbx
    call ugfx_raster_reset
    xor eax, eax
    EPILOGUE_RESTORE rbx
.init_bad:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx
.init_nomem:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx

; -----------------------------------------------------------------------------
; ugfx_raster_reset — drop all edges; keeps the cell storage.
;   IN: rdi = UgfxRaster*
; -----------------------------------------------------------------------------
global ugfx_raster_reset
ugfx_raster_reset:
    xor eax, eax
    mov [rdi + UgfxRaster_count], eax
    mov [rdi + UgfxRaster_cover], eax
    mov [rdi + UgfxRaster_area], eax
    mov [rdi + UgfxRaster_open], eax
    mov [rdi + UgfxRaster_error], eax
    mov [rdi + UgfxRaster_move_x], eax
    mov [rdi + UgfxRaster_move_y], eax
    mov [rdi + UgfxRaster_last_x], eax
    mov [rdi + UgfxRaster_last_y], eax
    mov dword [rdi + UgfxRaster_cur_x], 0x7FFFFFFF
    mov dword [rdi + UgfxRaster_cur_y], 0x7FFFFFFF
    ret

; -----------------------------------------------------------------------------
; ugfx_raster_move_to — start a contour (closing any open one)
;   IN: rdi = UgfxRaster*, esi = x, edx = y (24.8)
; -----------------------------------------------------------------------------
global ugfx_raster_move_to
ugfx_raster_move_to:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    call rs_close
    mov [rbx + UgfxRaster_move_x], r12d
    mov [rbx + UgfxRaster_move_y], r13d
    mov [rbx + UgfxRaster_last_x], r12d
    mov [rbx + UgfxRaster_last_y], r13d
    mov dword [rbx + UgfxRaster_open], 1
    mov edi, r12d
    sar edi, SHIFT
    mov esi, r13d
    sar esi, SHIFT
    call rs_set_cell
    EPILOGUE_RESTORE rbx, r12, r13

; -----------------------------------------------------------------------------
; ugfx_raster_line_to — edge from the current point
;   IN: rdi = UgfxRaster*, esi = x, edx = y (24.8)
; -----------------------------------------------------------------------------
global ugfx_raster_line_to
ugfx_raster_line_to:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    cmp dword [rbx + UgfxRaster_open], 0
    jne .line_open
    ; no contour yet: treat as a move
    mov rdi, rbx
    call ugfx_raster_move_to
    EPILOGUE_RESTORE rbx, r12, r13
.line_open:
    mov edi, [rbx + UgfxRaster_last_x]
    mov esi, [rbx + UgfxRaster_last_y]
    mov edx, r12d
    mov ecx, r13d
    call rs_line
    mov [rbx + UgfxRaster_last_x], r12d
    mov [rbx + UgfxRaster_last_y], r13d
    EPILOGUE_RESTORE rbx, r12, r13

; -----------------------------------------------------------------------------
; ugfx_raster_close — close the open contour back to its start
;   IN: rdi = UgfxRaster*
; -----------------------------------------------------------------------------
global ugfx_raster_close
ugfx_raster_close:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    call rs_close
    EPILOGUE_RESTORE rbx

; rbx = raster. Closes the open contour, if any.
rs_close:
    cmp dword [rbx + UgfxRaster_open], 0
    je .close_done
    mov dword [rbx + UgfxRaster_open], 0
    mov edi, [rbx + UgfxRaster_last_x]
    mov esi, [rbx + UgfxRaster_last_y]
    mov edx, [rbx + UgfxRaster_move_x]
    mov ecx, [rbx + UgfxRaster_move_y]
    cmp edi, edx
    jne .close_line
    cmp esi, ecx
    je .close_done
.close_line:
    mov [rbx + UgfxRaster_last_x], edx
    mov [rbx + UgfxRaster_last_y], ecx
    call rs_line
.close_done:
    ret

; -----------------------------------------------------------------------------
; rs_set_cell — rbx = raster, edi = cell x, esi = cell y.
;   Stores the current cell when the position changes.
;   Clobbers rax, rcx, rdx, rsi, rdi, r8-r11.
; -----------------------------------------------------------------------------
rs_set_cell:
    cmp edi, [rbx + UgfxRaster_cur_x]
    jne .set_change
    cmp esi, [rbx + UgfxRaster_cur_y]
    jne .set_change
    ret
.set_change:
    push rdi
    push rsi
    call rs_push_cell
    pop rsi
    pop rdi
    mov [rbx + UgfxRaster_cur_x], edi
    mov [rbx + UgfxRaster_cur_y], esi
    xor eax, eax
    mov [rbx + UgfxRaster_cover], eax
    mov [rbx + UgfxRaster_area], eax
    ret

; -----------------------------------------------------------------------------
; rs_push_cell — rbx = raster. Appends the current cell if it has coverage
;   and can affect a visible pixel. Clobbers rax, rcx, rdx, rsi, rdi, r8-r11.
; -----------------------------------------------------------------------------
rs_push_cell:
    mov eax, [rbx + UgfxRaster_cover]
    or eax, [rbx + UgfxRaster_area]
    jz .push_done
    mov eax, [rbx + UgfxRaster_cur_y]
    test eax, eax
    js .push_done                       ; above the clip area
    cmp eax, [rbx + UgfxRaster_height]
    jge .push_done                      ; below it
    ; Columns outside the clip area collapse onto its edges: left cells keep
    ; carrying cover from column -1, right cells end the row's span at
    ; column width. Neither column is drawn.
    mov edx, [rbx + UgfxRaster_cur_x]
    cmp edx, [rbx + UgfxRaster_width]
    jl .push_x_left
    mov edx, [rbx + UgfxRaster_width]
    jmp .push_x_ready
.push_x_left:
    test edx, edx
    jns .push_x_ready
    mov edx, -1
.push_x_ready:
    mov ecx, [rbx + UgfxRaster_count]
    cmp ecx, [rbx + UgfxRaster_cap]
    jb .push_store
    push rdx                            ; clamped column survives the call
    call rs_grow
    pop rdx
    test eax, eax                       ; rs_grow's result
    jnz .push_done
    mov ecx, [rbx + UgfxRaster_count]
.push_store:
    mov r8, [rbx + UgfxRaster_cells]
    shl rcx, 4
    add r8, rcx
    mov [r8], edx
    mov eax, [rbx + UgfxRaster_cur_y]
    mov [r8 + 4], eax
    mov eax, [rbx + UgfxRaster_cover]
    mov [r8 + 8], eax
    mov eax, [rbx + UgfxRaster_area]
    mov [r8 + 12], eax
    inc dword [rbx + UgfxRaster_count]
.push_done:
    ret

; rbx = raster -> eax = 0 or -ENOMEM (sticky in UgfxRaster_error).
rs_grow:
    mov eax, [rbx + UgfxRaster_cap]
    cmp eax, 0x08000000
    jae .grow_fail                      ; 128M cells is the limit
    lea esi, [rax + rax]
    shl rsi, 4
    mov rdi, [rbx + UgfxRaster_arena]
    call arena_alloc
    test rax, rax
    jz .grow_fail
    mov rdi, rax
    mov rsi, [rbx + UgfxRaster_cells]
    mov ecx, [rbx + UgfxRaster_count]
    shl rcx, 4
    rep movsb
    mov [rbx + UgfxRaster_cells], rax
    shl dword [rbx + UgfxRaster_cap], 1
    xor eax, eax
    ret
.grow_fail:
    mov dword [rbx + UgfxRaster_error], 1
    mov eax, -(ENOMEM)
    ret

; -----------------------------------------------------------------------------
; rs_hline — rbx = raster; edi = cell row, esi = x1, edx = fy1, ecx = x2,
;   r8d = fy2 (x in 24.8, fy = subpixel row within the cell, 0..256).
;   Distributes one row's worth of an edge over the cells it crosses.
; -----------------------------------------------------------------------------
%define H_EY    0
%define H_EX1   8
%define H_EX2   16
%define H_FX1   24
%define H_FX2   32
%define H_FIRST 40
%define H_INCR  48
%define H_Y1    56
%define H_Y2    64
%define H_DX    72
%define H_MOD   80
%define H_LIFT  88
%define H_REM   96
%define H_DY    104
%define H_SIZE  112

rs_hline:
    sub rsp, H_SIZE
    movsxd rax, edi
    mov [rsp + H_EY], rax
    movsxd rax, esi
    movsxd r9, ecx
    mov r10, rax
    sar r10, SHIFT
    mov [rsp + H_EX1], r10
    mov r10, r9
    sar r10, SHIFT
    mov [rsp + H_EX2], r10
    mov r10, rax
    and r10, MASK
    mov [rsp + H_FX1], r10
    mov r10, r9
    and r10, MASK
    mov [rsp + H_FX2], r10
    sub r9, rax
    mov [rsp + H_DX], r9                ; x2 - x1
    movsxd rax, edx
    mov [rsp + H_Y1], rax
    movsxd r9, r8d
    mov [rsp + H_Y2], r9
    sub r9, rax
    mov [rsp + H_DY], r9                ; y2 - y1
    jnz .hl_not_flat
    ; no vertical extent: only move to the end cell
    mov rdi, [rsp + H_EX2]
    mov rsi, [rsp + H_EY]
    call rs_set_cell
    add rsp, H_SIZE
    ret
.hl_not_flat:
    mov rax, [rsp + H_EX1]
    cmp rax, [rsp + H_EX2]
    jne .hl_multi
    ; a single cell
    mov rax, [rsp + H_DY]
    add [rbx + UgfxRaster_cover], eax
    mov rcx, [rsp + H_FX1]
    add rcx, [rsp + H_FX2]
    imul rcx, rax
    add [rbx + UgfxRaster_area], ecx
    add rsp, H_SIZE
    ret
.hl_multi:
    mov rcx, [rsp + H_DX]
    test rcx, rcx
    js .hl_left
    mov rax, SCALE
    sub rax, [rsp + H_FX1]
    imul rax, [rsp + H_DY]              ; p = (scale - fx1) * dy
    mov qword [rsp + H_FIRST], SCALE
    mov qword [rsp + H_INCR], 1
    jmp .hl_first
.hl_left:
    mov rax, [rsp + H_FX1]
    imul rax, [rsp + H_DY]              ; p = fx1 * dy
    mov qword [rsp + H_FIRST], 0
    mov qword [rsp + H_INCR], -1
    neg rcx
    mov [rsp + H_DX], rcx
.hl_first:
    FLOORDIV rcx
    mov [rsp + H_MOD], rdx
    add [rbx + UgfxRaster_cover], eax
    mov rcx, [rsp + H_FX1]
    add rcx, [rsp + H_FIRST]
    imul rcx, rax
    add [rbx + UgfxRaster_area], ecx
    add [rsp + H_Y1], rax
    mov rax, [rsp + H_EX1]
    add rax, [rsp + H_INCR]
    mov [rsp + H_EX1], rax
    mov edi, eax
    mov rsi, [rsp + H_EY]
    call rs_set_cell
    mov rax, [rsp + H_EX1]
    cmp rax, [rsp + H_EX2]
    je .hl_last
    mov rax, [rsp + H_DY]
    shl rax, SHIFT                      ; p = scale * dy
    mov rcx, [rsp + H_DX]
    FLOORDIV rcx
    mov [rsp + H_LIFT], rax
    mov [rsp + H_REM], rdx
    mov rax, [rsp + H_MOD]
    sub rax, [rsp + H_DX]
    mov [rsp + H_MOD], rax
.hl_loop:
    mov rax, [rsp + H_LIFT]
    mov rdx, [rsp + H_MOD]
    add rdx, [rsp + H_REM]
    test rdx, rdx
    js .hl_no_carry
    sub rdx, [rsp + H_DX]
    inc rax
.hl_no_carry:
    mov [rsp + H_MOD], rdx
    add [rbx + UgfxRaster_cover], eax
    mov ecx, eax
    shl ecx, SHIFT
    add [rbx + UgfxRaster_area], ecx
    add [rsp + H_Y1], rax
    mov rax, [rsp + H_EX1]
    add rax, [rsp + H_INCR]
    mov [rsp + H_EX1], rax
    mov edi, eax
    mov rsi, [rsp + H_EY]
    call rs_set_cell
    mov rax, [rsp + H_EX1]
    cmp rax, [rsp + H_EX2]
    jne .hl_loop
.hl_last:
    mov rax, [rsp + H_Y2]
    sub rax, [rsp + H_Y1]
    add [rbx + UgfxRaster_cover], eax
    mov rcx, [rsp + H_FX2]
    add rcx, SCALE
    sub rcx, [rsp + H_FIRST]
    imul rcx, rax
    add [rbx + UgfxRaster_area], ecx
    add rsp, H_SIZE
    ret

; -----------------------------------------------------------------------------
; rs_line — rbx = raster; edi = x1, esi = y1, edx = x2, ecx = y2 (24.8).
;   Splits an edge into per-row runs for rs_hline.
; -----------------------------------------------------------------------------
%define L_X1    0
%define L_X2    8
%define L_EY1   16
%define L_EY2   24
%define L_FY1   32
%define L_FY2   40
%define L_DX    48
%define L_DY    56
%define L_FIRST 64
%define L_INCR  72
%define L_MOD   80
%define L_LIFT  88
%define L_REM   96
%define L_XFROM 104
%define L_SIZE  112

rs_line:
    sub rsp, L_SIZE
    movsxd rax, edi
    mov [rsp + L_X1], rax
    movsxd rax, edx
    mov [rsp + L_X2], rax
    sub rax, [rsp + L_X1]
    mov [rsp + L_DX], rax
    movsxd rax, esi
    movsxd r9, ecx
    mov r10, r9
    sub r10, rax
    mov [rsp + L_DY], r10
    mov r10, rax
    sar r10, SHIFT
    mov [rsp + L_EY1], r10
    and rax, MASK
    mov [rsp + L_FY1], rax
    mov r10, r9
    sar r10, SHIFT
    mov [rsp + L_EY2], r10
    and r9, MASK
    mov [rsp + L_FY2], r9
    mov rax, [rsp + L_EY1]
    cmp rax, [rsp + L_EY2]
    jne .ln_rows
    ; the whole edge lies in one cell row
    mov edi, eax
    mov rsi, [rsp + L_X1]
    mov rdx, [rsp + L_FY1]
    mov rcx, [rsp + L_X2]
    mov r8, [rsp + L_FY2]
    call rs_hline
    add rsp, L_SIZE
    ret
.ln_rows:
    mov rcx, [rsp + L_DY]
    test rcx, rcx
    js .ln_up
    mov rax, SCALE
    sub rax, [rsp + L_FY1]
    imul rax, [rsp + L_DX]              ; p = (scale - fy1) * dx
    mov qword [rsp + L_FIRST], SCALE
    mov qword [rsp + L_INCR], 1
    jmp .ln_first
.ln_up:
    mov rax, [rsp + L_FY1]
    imul rax, [rsp + L_DX]              ; p = fy1 * dx
    mov qword [rsp + L_FIRST], 0
    mov qword [rsp + L_INCR], -1
    neg rcx
    mov [rsp + L_DY], rcx
.ln_first:
    FLOORDIV rcx
    mov [rsp + L_MOD], rdx
    add rax, [rsp + L_X1]
    mov [rsp + L_XFROM], rax
    mov rdi, [rsp + L_EY1]
    mov rsi, [rsp + L_X1]
    mov rdx, [rsp + L_FY1]
    mov rcx, rax
    mov r8, [rsp + L_FIRST]
    call rs_hline
    mov rax, [rsp + L_EY1]
    add rax, [rsp + L_INCR]
    mov [rsp + L_EY1], rax
    mov rdi, [rsp + L_XFROM]
    sar rdi, SHIFT
    mov esi, eax
    call rs_set_cell
    mov rax, [rsp + L_EY1]
    cmp rax, [rsp + L_EY2]
    je .ln_last
    mov rax, [rsp + L_DX]
    shl rax, SHIFT                      ; p = scale * dx
    mov rcx, [rsp + L_DY]
    FLOORDIV rcx
    mov [rsp + L_LIFT], rax
    mov [rsp + L_REM], rdx
    mov rax, [rsp + L_MOD]
    sub rax, [rsp + L_DY]
    mov [rsp + L_MOD], rax
.ln_loop:
    mov rax, [rsp + L_LIFT]
    mov rdx, [rsp + L_MOD]
    add rdx, [rsp + L_REM]
    test rdx, rdx
    js .ln_no_carry
    sub rdx, [rsp + L_DY]
    inc rax
.ln_no_carry:
    mov [rsp + L_MOD], rdx
    mov rcx, [rsp + L_XFROM]
    add rcx, rax                        ; x_to
    push rcx
    mov rdi, [rsp + 8 + L_EY1]
    mov rsi, [rsp + 8 + L_XFROM]
    mov edx, SCALE
    sub rdx, [rsp + 8 + L_FIRST]
    mov r8, [rsp + 8 + L_FIRST]
    call rs_hline
    pop rcx
    mov [rsp + L_XFROM], rcx
    mov rax, [rsp + L_EY1]
    add rax, [rsp + L_INCR]
    mov [rsp + L_EY1], rax
    mov rdi, rcx
    sar rdi, SHIFT
    mov esi, eax
    call rs_set_cell
    mov rax, [rsp + L_EY1]
    cmp rax, [rsp + L_EY2]
    jne .ln_loop
.ln_last:
    mov rdi, [rsp + L_EY1]
    mov rsi, [rsp + L_XFROM]
    mov edx, SCALE
    sub rdx, [rsp + L_FIRST]
    mov rcx, [rsp + L_X2]
    mov r8, [rsp + L_FY2]
    call rs_hline
    add rsp, L_SIZE
    ret

; -----------------------------------------------------------------------------
; ugfx_raster_fill — close, sort and sweep the cells, compositing a solid
;   colour into the buffer.
;   IN:  rdi = UgfxRaster*, rsi = PixBuf*, edx = colour (premultiplied BGRA),
;        ecx = UGFX_FILL_NONZERO or UGFX_FILL_EVENODD
;   OUT: rax = 0, -EINVAL, -ENOMEM. The raster is reset afterwards.
;
; ugfx_raster_fill_paint — the same with a paint (gradient, pattern), through
;   the paint's own span function (UgfxPaint_span):
;   IN:  rdi = UgfxRaster*, rsi = PixBuf*, rdx = const UgfxPaint*, ecx = rule
;
; ugfx_raster_fill_mask — the same into a coverage mask: each pixel becomes
;   the union m = c + m (255 - c) / 255 (ugfx_span_mask_union)
;   IN:  rdi = UgfxRaster*, rsi = UgfxMask*, ecx = rule
;
; With a clip (ugfx_raster_set_clip) every fill's coverage is multiplied by
; the clip mask: rs_span_clipped splits each run where the mask value
; changes and hands the pieces to the fill's span function.
;
; Both sweep into a span function with ugfx_span_fill_solid's registers
; (rdi = PixBuf*, esi = x, edx = y, ecx = length, r8d = coverage, r9 = the
; colour or the paint).
; -----------------------------------------------------------------------------
%define F_PIXBUF 0
%define F_ARG    8                      ; colour or UgfxPaint*, passed in r9
%define F_RULE   16
%define F_COUNT  20
%define F_KEYS   24
%define F_TEMP   32
%define F_ROW    40
%define F_COVER  44
%define F_X      48
%define F_SPAN   56                     ; span function
%define F_CLIP   64                     ; clipped: span, argument, mask
%define F_COUNTS 88                     ; u32[256] radix histogram
%define F_SIZE   (88 + 1024)            ; keeps calls 16-byte aligned

global ugfx_raster_fill
ugfx_raster_fill:
    lea r8, [rel ugfx_span_fill_solid]
    mov edx, edx
    jmp rs_fill

global ugfx_raster_fill_mask
ugfx_raster_fill_mask:
    lea r8, [rel ugfx_span_mask_union]
    xor edx, edx
    jmp rs_fill

global ugfx_raster_fill_paint
ugfx_raster_fill_paint:
    test rdx, rdx
    jz .paint_bad
    mov r8, [rdx + UgfxPaint_span]      ; set by the paint's constructor
    test r8, r8
    jnz rs_fill
.paint_bad:
    mov rax, -(EINVAL)
    ret

; rdi = raster, rsi = PixBuf*, rdx = span argument, ecx = rule, r8 = span
rs_fill:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, F_SIZE
    mov rbx, rdi
    test rdi, rdi
    jz .fill_bad
    test rsi, rsi
    jz .fill_bad
    cmp ecx, UGFX_FILL_EVENODD
    ja .fill_bad
    mov [rsp + F_PIXBUF], rsi
    mov [rsp + F_ARG], rdx
    mov [rsp + F_RULE], ecx
    mov [rsp + F_SPAN], r8
    ; a clip wraps the span function
    mov rax, [rbx + UgfxRaster_clip]
    test rax, rax
    jz .fill_unclipped
    mov [rsp + F_CLIP + 16], rax
    mov [rsp + F_CLIP], r8
    mov [rsp + F_CLIP + 8], rdx
    lea rax, [rel rs_span_clipped]
    mov [rsp + F_SPAN], rax
    lea rax, [rsp + F_CLIP]
    mov [rsp + F_ARG], rax
.fill_unclipped:
    call rs_close
    call rs_push_cell
    mov dword [rbx + UgfxRaster_cur_x], 0x7FFFFFFF
    mov dword [rbx + UgfxRaster_cur_y], 0x7FFFFFFF
    xor eax, eax
    mov [rbx + UgfxRaster_cover], eax
    mov [rbx + UgfxRaster_area], eax
    cmp dword [rbx + UgfxRaster_error], 0
    jne .fill_nomem
    mov r13d, [rbx + UgfxRaster_count]
    mov [rsp + F_COUNT], r13d
    test r13d, r13d
    jz .fill_done
    ; key/index pairs: key = row << 16 | (column + 1)
    mov rdi, [rbx + UgfxRaster_arena]
    mov esi, r13d
    shl rsi, 3
    call arena_alloc
    test rax, rax
    jz .fill_nomem
    mov [rsp + F_KEYS], rax
    mov rdi, [rbx + UgfxRaster_arena]
    mov esi, r13d
    shl rsi, 3
    call arena_alloc
    test rax, rax
    jz .fill_nomem
    mov [rsp + F_TEMP], rax
    mov r12, [rsp + F_KEYS]
    mov r15, [rbx + UgfxRaster_cells]
    xor ecx, ecx
.fill_keys:
    mov rdx, rcx
    shl rdx, 4
    mov eax, [r15 + rdx + 4]            ; row
    shl eax, 16
    mov edx, [r15 + rdx]                ; column, >= -1
    inc edx
    or eax, edx
    mov [r12 + rcx * 8], eax
    mov [r12 + rcx * 8 + 4], ecx
    inc ecx
    cmp ecx, r13d
    jb .fill_keys
    ; LSD radix sort, four byte passes (stable), ends back in F_KEYS
    xor r14d, r14d                      ; shift
.radix_pass:
    lea rdi, [rsp + F_COUNTS]
    xor eax, eax
    mov ecx, 256
    rep stosd
    mov r12, [rsp + F_KEYS]
    xor ecx, ecx
.radix_count:
    mov eax, [r12 + rcx * 8]
    xchg ecx, r14d
    shr eax, cl
    xchg ecx, r14d
    and eax, 255
    inc dword [rsp + F_COUNTS + rax * 4]
    inc ecx
    cmp ecx, r13d
    jb .radix_count
    xor eax, eax
    xor ecx, ecx
.radix_prefix:
    mov edx, [rsp + F_COUNTS + rcx * 4]
    mov [rsp + F_COUNTS + rcx * 4], eax
    add eax, edx
    inc ecx
    cmp ecx, 256
    jb .radix_prefix
    mov r8, [rsp + F_TEMP]
    xor ecx, ecx
.radix_scatter:
    mov rdx, [r12 + rcx * 8]
    mov eax, edx
    xchg ecx, r14d
    shr eax, cl
    xchg ecx, r14d
    and eax, 255
    mov r9d, [rsp + F_COUNTS + rax * 4]
    inc dword [rsp + F_COUNTS + rax * 4]
    mov [r8 + r9 * 8], rdx
    inc ecx
    cmp ecx, r13d
    jb .radix_scatter
    mov [rsp + F_TEMP], r12
    mov [rsp + F_KEYS], r8
    add r14d, 8
    cmp r14d, 32
    jb .radix_pass
    ; sweep: r12 = sorted keys, r13d = count, r14d = index, r15 = cells
    mov r12, [rsp + F_KEYS]
    xor r14d, r14d
.sweep_row:
    cmp r14d, r13d
    jae .fill_done
    mov eax, [r12 + r14 * 8]
    shr eax, 16
    mov [rsp + F_ROW], eax
    mov dword [rsp + F_COVER], 0
.sweep_cell:
    mov eax, [r12 + r14 * 8]
    mov edx, eax
    and eax, 0xFFFF
    dec eax
    mov [rsp + F_X], eax                ; column of this cell group
    xor r10d, r10d                      ; summed area
.sweep_same:
    mov ecx, [r12 + r14 * 8 + 4]
    shl rcx, 4
    add r10d, [r15 + rcx + 12]
    mov eax, [r15 + rcx + 8]
    add [rsp + F_COVER], eax
    inc r14d
    cmp r14d, r13d
    jae .sweep_group_done
    cmp [r12 + r14 * 8], edx
    je .sweep_same
.sweep_group_done:
    test r10d, r10d
    jz .sweep_span
    ; the cell's own pixel: (cover << (shift + 1)) - area
    mov eax, [rsp + F_COVER]
    shl eax, SHIFT + 1
    sub eax, r10d
    call rs_alpha
    test eax, eax
    jz .sweep_cell_skip
    mov r8d, eax
    mov esi, [rsp + F_X]
    test esi, esi
    js .sweep_cell_skip
    mov rdi, [rsp + F_PIXBUF]
    mov edx, [rsp + F_ROW]
    mov ecx, 1
    mov r9, [rsp + F_ARG]
    call [rsp + F_SPAN]
.sweep_cell_skip:
    inc dword [rsp + F_X]
.sweep_span:
    ; the run up to the next cell in this row, at the running cover
    cmp r14d, r13d
    jae .fill_done
    mov eax, [r12 + r14 * 8]
    shr eax, 16
    cmp eax, [rsp + F_ROW]
    jne .sweep_row
    mov ecx, [r12 + r14 * 8]
    and ecx, 0xFFFF
    dec ecx                             ; next column
    sub ecx, [rsp + F_X]
    jle .sweep_cell
    push rcx
    mov eax, [rsp + 8 + F_COVER]
    shl eax, SHIFT + 1
    call rs_alpha_frame8
    pop rcx
    test eax, eax
    jz .sweep_cell
    mov r8d, eax
    mov rdi, [rsp + F_PIXBUF]
    mov esi, [rsp + F_X]
    mov edx, [rsp + F_ROW]
    mov r9, [rsp + F_ARG]
    call [rsp + F_SPAN]
    jmp .sweep_cell
.fill_done:
    mov rdi, rbx
    call ugfx_raster_reset
    xor eax, eax
    add rsp, F_SIZE
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
.fill_bad:
    mov rax, -(EINVAL)
    add rsp, F_SIZE
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
.fill_nomem:
    mov rdi, rbx
    call ugfx_raster_reset
    mov rax, -(ENOMEM)
    add rsp, F_SIZE
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15

; -----------------------------------------------------------------------------
; ugfx_raster_set_clip — rdi = UgfxRaster*, rsi = const UgfxMask* or 0 (no
;   clip) -> rax = 0, -EINVAL. Pixels outside the mask are clipped away.
; -----------------------------------------------------------------------------
global ugfx_raster_set_clip
ugfx_raster_set_clip:
    test rdi, rdi
    jz .clip_bad
    test rsi, rsi
    jz .clip_set
    cmp qword [rsi + UgfxMask_data], 0
    je .clip_bad
.clip_set:
    mov [rdi + UgfxRaster_clip], rsi
    xor eax, eax
    ret
.clip_bad:
    mov rax, -(EINVAL)
    ret

; -----------------------------------------------------------------------------
; rs_span_clipped — span function under a clip: rdi = target, esi = x,
;   edx = y, ecx = length, r8d = coverage, r9 = [span, argument, mask].
;   Each run of equal mask values goes to the span at round(c m / 255).
; -----------------------------------------------------------------------------
rs_span_clipped:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 24
    mov rbx, r9
    mov r12, rdi                        ; target
    mov [rsp], r8d                      ; coverage
    mov r10, [rbx + 16]                 ; mask
    test edx, edx
    js .sc_done
    movsxd r13, edx                     ; y
    cmp r13, [r10 + UgfxMask_height]
    jae .sc_done                        ; below the mask: clipped
    movsxd r14, esi                     ; x
    movsxd rcx, ecx
    lea r15, [r14 + rcx]                ; end
    xor eax, eax
    test r14, r14
    cmovs r14, rax
    cmp r15, [r10 + UgfxMask_width]
    jle .sc_end
    mov r15, [r10 + UgfxMask_width]
.sc_end:
    mov rax, r13
    imul rax, [r10 + UgfxMask_stride]
    add rax, [r10 + UgfxMask_data]
    mov [rsp + 8], rax                  ; mask row
.sc_run:
    cmp r14, r15
    jge .sc_done
    mov rdx, [rsp + 8]
    movzx r9d, byte [rdx + r14]         ; this run's mask value
    lea rcx, [r14 + 1]
.sc_extend:
    cmp rcx, r15
    jge .sc_have_run
    cmp [rdx + rcx], r9b
    jne .sc_have_run
    inc rcx
    jmp .sc_extend
.sc_have_run:
    mov [rsp + 16], rcx                 ; run end
    test r9d, r9d
    jz .sc_next
    mov eax, [rsp]
    imul eax, r9d
    add eax, 128
    mov edx, eax
    shr edx, 8
    add eax, edx
    shr eax, 8                          ; round(c m / 255)
    test eax, eax
    jz .sc_next
    mov r8d, eax
    mov rdi, r12
    mov esi, r14d
    mov edx, r13d
    sub ecx, r14d
    mov r9, [rbx + 8]
    call [rbx]
.sc_next:
    mov r14, [rsp + 16]
    jmp .sc_run
.sc_done:
    xor eax, eax
    add rsp, 24
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15

; -----------------------------------------------------------------------------
; ugfx_raster_set_alpha — rdi = UgfxRaster*, esi = alpha 0..255 (global
;   opacity: every fill's coverage is multiplied by it) -> rax = 0, -EINVAL
; -----------------------------------------------------------------------------
global ugfx_raster_set_alpha
ugfx_raster_set_alpha:
    test rdi, rdi
    jz .alpha_bad
    cmp esi, 255
    ja .alpha_bad
    mov [rdi + UgfxRaster_alpha], esi
    xor eax, eax
    ret
.alpha_bad:
    mov rax, -(EINVAL)
    ret

; eax = cover << 9 minus area -> eax = coverage 0..255 for the rule at
; [rsp + 8 + F_RULE] (called from ugfx_raster_fill's frame).
rs_alpha:
    mov ecx, [rsp + 8 + F_RULE]
    jmp rs_alpha_rule
; Same, called with one extra qword pushed on the fill frame. Both apply the
; raster's alpha into account (rbx = raster).
rs_alpha_frame8:
    mov ecx, [rsp + 16 + F_RULE]
rs_alpha_rule:
    sar eax, SHIFT * 2 + 1 - 8
    cdq
    xor eax, edx
    sub eax, edx                        ; |coverage| in 1/256
    cmp ecx, UGFX_FILL_EVENODD
    jne .alpha_clamp
    and eax, 511
    cmp eax, 256
    jbe .alpha_clamp
    neg eax
    add eax, 512
.alpha_clamp:
    cmp eax, 255
    jbe .alpha_global
    mov eax, 255
.alpha_global:
    mov ecx, [rbx + UgfxRaster_alpha]
    cmp ecx, 255
    je .alpha_done
    imul eax, ecx                       ; round(coverage * alpha / 255)
    add eax, 128
    mov edx, eax
    shr edx, 8
    add eax, edx
    shr eax, 8
.alpha_done:
    ret

section .data
global ugfx_raster_version
ugfx_raster_version: dq 0x010000
