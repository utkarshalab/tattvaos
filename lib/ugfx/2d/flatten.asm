; =============================================================================
; Utkarsha OS — lib/ugfx/2d/flatten.asm
; =============================================================================
; Flattening a path into polylines, and measuring it.
;
;   ugfx_path_flatten(dst, src, tolerance)   curves -> line segments
;   ugfx_path_length(path, tolerance)        total length of all contours
;
; The flattened copy keeps every MOVE and CLOSE of the source, so its
; contours match the source's one for one; quads and cubics become
; umath_bezier_*_segments lines through the curve (the end point exact).
; The length counts each contour's closing segment when it is closed.
; =============================================================================

%include "ugfx.inc"

extern ugfx_path_init
extern ugfx_path_move_to
extern ugfx_path_line_to
extern ugfx_path_close
extern umath_bezier_quad_eval
extern umath_bezier_cubic_eval
extern umath_bezier_quad_segments
extern umath_bezier_cubic_segments
extern umath_hypot_f64

; ugfx_path_flatten frame (r15)
%define F_DST       0
%define F_SRC       8
%define F_TOL       16
%define F_VERB      24                  ; u32
%define F_POINT     28                  ; u32
%define F_KIND      32                  ; u32 2 = quad, 3 = cubic
%define F_SEGN      40                  ; u64
%define F_SEGI      48
%define F_CURVE     56                  ; f64[8]
%define F_SIZE      120

section .rodata
align 8
flatten_default_tol: dq UGFX_PATH_TOLERANCE

section .text

; -----------------------------------------------------------------------------
; ugfx_path_flatten — rdi = destination UgfxPath*, rsi = source UgfxPath*,
;   xmm0 = tolerance in path units (<= 0 or NaN: UGFX_PATH_TOLERANCE)
;   -> rax = 0, -EINVAL, -ENOMEM. Appends to dst; dst must not be src.
; -----------------------------------------------------------------------------
global ugfx_path_flatten
ugfx_path_flatten:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, F_SIZE
    mov r15, rsp
    mov rax, -(EINVAL)
    test rdi, rdi
    jz .out
    test rsi, rsi
    jz .out
    cmp rdi, rsi
    je .out
    mov rax, -(ENOMEM)
    cmp dword [rsi + UgfxPath_error], 0
    jne .out
    mov [r15 + F_DST], rdi
    mov [r15 + F_SRC], rsi
    xorpd xmm1, xmm1
    ucomisd xmm0, xmm1
    jp .default_tol
    ja .tol_ready
.default_tol:
    movsd xmm0, [rel flatten_default_tol]
.tol_ready:
    movsd [r15 + F_TOL], xmm0
    mov dword [r15 + F_VERB], 0
    mov dword [r15 + F_POINT], 0
.verb:
    mov rbx, [r15 + F_SRC]
    mov eax, [r15 + F_VERB]
    cmp eax, [rbx + UgfxPath_verb_count]
    jae .done
    inc dword [r15 + F_VERB]
    mov rdx, [rbx + UgfxPath_verbs]
    movzx eax, byte [rdx + rax]
    cmp eax, PATH_VERB_MOVE
    je .v_move
    cmp eax, PATH_VERB_LINE
    je .v_line
    cmp eax, PATH_VERB_QUAD
    je .v_quad
    cmp eax, PATH_VERB_CUBIC
    je .v_cubic
    cmp eax, PATH_VERB_CLOSE
    je .v_close
    mov rax, -(EINVAL)
    jmp .out
.v_move:
    call fl_take_point
    mov rdi, [r15 + F_DST]
    call ugfx_path_move_to
    jmp .check
.v_line:
    call fl_take_point
    mov rdi, [r15 + F_DST]
    call ugfx_path_line_to
    jmp .check
.v_quad:
    mov dword [r15 + F_KIND], 2
    jmp .v_curve
.v_cubic:
    mov dword [r15 + F_KIND], 3
.v_curve:
    call fl_curve
    jmp .check
.v_close:
    mov rdi, [r15 + F_DST]
    call ugfx_path_close
.check:
    test rax, rax
    jz .verb
    jmp .out
.done:
    xor eax, eax
.out:
    add rsp, F_SIZE
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15

; next source point -> xmm0/xmm1
fl_take_point:
    mov rbx, [r15 + F_SRC]
    mov eax, [r15 + F_POINT]
    inc dword [r15 + F_POINT]
    shl rax, 4
    add rax, [rbx + UgfxPath_points]
    movsd xmm0, [rax]
    movsd xmm1, [rax + 8]
    ret

; the quad/cubic (F_KIND control points after the last point) as lines
;   -> rax = 0 or -errno
fl_curve:
    mov rbx, [r15 + F_SRC]
    mov eax, [r15 + F_POINT]
    test eax, eax
    jz .c_done                          ; curves always follow a point
    dec eax
    shl rax, 4
    add rax, [rbx + UgfxPath_points]
    mov ecx, [r15 + F_KIND]
    inc ecx
    shl ecx, 1                          ; doubles to copy
    xor edx, edx
.c_copy:
    movsd xmm0, [rax + rdx * 8]
    movsd [r15 + F_CURVE + rdx * 8], xmm0
    inc edx
    cmp edx, ecx
    jb .c_copy
    mov eax, [r15 + F_KIND]
    add [r15 + F_POINT], eax
    lea rdi, [r15 + F_CURVE]
    movsd xmm0, [r15 + F_TOL]
    cmp dword [r15 + F_KIND], 2
    jne .c_cubic_n
    call umath_bezier_quad_segments
    jmp .c_have_n
.c_cubic_n:
    call umath_bezier_cubic_segments
.c_have_n:
    mov [r15 + F_SEGN], rax
    mov qword [r15 + F_SEGI], 1
.c_point:
    mov rax, [r15 + F_SEGI]
    cmp rax, [r15 + F_SEGN]
    ja .c_done
    je .c_end_point
    cvtsi2sd xmm0, rax
    cvtsi2sd xmm1, qword [r15 + F_SEGN]
    divsd xmm0, xmm1
    lea rdi, [r15 + F_CURVE]
    cmp dword [r15 + F_KIND], 2
    jne .c_cubic_eval
    call umath_bezier_quad_eval
    jmp .c_add
.c_cubic_eval:
    call umath_bezier_cubic_eval
    jmp .c_add
.c_end_point:
    mov eax, [r15 + F_KIND]
    shl eax, 4
    movsd xmm0, [r15 + F_CURVE + rax]
    movsd xmm1, [r15 + F_CURVE + rax + 8]
.c_add:
    mov rdi, [r15 + F_DST]
    call ugfx_path_line_to
    test rax, rax
    jnz .c_out
    inc qword [r15 + F_SEGI]
    jmp .c_point
.c_done:
    xor eax, eax
.c_out:
    ret

; -----------------------------------------------------------------------------
; xmm0 = ugfx_path_length — rdi = UgfxPath*, rsi = arena for a flattened
;   copy, xmm0 = tolerance (as for ugfx_path_flatten)
;   -> xmm0 = length, rax = 0, -EINVAL, -ENOMEM (xmm0 = 0 on error)
; -----------------------------------------------------------------------------
global ugfx_path_length
ugfx_path_length:
    PROLOGUE_SAVE rbx, r12, r13, r14
    sub rsp, UgfxPath_SIZE + 24
    mov r12, rdi
    movsd [rsp + UgfxPath_SIZE], xmm0
    mov rax, -(EINVAL)
    test rdi, rdi
    jz .len_fail
    mov rdi, rsp
    call ugfx_path_init
    test rax, rax
    jnz .len_fail
    mov rdi, rsp
    mov rsi, r12
    movsd xmm0, [rsp + UgfxPath_SIZE]
    call ugfx_path_flatten
    test rax, rax
    jnz .len_fail
    ; sum the segments: rbx = verbs, r13 = point index, r14 = verb index
    xorpd xmm0, xmm0
    movsd [rsp + UgfxPath_SIZE + 8], xmm0       ; total
    xor r13d, r13d
    xor r14d, r14d
    mov r12d, -1                                ; contour's first point
.len_verb:
    cmp r14d, [rsp + UgfxPath_verb_count]
    jae .len_done
    mov rbx, [rsp + UgfxPath_verbs]
    movzx eax, byte [rbx + r14]
    inc r14d
    cmp eax, PATH_VERB_MOVE
    je .len_move
    cmp eax, PATH_VERB_CLOSE
    je .len_close
    ; LINE: from point r13 - 1 to r13
    mov eax, r13d
    inc r13d
    jmp .len_segment
.len_move:
    mov r12d, r13d
    inc r13d
    jmp .len_verb
.len_close:
    ; from the last point back to the contour's first
    lea eax, [r13 - 1]
    shl rax, 4
    add rax, [rsp + UgfxPath_points]
    mov ecx, r12d
    shl rcx, 4
    add rcx, [rsp + UgfxPath_points]
    movsd xmm0, [rcx]
    subsd xmm0, [rax]
    movsd xmm1, [rcx + 8]
    subsd xmm1, [rax + 8]
    jmp .len_add
.len_segment:
    shl rax, 4
    add rax, [rsp + UgfxPath_points]
    movsd xmm0, [rax]
    subsd xmm0, [rax - 16]
    movsd xmm1, [rax + 8]
    subsd xmm1, [rax - 8]
.len_add:
    call umath_hypot_f64
    addsd xmm0, [rsp + UgfxPath_SIZE + 8]
    movsd [rsp + UgfxPath_SIZE + 8], xmm0
    jmp .len_verb
.len_done:
    movsd xmm0, [rsp + UgfxPath_SIZE + 8]
    xor eax, eax
    add rsp, UgfxPath_SIZE + 24
    EPILOGUE_RESTORE rbx, r12, r13, r14
.len_fail:
    xorpd xmm0, xmm0
    add rsp, UgfxPath_SIZE + 24
    EPILOGUE_RESTORE rbx, r12, r13, r14

global ugfx_flatten_version
ugfx_flatten_version:
    mov eax, 1
    ret
