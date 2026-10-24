; =============================================================================
; Utkarsha OS — lib/ugfx/2d/stroke.asm
; =============================================================================
; Stroking: turns the contours of a path into the outline of their stroke,
; appended to another path as closed contours to fill with the nonzero rule.
;
;   ugfx_path_stroke(dst, src, style, tolerance)
;
; Each source contour is flattened (tolerance in user units), repeated
; points are dropped, and the offset sides at +/- width/2 are walked:
;   - outer side of each turn: miter (falls back to bevel past the miter
;     limit), round (an arc around the vertex) or bevel
;   - inner side: through the vertex itself, which stays correct for short
;     segments and is resolved by the nonzero fill
;   - open contours: left side, end cap, right side reversed, start cap -
;     one closed outline; caps are butt, round or square
;   - closed contours: the left side and the reversed right side as two
;     loops of opposite winding (a ring)
;   - a single point: a dot for round (circle) and square (square) caps
; Angles for round joins and caps come from umath_atan2_f64 and the arcs
; from umath_arc_to_cubics; lengths from umath_hypot_f64.
; =============================================================================

%include "ugfx.inc"

extern arena_alloc
extern ugfx_path_init
extern ugfx_path_reset
extern ugfx_path_move_to
extern ugfx_path_line_to
extern ugfx_path_cubic_to
extern ugfx_path_close
extern ugfx_path_add_circle
extern ugfx_path_add_rect
extern umath_bezier_quad_eval
extern umath_bezier_cubic_eval
extern umath_bezier_quad_segments
extern umath_bezier_cubic_segments
extern umath_arc_to_cubics
extern umath_atan2_f64
extern umath_hypot_f64

; frame, addressed through r15
%define K_DST       0
%define K_SRC       8
%define K_STYLE     16
%define K_TOL       24
%define K_H         32                  ; half width
%define K_LIMIT     40                  ; miter limit
%define K_JOIN      48                  ; u32
%define K_CAP       52                  ; u32
%define K_PTS       56                  ; f64 point list
%define K_PTCAP     64                  ; u32
%define K_N         68                  ; u32 points in the contour
%define K_CLOSED    72                  ; u32
%define K_VERB      76                  ; u32
%define K_POINT     80                  ; u32
%define K_SIDE      88                  ; f64 +1 or -1
%define K_TARGET    96                  ; path receiving the side
%define K_SEGS      104                 ; u32
%define K_I         108                 ; u32
%define K_CURVE     112                 ; f64[8]
%define K_TMP       176                 ; UgfxPath, right side
%define K_ARCBUF    240                 ; f64[24]
%define K_PX        432                 ; join vertex
%define K_PY        440
%define K_NPX       448                 ; previous segment normal
%define K_NPY       456
%define K_NCX       464                 ; current segment normal
%define K_NCY       472
%define K_DPX       480                 ; previous direction
%define K_DPY       488
%define K_DCX       496                 ; current direction
%define K_DCY       504
%define K_ARCN      512
%define K_ARCI      520
%define K_SEGN      528                 ; u64 curve segments
%define K_SEGI      536
%define K_KIND      544                 ; u32 2 = quad, 3 = cubic
%define K_ERR       548                 ; i32 first error
%define K_SEGLEN    552                 ; f64 length from the last st_segment
%define K_LP        560                 ; previous segment length
%define K_LC        568                 ; current segment length
%define K_SIZE      576

%define STROKE_INITIAL_POINTS 256

section .rodata
align 8
stroke_zero:        dq 0.0
stroke_one:         dq 1.0
stroke_neg_one:     dq -1.0
stroke_half:        dq 0.5
stroke_two:         dq 2.0
stroke_pi:          dq 3.141592653589793
stroke_eps:         dq 1.0e-9
stroke_cross_eps:   dq 1.0e-12
stroke_default_tol: dq UGFX_PATH_TOLERANCE

section .text

; -----------------------------------------------------------------------------
; ugfx_path_stroke — rdi = destination UgfxPath*, rsi = source UgfxPath*,
;   rdx = const UgfxStroke*, xmm0 = flattening tolerance in user units
;   (<= 0 or NaN: UGFX_PATH_TOLERANCE)
;   -> rax = 0, -EINVAL, -ENOMEM. dst must not be src.
; -----------------------------------------------------------------------------
global ugfx_path_stroke
ugfx_path_stroke:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, K_SIZE
    mov r15, rsp
    test rdi, rdi
    jz .bad
    test rsi, rsi
    jz .bad
    test rdx, rdx
    jz .bad
    cmp rdi, rsi
    je .bad
    mov [r15 + K_DST], rdi
    mov [r15 + K_SRC], rsi
    mov [r15 + K_STYLE], rdx
    mov dword [r15 + K_ERR], 0
    xorpd xmm1, xmm1
    ucomisd xmm0, xmm1
    jp .default_tol
    ja .tol_ready
.default_tol:
    movsd xmm0, [rel stroke_default_tol]
.tol_ready:
    movsd [r15 + K_TOL], xmm0
    movsd xmm0, [rdx + UgfxStroke_width]
    xorpd xmm1, xmm1
    ucomisd xmm0, xmm1
    jp .bad
    jbe .bad                            ; width must be > 0
    mulsd xmm0, [rel stroke_half]
    movsd [r15 + K_H], xmm0
    movsd xmm0, [rdx + UgfxStroke_miter_limit]
    maxsd xmm0, [rel stroke_one]        ; at least 1 (NaN -> 1)
    movsd [r15 + K_LIMIT], xmm0
    mov eax, [rdx + UgfxStroke_join]
    cmp eax, UGFX_JOIN_BEVEL
    ja .bad
    mov [r15 + K_JOIN], eax
    mov eax, [rdx + UgfxStroke_cap]
    cmp eax, UGFX_CAP_SQUARE
    ja .bad
    mov [r15 + K_CAP], eax
    mov rax, [r15 + K_SRC]
    cmp dword [rax + UgfxPath_error], 0
    jne .nomem
    ; point list and the right-side path
    mov rax, [r15 + K_DST]
    mov rdi, [rax + UgfxPath_arena]
    mov esi, STROKE_INITIAL_POINTS * 16
    call arena_alloc
    test rax, rax
    jz .nomem
    mov [r15 + K_PTS], rax
    mov dword [r15 + K_PTCAP], STROKE_INITIAL_POINTS
    lea rdi, [r15 + K_TMP]
    mov rax, [r15 + K_DST]
    mov rsi, [rax + UgfxPath_arena]
    call ugfx_path_init
    test rax, rax
    jnz .nomem
    ; walk the source verbs, collecting one flattened contour at a time
    mov dword [r15 + K_N], 0
    mov dword [r15 + K_CLOSED], 0
    mov dword [r15 + K_VERB], 0
    mov dword [r15 + K_POINT], 0
.verb:
    mov rbx, [r15 + K_SRC]
    mov eax, [r15 + K_VERB]
    cmp eax, [rbx + UgfxPath_verb_count]
    jae .verbs_done
    inc dword [r15 + K_VERB]
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
    jmp .bad
.v_move:
    call st_flush
    call st_take_point
    call st_append
    jmp .verb
.v_line:
    call st_take_point
    call st_append
    jmp .verb
.v_quad:
    mov dword [r15 + K_KIND], 2
    jmp .v_curve
.v_cubic:
    mov dword [r15 + K_KIND], 3
.v_curve:
    call st_flatten_curve
    jmp .verb
.v_close:
    mov dword [r15 + K_CLOSED], 1
    call st_flush
    jmp .verb
.verbs_done:
    call st_flush
    movsxd rax, dword [r15 + K_ERR]
    add rsp, K_SIZE
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
.bad:
    mov rax, -(EINVAL)
    add rsp, K_SIZE
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
.nomem:
    mov rax, -(ENOMEM)
    add rsp, K_SIZE
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15

; next source point -> xmm0/xmm1
st_take_point:
    mov rbx, [r15 + K_SRC]
    mov eax, [r15 + K_POINT]
    inc dword [r15 + K_POINT]
    shl rax, 4
    add rax, [rbx + UgfxPath_points]
    movsd xmm0, [rax]
    movsd xmm1, [rax + 8]
    ret

; flatten the quad/cubic (K_KIND control points follow the last point)
st_flatten_curve:
    mov rbx, [r15 + K_SRC]
    mov eax, [r15 + K_POINT]
    test eax, eax
    jz .fc_done                         ; curves always follow a point
    dec eax
    shl rax, 4
    add rax, [rbx + UgfxPath_points]
    mov ecx, [r15 + K_KIND]
    inc ecx
    shl ecx, 1                          ; doubles to copy
    xor edx, edx
.fc_copy:
    movsd xmm0, [rax + rdx * 8]
    movsd [r15 + K_CURVE + rdx * 8], xmm0
    inc edx
    cmp edx, ecx
    jb .fc_copy
    mov eax, [r15 + K_KIND]
    add [r15 + K_POINT], eax
    lea rdi, [r15 + K_CURVE]
    movsd xmm0, [r15 + K_TOL]
    cmp dword [r15 + K_KIND], 2
    jne .fc_cubic_n
    call umath_bezier_quad_segments
    jmp .fc_have_n
.fc_cubic_n:
    call umath_bezier_cubic_segments
.fc_have_n:
    mov [r15 + K_SEGN], rax
    mov qword [r15 + K_SEGI], 1
.fc_point:
    mov rax, [r15 + K_SEGI]
    cmp rax, [r15 + K_SEGN]
    ja .fc_done
    je .fc_end_point
    cvtsi2sd xmm0, rax
    cvtsi2sd xmm1, qword [r15 + K_SEGN]
    divsd xmm0, xmm1
    lea rdi, [r15 + K_CURVE]
    cmp dword [r15 + K_KIND], 2
    jne .fc_cubic_eval
    call umath_bezier_quad_eval
    jmp .fc_add
.fc_cubic_eval:
    call umath_bezier_cubic_eval
    jmp .fc_add
.fc_end_point:
    mov eax, [r15 + K_KIND]
    shl eax, 4
    movsd xmm0, [r15 + K_CURVE + rax]
    movsd xmm1, [r15 + K_CURVE + rax + 8]
.fc_add:
    call st_append
    inc qword [r15 + K_SEGI]
    jmp .fc_point
.fc_done:
    ret

; xmm0/xmm1 -> appended to the point list unless it repeats the last point
st_append:
    mov ecx, [r15 + K_N]
    test ecx, ecx
    jz .ap_store
    lea rax, [rcx - 1]
    shl rax, 4
    add rax, [r15 + K_PTS]
    movapd xmm2, xmm0
    subsd xmm2, [rax]
    movapd xmm3, xmm1
    subsd xmm3, [rax + 8]
    mulsd xmm2, xmm2
    mulsd xmm3, xmm3
    addsd xmm2, xmm3
    movsd xmm3, [rel stroke_eps]
    mulsd xmm3, xmm3
    ucomisd xmm2, xmm3
    jbe .ap_done                        ; repeated point (or NaN): skip
.ap_store:
    cmp ecx, [r15 + K_PTCAP]
    jb .ap_room
    sub rsp, 24
    movsd [rsp], xmm0
    movsd [rsp + 8], xmm1
    mov rax, [r15 + K_DST]
    mov rdi, [rax + UgfxPath_arena]
    mov esi, [r15 + K_PTCAP]
    shl rsi, 5                          ; twice the points, 16 bytes each
    call arena_alloc
    test rax, rax
    jz .ap_nomem
    mov rdi, rax
    mov rsi, [r15 + K_PTS]
    mov ecx, [r15 + K_N]
    shl rcx, 4
    rep movsb
    mov [r15 + K_PTS], rax
    shl dword [r15 + K_PTCAP], 1
    movsd xmm0, [rsp]
    movsd xmm1, [rsp + 8]
    add rsp, 24
    mov ecx, [r15 + K_N]
.ap_room:
    shl rcx, 4
    add rcx, [r15 + K_PTS]
    movsd [rcx], xmm0
    movsd [rcx + 8], xmm1
    inc dword [r15 + K_N]
.ap_done:
    ret
.ap_nomem:
    add rsp, 24
    mov dword [r15 + K_ERR], -(ENOMEM)
    ret

; -----------------------------------------------------------------------------
; st_flush — strokes the collected contour and starts an empty one
; -----------------------------------------------------------------------------
st_flush:
    cmp dword [r15 + K_ERR], 0
    jne .fl_reset
    mov eax, [r15 + K_N]
    test eax, eax
    jz .fl_reset
    ; a closed contour that returns to its start drops the repeat
    cmp dword [r15 + K_CLOSED], 0
    je .fl_ready
    cmp eax, 2
    jb .fl_ready
    mov rcx, [r15 + K_PTS]
    lea rdx, [rax - 1]
    shl rdx, 4
    movsd xmm0, [rcx + rdx]
    subsd xmm0, [rcx]
    movsd xmm1, [rcx + rdx + 8]
    subsd xmm1, [rcx + 8]
    mulsd xmm0, xmm0
    mulsd xmm1, xmm1
    addsd xmm0, xmm1
    movsd xmm1, [rel stroke_eps]
    mulsd xmm1, xmm1
    ucomisd xmm0, xmm1
    ja .fl_ready
    dec dword [r15 + K_N]
.fl_ready:
    cmp dword [r15 + K_N], 1
    je .fl_dot
    cmp dword [r15 + K_CLOSED], 0
    jne .fl_closed
    call st_stroke_open
    jmp .fl_reset
.fl_closed:
    call st_stroke_closed
    jmp .fl_reset
.fl_dot:
    call st_dot
.fl_reset:
    mov dword [r15 + K_N], 0
    mov dword [r15 + K_CLOSED], 0
    ret

; record the first error from a path call (eax)
%macro ST_CHECK 0
    test eax, eax
    jz %%ok
    cmp dword [r15 + K_ERR], 0
    jne %%ok
    mov [r15 + K_ERR], eax
%%ok:
%endmacro

; a lone point: a circle (round cap), a square (square cap) or nothing
st_dot:
    mov rax, [r15 + K_PTS]
    movsd xmm0, [rax]
    movsd xmm1, [rax + 8]
    cmp dword [r15 + K_CAP], UGFX_CAP_ROUND
    je .dot_round
    cmp dword [r15 + K_CAP], UGFX_CAP_SQUARE
    jne .dot_done
    subsd xmm0, [r15 + K_H]
    subsd xmm1, [r15 + K_H]
    movsd xmm2, [r15 + K_H]
    addsd xmm2, xmm2
    movapd xmm3, xmm2
    mov rdi, [r15 + K_DST]
    call ugfx_path_add_rect
    ST_CHECK
    ret
.dot_round:
    movsd xmm2, [r15 + K_H]
    mov rdi, [r15 + K_DST]
    call ugfx_path_add_circle
    ST_CHECK
.dot_done:
    ret

; -----------------------------------------------------------------------------
; Geometry helpers. Points are P[i mod n]. Segment i runs from P[i] to
; P[i + 1]; its direction d is unit length and its normal is (-dy, dx).
; -----------------------------------------------------------------------------

; ecx = index -> rax = &P[index mod n]
st_point_addr:
    mov eax, ecx
    xor edx, edx
    div dword [r15 + K_N]
    mov eax, edx
    shl rax, 4
    add rax, [r15 + K_PTS]
    ret

; ecx = segment -> xmm2/xmm3 = direction, xmm4/xmm5 = normal
st_segment:
    push rcx
    call st_point_addr
    movsd xmm2, [rax]
    movsd xmm3, [rax + 8]
    pop rcx
    inc ecx
    push rax
    call st_point_addr
    movsd xmm0, [rax]
    subsd xmm0, xmm2
    movsd xmm1, [rax + 8]
    subsd xmm1, xmm3
    pop rax
    sub rsp, 24
    movsd [rsp], xmm0
    movsd [rsp + 8], xmm1
    call umath_hypot_f64                ; length (> 0: repeats were dropped)
    movsd [r15 + K_SEGLEN], xmm0
    movsd xmm2, [rsp]
    movsd xmm3, [rsp + 8]
    add rsp, 24
    divsd xmm2, xmm0
    divsd xmm3, xmm0
    xorpd xmm4, xmm4
    subsd xmm4, xmm3                    ; nx = -dy
    movapd xmm5, xmm2                   ; ny = dx
    ret

; (K_PX, K_PY) + K_SIDE * K_H * (xmm0, xmm1) -> xmm0/xmm1
st_offset:
    movsd xmm2, [r15 + K_H]
    mulsd xmm2, [r15 + K_SIDE]
    mulsd xmm0, xmm2
    mulsd xmm1, xmm2
    addsd xmm0, [r15 + K_PX]
    addsd xmm1, [r15 + K_PY]
    ret

; target line_to (xmm0, xmm1)
st_line:
    mov rdi, [r15 + K_TARGET]
    call ugfx_path_line_to
    ST_CHECK
    ret

; target move_to (xmm0, xmm1)
st_move:
    mov rdi, [r15 + K_TARGET]
    call ugfx_path_move_to
    ST_CHECK
    ret

; arc around (K_PX, K_PY) of radius K_H from the direction (xmm0, xmm1)
; turning by xmm2 radians, appended as cubics to the target
st_arc:
    sub rsp, 24
    movsd [rsp], xmm2
    movapd xmm3, xmm0
    movapd xmm0, xmm1
    movapd xmm1, xmm3
    call umath_atan2_f64                ; start angle
    movapd xmm4, xmm0
    movsd xmm5, [rsp]
    add rsp, 24
    lea rdi, [r15 + K_ARCBUF]
    movsd xmm0, [r15 + K_PX]
    movsd xmm1, [r15 + K_PY]
    movsd xmm2, [r15 + K_H]
    movapd xmm3, xmm2
    call umath_arc_to_cubics
    mov [r15 + K_ARCN], rax
    mov qword [r15 + K_ARCI], 0
.arc_piece:
    mov rax, [r15 + K_ARCI]
    cmp rax, [r15 + K_ARCN]
    jae .arc_done
    imul rax, rax, 48
    lea rax, [r15 + K_ARCBUF + rax]
    movsd xmm0, [rax]
    movsd xmm1, [rax + 8]
    movsd xmm2, [rax + 16]
    movsd xmm3, [rax + 24]
    movsd xmm4, [rax + 32]
    movsd xmm5, [rax + 40]
    mov rdi, [r15 + K_TARGET]
    call ugfx_path_cubic_to
    ST_CHECK
    inc qword [r15 + K_ARCI]
    jmp .arc_piece
.arc_done:
    ret

; -----------------------------------------------------------------------------
; st_side — writes one offset side (K_SIDE) of the contour to K_TARGET:
;   open: from P[0] to P[n-1]; closed: a loop ending back at its start.
; -----------------------------------------------------------------------------
st_side:
    mov eax, [r15 + K_N]
    cmp dword [r15 + K_CLOSED], 0
    jne .side_segs
    dec eax
.side_segs:
    mov [r15 + K_SEGS], eax
    ; start: P[0] + s h n0
    xor ecx, ecx
    call st_segment
    movsd [r15 + K_NCX], xmm4
    movsd [r15 + K_NCY], xmm5
    movsd [r15 + K_DCX], xmm2
    movsd [r15 + K_DCY], xmm3
    movsd xmm0, [r15 + K_SEGLEN]
    movsd [r15 + K_LC], xmm0
    mov rax, [r15 + K_PTS]
    movsd xmm0, [rax]
    movsd xmm1, [rax + 8]
    movsd [r15 + K_PX], xmm0
    movsd [r15 + K_PY], xmm1
    movapd xmm0, xmm4
    movapd xmm1, xmm5
    call st_offset
    call st_move
    mov dword [r15 + K_I], 1
.side_vertex:
    mov eax, [r15 + K_I]
    cmp eax, [r15 + K_SEGS]
    jb .side_join
    cmp dword [r15 + K_CLOSED], 0
    je .side_end
    cmp eax, [r15 + K_SEGS]
    ja .side_done                       ; closed: joined at P[0] already
.side_join:
    ; vertex P[i] between segments i-1 and i (mod n)
    movsd xmm0, [r15 + K_NCX]
    movsd [r15 + K_NPX], xmm0
    movsd xmm0, [r15 + K_NCY]
    movsd [r15 + K_NPY], xmm0
    movsd xmm0, [r15 + K_DCX]
    movsd [r15 + K_DPX], xmm0
    movsd xmm0, [r15 + K_DCY]
    movsd [r15 + K_DPY], xmm0
    movsd xmm0, [r15 + K_LC]
    movsd [r15 + K_LP], xmm0
    mov ecx, [r15 + K_I]
    call st_segment
    movsd xmm0, [r15 + K_SEGLEN]
    movsd [r15 + K_LC], xmm0
    movsd [r15 + K_NCX], xmm4
    movsd [r15 + K_NCY], xmm5
    movsd [r15 + K_DCX], xmm2
    movsd [r15 + K_DCY], xmm3
    mov ecx, [r15 + K_I]
    call st_point_addr
    movsd xmm0, [rax]
    movsd xmm1, [rax + 8]
    movsd [r15 + K_PX], xmm0
    movsd [r15 + K_PY], xmm1
    call st_join
    inc dword [r15 + K_I]
    jmp .side_vertex
.side_end:
    ; open: the last segment ends at P[n-1] + s h n_last
    mov ecx, [r15 + K_SEGS]
    call st_point_addr
    movsd xmm0, [rax]
    movsd xmm1, [rax + 8]
    movsd [r15 + K_PX], xmm0
    movsd [r15 + K_PY], xmm1
    movsd xmm0, [r15 + K_NCX]
    movsd xmm1, [r15 + K_NCY]
    call st_offset
    call st_line
.side_done:
    ret

; join at (K_PX, K_PY) from normal NP to normal NC on side K_SIDE
st_join:
    ; the previous segment's offset end
    movsd xmm0, [r15 + K_NPX]
    movsd xmm1, [r15 + K_NPY]
    call st_offset
    call st_line
    ; cross = dp x dc, dot = np . nc
    movsd xmm6, [r15 + K_DPX]
    mulsd xmm6, [r15 + K_DCY]
    movsd xmm7, [r15 + K_DPY]
    mulsd xmm7, [r15 + K_DCX]
    subsd xmm6, xmm7                    ; cross
    movsd xmm7, [r15 + K_NPX]
    mulsd xmm7, [r15 + K_NCX]
    movsd xmm8, [r15 + K_NPY]
    mulsd xmm8, [r15 + K_NCY]
    addsd xmm7, xmm8                    ; dot
    movapd xmm8, xmm6
    andpd xmm8, [rel stroke_abs_mask]
    ucomisd xmm8, [rel stroke_cross_eps]
    ja .join_turn
    ; (nearly) straight on: nothing to add; a reversal is an outer turn
    ucomisd xmm7, [rel stroke_zero]
    ja .join_finish
    jmp .join_outer_reverse
.join_turn:
    ; the side is outer when side * cross < 0
    movapd xmm8, xmm6
    mulsd xmm8, [r15 + K_SIDE]
    ucomisd xmm8, [rel stroke_zero]
    jb .join_outer
    ; inner side: where the two inner offset lines meet, P + s h (np + nc) /
    ; (1 + dot), if that lies within the near half of both segments (its
    ; distance along them, h tan(theta / 2), at most half the shorter
    ; length, so the joins at a segment's two ends cannot cross; compared
    ; squared: h^2 (1 - dot) <= (L / 2)^2 (1 + dot)). The outline then has
    ; no overlap. Otherwise (short segments) go through the vertex.
    movsd xmm9, [r15 + K_LP]
    minsd xmm9, [r15 + K_LC]
    mulsd xmm9, [rel stroke_half]
    mulsd xmm9, xmm9
    movapd xmm10, xmm7
    addsd xmm10, [rel stroke_one]       ; 1 + dot
    mulsd xmm9, xmm10
    movsd xmm11, [rel stroke_one]
    subsd xmm11, xmm7                   ; 1 - dot
    movsd xmm12, [r15 + K_H]
    mulsd xmm12, xmm12
    mulsd xmm11, xmm12
    ucomisd xmm11, xmm9
    ja .join_pivot
    movsd xmm0, [r15 + K_NPX]
    addsd xmm0, [r15 + K_NCX]
    movsd xmm1, [r15 + K_NPY]
    addsd xmm1, [r15 + K_NCY]
    divsd xmm0, xmm10
    divsd xmm1, xmm10
    call st_offset
    jmp st_line                         ; ends the join: both sides meet here
.join_pivot:
    movsd xmm0, [r15 + K_PX]
    movsd xmm1, [r15 + K_PY]
    call st_line
    jmp .join_finish
.join_outer:
    mov eax, [r15 + K_JOIN]
    cmp eax, UGFX_JOIN_ROUND
    je .join_round
    cmp eax, UGFX_JOIN_BEVEL
    je .join_finish
    ; miter: length ratio 1 / sqrt((1 + dot) / 2) against the limit,
    ; compared squared: (1 + dot) / 2 * limit^2 >= 1
    movapd xmm8, xmm7
    addsd xmm8, [rel stroke_one]        ; 1 + dot
    movapd xmm9, xmm8
    mulsd xmm9, [rel stroke_half]
    movsd xmm10, [r15 + K_LIMIT]
    mulsd xmm10, xmm10
    mulsd xmm9, xmm10
    ucomisd xmm9, [rel stroke_one]
    jb .join_finish                     ; too long: bevel
    ; miter point: P + s h (np + nc) / (1 + dot)
    movsd xmm0, [r15 + K_NPX]
    addsd xmm0, [r15 + K_NCX]
    movsd xmm1, [r15 + K_NPY]
    addsd xmm1, [r15 + K_NCY]
    divsd xmm0, xmm8
    divsd xmm1, xmm8
    call st_offset
    call st_line
    jmp .join_finish
.join_round:
    ; sweep = atan2(np x nc, np . nc), from side * np
    movsd xmm0, [r15 + K_NPX]
    mulsd xmm0, [r15 + K_NCY]
    movsd xmm1, [r15 + K_NPY]
    mulsd xmm1, [r15 + K_NCX]
    subsd xmm0, xmm1                    ; np x nc
    movapd xmm1, xmm7                   ; np . nc
    call umath_atan2_f64
    movapd xmm2, xmm0
    jmp .join_round_arc
.join_outer_reverse:
    cmp dword [r15 + K_JOIN], UGFX_JOIN_ROUND
    jne .join_finish                    ; miter and bevel: straight across
    movsd xmm2, [rel stroke_pi]
    mulsd xmm2, [r15 + K_SIDE]
    xorpd xmm3, xmm3
    subsd xmm3, xmm2
    movapd xmm2, xmm3                   ; -side * pi, around the outside
.join_round_arc:
    movsd xmm0, [r15 + K_NPX]
    mulsd xmm0, [r15 + K_SIDE]
    movsd xmm1, [r15 + K_NPY]
    mulsd xmm1, [r15 + K_SIDE]
    call st_arc
.join_finish:
    ; the current segment's offset start
    movsd xmm0, [r15 + K_NCX]
    movsd xmm1, [r15 + K_NCY]
    call st_offset
    jmp st_line

; cap at (K_PX, K_PY): from +s h n to -s h n around direction d = (xmm6, xmm7)
; with normal (xmm4, xmm5) and side s = K_SIDE (the current point is the
; +side offset)
%define K_CAPD 0                        ; (scratch on the caller's stack)
st_cap:
    sub rsp, 40
    movsd [rsp], xmm4
    movsd [rsp + 8], xmm5
    movsd [rsp + 16], xmm6
    movsd [rsp + 24], xmm7
    mov eax, [r15 + K_CAP]
    cmp eax, UGFX_CAP_ROUND
    je .cap_round
    cmp eax, UGFX_CAP_SQUARE
    je .cap_square
    ; butt: straight across
    movsd xmm0, [rsp]
    movsd xmm1, [rsp + 8]
    mulsd xmm0, [rel stroke_neg_one]
    mulsd xmm1, [rel stroke_neg_one]
    call st_offset
    call st_line
    add rsp, 40
    ret
.cap_square:
    ; P + s h n + h d, P - s h n + h d, P - s h n
    movsd xmm0, [rsp + 16]
    mulsd xmm0, [r15 + K_SIDE]
    addsd xmm0, [rsp]
    movsd xmm1, [rsp + 24]
    mulsd xmm1, [r15 + K_SIDE]
    addsd xmm1, [rsp + 8]
    call st_offset
    call st_line
    movsd xmm0, [rsp + 16]
    mulsd xmm0, [r15 + K_SIDE]
    subsd xmm0, [rsp]
    movsd xmm1, [rsp + 24]
    mulsd xmm1, [r15 + K_SIDE]
    subsd xmm1, [rsp + 8]
    call st_offset
    call st_line
    movsd xmm0, [rsp]
    movsd xmm1, [rsp + 8]
    mulsd xmm0, [rel stroke_neg_one]
    mulsd xmm1, [rel stroke_neg_one]
    call st_offset
    call st_line
    add rsp, 40
    ret
.cap_round:
    ; half turn from s n through d: sweep = -s pi
    movsd xmm2, [rel stroke_pi]
    mulsd xmm2, [r15 + K_SIDE]
    xorpd xmm3, xmm3
    subsd xmm3, xmm2
    movapd xmm2, xmm3
    movsd xmm0, [rsp]
    mulsd xmm0, [r15 + K_SIDE]
    movsd xmm1, [rsp + 8]
    mulsd xmm1, [r15 + K_SIDE]
    call st_arc
    add rsp, 40
    ret

; -----------------------------------------------------------------------------
; st_append_reversed — appends the single contour in K_TMP to K_TARGET in
;   reverse; eax = 1 continues the open contour, 0 starts a new one.
; -----------------------------------------------------------------------------
st_append_reversed:
    push r12
    push r13
    push r14
    lea r12, [r15 + K_TMP]
    mov r13d, [r12 + UgfxPath_point_count]
    test r13d, r13d
    jz .rev_done
    dec r13d                            ; index of the last point
    push rax
    mov eax, r13d
    shl rax, 4
    add rax, [r12 + UgfxPath_points]
    movsd xmm0, [rax]
    movsd xmm1, [rax + 8]
    pop rax
    test eax, eax
    jz .rev_move
    call st_line
    jmp .rev_started
.rev_move:
    call st_move
.rev_started:
    mov r14d, [r12 + UgfxPath_verb_count]
.rev_verb:
    test r14d, r14d
    jz .rev_done
    dec r14d
    mov rax, [r12 + UgfxPath_verbs]
    movzx eax, byte [rax + r14]
    cmp eax, PATH_VERB_LINE
    je .rev_line
    cmp eax, PATH_VERB_CUBIC
    je .rev_cubic
    jmp .rev_verb                       ; MOVE / CLOSE carry no segment
.rev_line:
    dec r13d
    mov eax, r13d
    shl rax, 4
    add rax, [r12 + UgfxPath_points]
    movsd xmm0, [rax]
    movsd xmm1, [rax + 8]
    call st_line
    jmp .rev_verb
.rev_cubic:
    ; points: [r13 - 3] start, [r13 - 2] c1, [r13 - 1] c2, [r13] end
    mov eax, r13d
    shl rax, 4
    add rax, [r12 + UgfxPath_points]
    movsd xmm0, [rax - 16]              ; c2
    movsd xmm1, [rax - 8]
    movsd xmm2, [rax - 32]              ; c1
    movsd xmm3, [rax - 24]
    movsd xmm4, [rax - 48]              ; start
    movsd xmm5, [rax - 40]
    mov rdi, [r15 + K_TARGET]
    call ugfx_path_cubic_to
    ST_CHECK
    sub r13d, 3
    jmp .rev_verb
.rev_done:
    pop r14
    pop r13
    pop r12
    ret

; the right side (side -1) into K_TMP
st_right_side:
    lea rdi, [r15 + K_TMP]
    call ugfx_path_reset
    lea rax, [r15 + K_TMP]
    mov [r15 + K_TARGET], rax
    movsd xmm0, [rel stroke_neg_one]
    movsd [r15 + K_SIDE], xmm0
    call st_side
    lea rax, [r15 + K_TMP]
    cmp dword [rax + UgfxPath_error], 0
    je .right_ok
    mov dword [r15 + K_ERR], -(ENOMEM)
.right_ok:
    ret

; -----------------------------------------------------------------------------
; open contour: left side, end cap, right side reversed, start cap, close
; -----------------------------------------------------------------------------
st_stroke_open:
    mov rax, [r15 + K_DST]
    mov [r15 + K_TARGET], rax
    movsd xmm0, [rel stroke_one]
    movsd [r15 + K_SIDE], xmm0
    call st_side                        ; leaves NC/DC = last segment, P = end
    ; end cap: side +1, from n through d
    movsd xmm4, [r15 + K_NCX]
    movsd xmm5, [r15 + K_NCY]
    movsd xmm6, [r15 + K_DCX]
    movsd xmm7, [r15 + K_DCY]
    call st_cap
    call st_right_side
    mov rax, [r15 + K_DST]
    mov [r15 + K_TARGET], rax
    mov eax, 1
    call st_append_reversed
    ; start cap at P[0]: the end cap of the reversed contour, whose direction
    ; is -d0 and whose left normal is -n0; the current point P0 - h n0 is its
    ; +side offset, and the cap ends at P0 + h n0
    xor ecx, ecx
    call st_segment
    xorpd xmm6, xmm6
    subsd xmm6, xmm2                    ; -d0
    xorpd xmm7, xmm7
    subsd xmm7, xmm3
    xorpd xmm0, xmm0
    subsd xmm0, xmm4                    ; -n0
    movapd xmm4, xmm0
    xorpd xmm0, xmm0
    subsd xmm0, xmm5
    movapd xmm5, xmm0
    mov rax, [r15 + K_PTS]
    movsd xmm0, [rax]
    movsd xmm1, [rax + 8]
    movsd [r15 + K_PX], xmm0
    movsd [r15 + K_PY], xmm1
    movsd xmm0, [rel stroke_one]
    movsd [r15 + K_SIDE], xmm0
    call st_cap
    mov rdi, [r15 + K_DST]
    call ugfx_path_close
    ST_CHECK
    ret

; -----------------------------------------------------------------------------
; closed contour: the left loop, and the right loop reversed (a ring)
; -----------------------------------------------------------------------------
st_stroke_closed:
    mov rax, [r15 + K_DST]
    mov [r15 + K_TARGET], rax
    movsd xmm0, [rel stroke_one]
    movsd [r15 + K_SIDE], xmm0
    call st_side
    mov rdi, [r15 + K_DST]
    call ugfx_path_close
    ST_CHECK
    call st_right_side
    mov rax, [r15 + K_DST]
    mov [r15 + K_TARGET], rax
    xor eax, eax
    call st_append_reversed
    mov rdi, [r15 + K_DST]
    call ugfx_path_close
    ST_CHECK
    ret

section .rodata
align 16
stroke_abs_mask:    dq 0x7FFFFFFFFFFFFFFF, 0x7FFFFFFFFFFFFFFF

section .data
global ugfx_stroke_version
ugfx_stroke_version: dq 0x010000
