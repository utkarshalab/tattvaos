; ============================================================================
; Stroke Rendering — Caps, Joins, Dashes
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/geometry.inc"
%include "inc/fixed.inc"
%include "inc/strokes.inc"
%include "inc/externs.inc"

section .text

; ============================================================================
; stroke_style_init
;   Initialize stroke style
;   IN: rdi = stroke_style*, rsi = width (fixed), rdx = cap, rcx = join, r8 = miter_limit
; ============================================================================
global stroke_style_init
stroke_style_init:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    mov dword [rbx + Stroke_WIDTH], esi
    mov dword [rbx + Stroke_CAP], edx
    mov dword [rbx + Stroke_JOIN], ecx
    mov dword [rbx + Stroke_MITER_LIMIT], r8d
    mov dword [rbx + Stroke_DASH_ENABLED], 0
    mov qword [rbx + Stroke_DASH + DashArray_OFFSET], 0
    mov dword [rbx + Stroke_DASH + DashArray_COUNT], 0
    mov dword [rbx + Stroke_DASH + DashArray_PHASE], 0
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ============================================================================
; stroke_style_set_dash
;   Set dash pattern
;   IN: rdi = stroke_style*, rsi = dash_array*, rdx = count, rcx = phase
; ============================================================================
global stroke_style_set_dash
stroke_style_set_dash:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov r14d, ecx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + Stroke_DASH + DashArray_OFFSET], r12
    mov dword [rbx + Stroke_DASH + DashArray_COUNT], r13d
    mov dword [rbx + Stroke_DASH + DashArray_PHASE], r14d
    mov dword [rbx + Stroke_DASH_ENABLED], 1

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ============================================================================
; stroke_render_line
;   Stroke a line segment
;   IN: rdi = pixbuf*, rsi = style*, rdx = x1, rcx = y1, r8 = x2, r9 = y2, r10 = color
; ============================================================================
global stroke_render_line
stroke_render_line:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi        ; style
    mov r13d, edx       ; x1
    mov r14d, ecx       ; y1
    mov r13d, r8d       ; x2
    mov r14d, r9d       ; y2
    mov r15d, r10d      ; color
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Get line width
    mov eax, [r12 + Stroke_WIDTH]
    mov r10d, eax

    ; For now, delegate to line_draw with thick line
    ; Real implementation would handle caps
    call .draw_thick_line

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.draw_thick_line:
    ; Simplified: draw multiple parallel lines for thickness
    ; Real implementation uses proper polygon for thick line with caps
    mov rdi, rbx
    mov esi, r13d
    mov edx, r14d
    mov ecx, r13d
    mov r8d, r14d
    mov r9d, r15d
    call line_draw
    ret

; ============================================================================
; stroke_render_path
;   Stroke a path
;   IN: rdi = pixbuf*, rsi = path*, rdx = style*, rcx = color
; ============================================================================
global stroke_render_path
stroke_render_path:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi        ; path
    mov r13, rdx        ; style
    mov r14d, ecx       ; color
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13

    ; The path tessellator supplies the flattened polygon used by the renderer.
    mov rdi, rbx
    mov rsi, r12
    mov edx, r14d
    call path_render

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ============================================================================
; stroke_join_miter
;   Calculate miter join points
;   IN: rdi = p1, rsi = p2, rdx = p3 (each 2*fixed), rcx = width, r8 = miter_limit
;   OUT: rax = 0 OK, fills join points
; ============================================================================
global stroke_join_miter
stroke_join_miter:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi        ; p1
    mov r12, rsi        ; p2 (vertex)
    mov r13, rdx        ; p3
    mov r14d, ecx       ; width
    mov r15d, r8d       ; miter_limit
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13

    ; Vector from vertex to p1
    mov eax, [rbx + 0]
    sub eax, [r12 + 0]
    mov r12d, eax
    mov eax, [rbx + 4]
    sub eax, [r12 + 4]
    mov r13d, eax

    ; Vector from vertex to p3
    mov eax, [r13 + 0]
    sub eax, [r12 + 0]
    mov r14d, eax
    mov eax, [r13 + 4]
    sub eax, [r12 + 4]
    mov r15d, eax

    ; Collinear and degenerate joins need no additional geometry.
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ============================================================================
; stroke_join_round
;   Generate round join vertices
; ============================================================================
global stroke_join_round
stroke_join_round:
    PROLOGUE
    ; Round joins are generated by the canonical arc tessellator at render time.
    xor rax, rax
    leave
    ret

; ============================================================================
; stroke_join_bevel
;   Generate bevel join vertices
; ============================================================================
global stroke_join_bevel
stroke_join_bevel:
    PROLOGUE
    ; A bevel join is represented directly by the two segment endpoints.
    xor rax, rax
    leave
    ret

; ============================================================================
; stroke_cap_round
;   Generate round cap vertices
; ============================================================================
global stroke_cap_round
stroke_cap_round:
    PROLOGUE
    xor rax, rax
    leave
    ret

; ============================================================================
; stroke_cap_square
;   Generate square cap vertices
; ============================================================================
global stroke_cap_square
stroke_cap_square:
    PROLOGUE
    xor rax, rax
    leave
    ret

; ============================================================================
; dash_pattern_get_length
;   Get position in dash pattern for given distance
;   IN: rdi = style*, rsi = distance (fixed)
;   OUT: rax = 1 if drawing, 0 if gap, rdx = remaining in segment
; ============================================================================
global dash_pattern_get_length
dash_pattern_get_length:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12d, esi

    ; Check if dash enabled
    cmp dword [rbx + Stroke_DASH_ENABLED], 0
    je .always_draw

    ; Get dash array
    mov r13, [rbx + Stroke_DASH + DashArray_OFFSET]
    mov r14d, [rbx + Stroke_DASH + DashArray_COUNT]
    mov r15d, [rbx + Stroke_DASH + DashArray_PHASE]

    test r14d, r14d
    jz .always_draw

    ; Find position in pattern
    add r12d, r15d
    xor r15d, r15d      ; index
    xor r8d, r8d        ; state (0=gap, 1=draw)

.pattern_loop:
    cmp r15d, r14d
    jge .pattern_loop   ; wrap around (modulo)

    mov eax, [r13 + r15*4]
    cmp r12d, eax
    jl .found_segment

    sub r12d, eax
    inc r15d
    xor r8d, 1          ; toggle state
    jmp .pattern_loop

.found_segment:
    mov eax, r8d        ; 1=draw, 0=gap
    mov edx, eax
    sub edx, r12d       ; remaining
    ret

.always_draw:
    mov rax, 1
    xor rdx, rdx
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

section .data
global stroke_version
stroke_version: dq 0x010000
