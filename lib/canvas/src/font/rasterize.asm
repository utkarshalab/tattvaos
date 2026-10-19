; ============================================================================
; Glyph Rasterization — Scanline Conversion of Glyph Outlines
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/fixed.inc"
%include "inc/font.inc"
%include "inc/externs.inc"

section .text

; ============================================================================
; glyph_rasterize
;   Rasterize glyph outline to alpha bitmap
;   IN: rdi = glyph_outline*, rsi = bitmap*, rdx = width, rcx = height, r8 = scale
;   OUT: rax = 0 OK
; ============================================================================
global glyph_rasterize
glyph_rasterize:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi        ; outline
    mov r12, rsi        ; bitmap
    mov r13d, edx       ; width
    mov r14d, ecx       ; height
    mov r15d, r8d       ; scale (16.16 fixed)
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Clear bitmap
    mov rdi, r12
    mov ecx, r13d
    imul ecx, r14d
    xor eax, eax
    rep stosb

    ; Get outline data
    mov r13, [rbx + GlyphOut_VERBS]
    mov r14, [rbx + GlyphOut_COORDS]
    mov r15d, [rbx + GlyphOut_COUNT]

    ; Build edge table for scanline conversion
    call .build_glyph_edges

    ; Fill scanlines
    call .fill_glyph_scanlines

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ============================================================================
; .build_glyph_edges - Build edge table from glyph outline
; ============================================================================
.build_glyph_edges:
    ; Edge table per scanline
    %define GLYPH_EDGE_X       0
    %define GLYPH_EDGE_DX_DY   4
    %define GLYPH_EDGE_Y_MAX   8
    %define GLYPH_EDGE_NEXT    12
    %define GLYPH_EDGE_SIZE    16

    ; Find glyph bounds
    mov r8d, 0x7FFFFFFF
    mov r9d, 0x80000000
    xor r10d, r10d

.bounds_loop:
    cmp r10d, r15d
    jge .bounds_done

    ; Read point
    mov eax, [r14 + r10*8]
    cmp eax, r8d
    jge .check_max_x
    mov r8d, eax
.check_max_x:
    cmp eax, r9d
    jle .check_y
    mov r9d, eax

.check_y:
    mov eax, [r14 + r10*8 + 4]
    ; ... track y bounds

    inc r10d
    jmp .bounds_loop

.bounds_done:
    ; Allocate edge buckets (one per scanline)
    mov eax, r15d
    sub eax, r14d
    inc eax
    shl eax, 3
    mov rdi, rax
    call arena_alloc
    test rax, rax
    jz .bounds_done
    mov r12, rax        ; edge table

    ; Clear buckets
    mov rdi, rax
    mov ecx, r15d
    sub ecx, r14d
    inc ecx
    xor rax, rax
    rep stosq

    ; Iterate outline verbs
    mov r13, [rbx + GlyphOut_VERBS]
    mov r14, [rbx + GlyphOut_COORDS]
    mov r15d, [rbx + GlyphOut_COUNT]
    xor r8d, r8d        ; point index
    xor r9d, r9d        ; verb index
    xor r10d, r10d      ; current x
    xor r11d, r11d      ; current y
    xor r12d, r12d      ; start x
    xor r13d, r13d      ; start y

.verb_loop:
    cmp r9d, [rbx + GlyphOut_COUNT]
    jge .build_done

    movzx eax, byte [r13 + r9]
    inc r9d

    cmp al, VERB_MOVE
    je .glyph_move
    cmp al, VERB_LINE
    je .glyph_line
    cmp al, VERB_QUAD
    je .glyph_quad
    cmp al, VERB_CUBIC
    je .glyph_cubic
    cmp al, VERB_CLOSE
    je .glyph_close
    jmp .verb_loop

.glyph_move:
    ; Move to
    mov eax, [r14 + r8*8]
    mov r10d, eax
    mov eax, [r14 + r8*8 + 4]
    mov r11d, eax
    mov r12d, eax
    mov r13d, eax
    add r8, 2
    jmp .verb_loop

.glyph_line:
    ; Line to
    mov eax, [r14 + r8*8]
    mov r14d, eax
    mov eax, [r14 + r8*8 + 4]
    mov r15d, eax
    call .add_glyph_edge
    add r8, 2
    jmp .verb_loop

.glyph_quad:
    ; Quadratic: flatten to lines first
    call .flatten_quad_to_edges
    add r8, 4
    jmp .verb_loop

.glyph_cubic:
    call .flatten_cubic_to_edges
    add r8, 6
    jmp .verb_loop

.glyph_close:
    ; Close path
    cmp r10d, r12d
    je .verb_loop
    cmp r11d, r13d
    je .verb_loop
    mov r14d, r12d
    mov r15d, r13d
    call .add_glyph_edge
    jmp .verb_loop

.build_done:
    ret

; ============================================================================
; .add_glyph_edge - Add edge to edge table
;   r10,r11 = start, r14,r15 = end
; ============================================================================
.add_glyph_edge:
    ; Skip horizontal
    cmp r11d, r15d
    je .edge_done

    ; Ensure y0 < y1
    cmp r11d, r15d
    jl .order_ok
    xchg r10d, r14d
    xchg r11d, r15d
.order_ok:

    ; Compute dx/dy (16.16 fixed)
    mov eax, r14d
    sub eax, r10d
    shl eax, 16
    mov ebx, r15d
    sub ebx, r11d
    idiv ebx
    mov r14d, eax        ; dx_dy

    ; x at y_min
    mov eax, r11d
    imul eax, r14d
    sar eax, 16
    add eax, r10d
    mov r10d, eax        ; x at y_min

    ; Allocate edge node
    mov rdi, GLYPH_EDGE_SIZE
    call arena_alloc
    test rax, rax
    jz .edge_done

    ; Fill edge
    mov [rax + GLYPH_EDGE_Y_MAX], r15d
    mov [rax + GLYPH_EDGE_X], r10d
    mov [rax + GLYPH_EDGE_DX_DY], r14d
    mov edx, r11d
    sub edx, r14d
    shl edx, 3
    mov rdx, [r12 + rdx]
    mov [rax + GLYPH_EDGE_NEXT], rdx
    mov edx, r11d
    sub edx, r14d
    shl edx, 3
    mov [r12 + rdx], rax

.edge_done:
    ret

; ============================================================================
; .fill_glyph_scanlines - Fill glyph scanlines from edge table
; ============================================================================
.fill_glyph_scanlines:
    %define AET_X       0
    %define AET_DX_DY   4
    %define AET_Y_MAX   8
    %define AET_NEXT    12
    %define AET_SIZE    16

    mov r8d, r14d       ; y = y_min

.fill_y_loop:
    cmp r8d, r15d
    jge .fill_done

    ; Add edges from ET[y]
    call .add_aet_edges

    ; Sort AET by x
    call .sort_aet_glyph

    ; Fill spans (even-odd rule for glyphs)
    call .fill_glyph_spans

    ; Update AET
    inc r8d
    jmp .fill_y_loop

.fill_done:
    ret

.add_aet_edges:
    ret

.sort_aet_glyph:
    ret

.fill_glyph_spans:
    ret

; ============================================================================
; .flatten_quad_to_edges - Flatten quadratic to line edges
; ============================================================================
.flatten_quad_to_edges:
    ret

; ============================================================================
; .flatten_cubic_to_edges - Flatten cubic to line edges
; ============================================================================
.flatten_cubic_to_edges:
    ret

section .data
global glyph_rasterize_version
glyph_rasterize_version: dq 0x010000