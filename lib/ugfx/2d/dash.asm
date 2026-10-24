; =============================================================================
; Utkarsha OS — lib/ugfx/2d/dash.asm
; =============================================================================
; Dashing: cuts the contours of a path into the "on" runs of a dash pattern,
; appended to another path as open polylines - stroke them with
; ugfx_path_stroke for the dashed outline.
;
;   ugfx_path_dash(dst, src, dash, tolerance)
;
; The source is flattened first (ugfx_path_flatten), so dashes follow
; curves by arc length. Each contour restarts the pattern at the dash
; offset. A dash that crosses a vertex keeps the vertex, so the stroke gets
; a proper join there; a zero-length dash is a single point, which the
; stroker draws as a dot with round or square caps.
;
; Closed contours: the pattern runs once around, including the closing
; segment. If the contour starts inside a dash, that first run is held
; back and drawn at the end as the continuation of the last dash (or on
; its own if the pattern is off when the walk returns to the start), so
; the start point gets a join rather than two caps. A closed contour that
; lies entirely inside one dash is copied as a closed contour.
; =============================================================================

%include "ugfx.inc"

extern ugfx_path_init
extern ugfx_path_move_to
extern ugfx_path_line_to
extern ugfx_path_close
extern ugfx_path_flatten
extern umath_hypot_f64
extern umath_fmod_f64

; frame (r15)
%define D_DST       0
%define D_SRC       8
%define D_DASH      16
%define D_TOL       24
%define D_INT       32                  ; const f64* intervals
%define D_N         40                  ; u32 intervals
%define D_P         44                  ; u32 intervals in one period (n, or 2n if n is odd)
%define D_K0        48                  ; u32 interval at each contour start
%define D_K         52                  ; u32 current interval (even = on)
%define D_REM0      56                  ; f64 length left in interval K0 at the start
%define D_REM       64                  ; f64 length left in interval K
%define D_TOTAL     72                  ; f64 period length
%define D_FLAT      80                  ; UgfxPath, the flattened source
%define D_VERB      136                 ; u32
%define D_PT        140                 ; u32
%define D_C0        144                 ; u32 contour's first point
%define D_CN        148                 ; u32 contour's points
%define D_CLOSED    152                 ; u32
%define D_SKIP      156                 ; u32 first run held back
%define D_I         160                 ; u32
%define D_SEGS      164                 ; u32
%define D_SEG       168                 ; u32
%define D_ERR       172                 ; i32 first error
%define D_AX        176                 ; current segment A -> B, length L
%define D_AY        184
%define D_BX        192
%define D_BY        200
%define D_L         208
%define D_S         216                 ; distance walked along the segment
%define D_SIZE      232

section .rodata
align 16
dash_abs_mask:      dq 0x7FFFFFFFFFFFFFFF, 0x7FFFFFFFFFFFFFFF
dash_max:           dq 0x7FEFFFFFFFFFFFFF   ; largest finite double

section .text

; -----------------------------------------------------------------------------
; ugfx_path_dash — rdi = destination UgfxPath*, rsi = source UgfxPath*,
;   rdx = const UgfxDash*, xmm0 = flattening tolerance in path units
;   (<= 0 or NaN: UGFX_PATH_TOLERANCE)
;   -> rax = 0, -EINVAL (bad pattern or arguments), -ENOMEM.
;   Appends to dst; dst must not be src.
; -----------------------------------------------------------------------------
global ugfx_path_dash
ugfx_path_dash:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, D_SIZE
    mov r15, rsp
    test rdi, rdi
    jz .bad
    test rsi, rsi
    jz .bad
    test rdx, rdx
    jz .bad
    cmp rdi, rsi
    je .bad
    mov [r15 + D_DST], rdi
    mov [r15 + D_SRC], rsi
    mov [r15 + D_DASH], rdx
    movsd [r15 + D_TOL], xmm0
    mov dword [r15 + D_ERR], 0
    ; the pattern: count >= 1, every interval finite and >= 0, sum > 0
    mov rbx, rdx
    mov eax, [rbx + UgfxDash_count]
    test eax, eax
    jz .bad
    mov [r15 + D_N], eax
    mov rcx, [rbx + UgfxDash_intervals]
    test rcx, rcx
    jz .bad
    mov [r15 + D_INT], rcx
    xorpd xmm2, xmm2
    xor edx, edx
.sum:
    movsd xmm0, [rcx + rdx * 8]
    xorpd xmm1, xmm1
    ucomisd xmm0, xmm1
    jp .bad
    jb .bad
    ucomisd xmm0, [rel dash_max]
    ja .bad
    addsd xmm2, xmm0
    inc edx
    cmp edx, eax
    jb .sum
    xorpd xmm1, xmm1
    ucomisd xmm2, xmm1
    jbe .bad
    ucomisd xmm2, [rel dash_max]
    ja .bad
    mov ecx, eax
    test eax, 1
    jz .period
    addsd xmm2, xmm2                    ; an odd list repeats
    add ecx, ecx
.period:
    mov [r15 + D_P], ecx
    movsd [r15 + D_TOTAL], xmm2
    ; phase = offset mod period, in [0, period)
    movsd xmm0, [rbx + UgfxDash_offset]
    movapd xmm3, xmm0
    andpd xmm3, [rel dash_abs_mask]
    ucomisd xmm3, [rel dash_max]
    jp .bad
    ja .bad
    movapd xmm1, xmm2
    call umath_fmod_f64
    xorpd xmm1, xmm1
    ucomisd xmm0, xmm1
    jae .phase_pos
    addsd xmm0, [r15 + D_TOTAL]
.phase_pos:
    ucomisd xmm0, [r15 + D_TOTAL]
    jb .phase_ok
    xorpd xmm0, xmm0                    ; rounded up to the period
.phase_ok:
    xor ecx, ecx
.find:
    call ds_len
    ucomisd xmm0, xmm1
    jb .found
    subsd xmm0, xmm1
    inc ecx
    cmp ecx, [r15 + D_P]
    jb .find
    xor ecx, ecx                        ; rounding ran past the end
    xorpd xmm0, xmm0
    call ds_len
.found:
    mov [r15 + D_K0], ecx
    subsd xmm1, xmm0
    movsd [r15 + D_REM0], xmm1
    ; flatten the source
    lea rdi, [r15 + D_FLAT]
    mov rax, [r15 + D_DST]
    mov rsi, [rax + UgfxPath_arena]
    call ugfx_path_init
    test rax, rax
    jnz .out
    lea rdi, [r15 + D_FLAT]
    mov rsi, [r15 + D_SRC]
    movsd xmm0, [r15 + D_TOL]
    call ugfx_path_flatten
    test rax, rax
    jnz .out
    ; one contour at a time
    mov dword [r15 + D_VERB], 0
    mov dword [r15 + D_PT], 0
    mov dword [r15 + D_CN], 0
    mov dword [r15 + D_CLOSED], 0
.verb:
    mov eax, [r15 + D_VERB]
    cmp eax, [r15 + D_FLAT + UgfxPath_verb_count]
    jae .verbs_done
    inc dword [r15 + D_VERB]
    mov rdx, [r15 + D_FLAT + UgfxPath_verbs]
    movzx eax, byte [rdx + rax]
    cmp eax, PATH_VERB_MOVE
    je .v_move
    cmp eax, PATH_VERB_CLOSE
    je .v_close
    inc dword [r15 + D_CN]              ; a line (flattened paths have no curves)
    inc dword [r15 + D_PT]
    jmp .verb
.v_move:
    call ds_contour
    mov eax, [r15 + D_PT]
    mov [r15 + D_C0], eax
    mov dword [r15 + D_CN], 1
    inc dword [r15 + D_PT]
    jmp .verb
.v_close:
    mov dword [r15 + D_CLOSED], 1
    call ds_contour
    jmp .verb
.verbs_done:
    call ds_contour
    movsxd rax, dword [r15 + D_ERR]
.out:
    add rsp, D_SIZE
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
.bad:
    mov rax, -(EINVAL)
    jmp .out

; ecx = interval index (< D_P) -> xmm1 = its length. Clobbers eax, rdx.
ds_len:
    mov eax, ecx
    cmp eax, [r15 + D_N]
    jb .len_index
    sub eax, [r15 + D_N]
.len_index:
    mov rdx, [r15 + D_INT]
    movsd xmm1, [rdx + rax * 8]
    ret

; eax = point index in the contour -> xmm0/xmm1
ds_point:
    add eax, [r15 + D_C0]
    shl rax, 4
    add rax, [r15 + D_FLAT + UgfxPath_points]
    movsd xmm0, [rax]
    movsd xmm1, [rax + 8]
    ret

; xmm2 = t -> xmm0/xmm1 = A + (B - A) t
ds_lerp:
    movsd xmm0, [r15 + D_BX]
    subsd xmm0, [r15 + D_AX]
    mulsd xmm0, xmm2
    addsd xmm0, [r15 + D_AX]
    movsd xmm1, [r15 + D_BY]
    subsd xmm1, [r15 + D_AY]
    mulsd xmm1, xmm2
    addsd xmm1, [r15 + D_AY]
    ret

; ecx = segment index -> D_AX..D_L (the last segment of a closed contour
;   returns to point 0)
ds_load_seg:
    push rbx
    mov [r15 + D_SEG], ecx
    mov eax, ecx
    call ds_point
    movsd [r15 + D_AX], xmm0
    movsd [r15 + D_AY], xmm1
    mov eax, [r15 + D_SEG]
    inc eax
    cmp eax, [r15 + D_CN]
    jb .seg_b
    xor eax, eax
.seg_b:
    call ds_point
    movsd [r15 + D_BX], xmm0
    movsd [r15 + D_BY], xmm1
    subsd xmm0, [r15 + D_AX]
    subsd xmm1, [r15 + D_AY]
    call umath_hypot_f64
    movsd [r15 + D_L], xmm0
    pop rbx
    ret

; xmm0/xmm1 -> dst.move_to / dst.line_to, the first error kept
ds_move:
    push rbx
    cmp dword [r15 + D_ERR], 0
    jne ds_emit_done
    mov rdi, [r15 + D_DST]
    call ugfx_path_move_to
    jmp ds_emitted
ds_line:
    push rbx
    cmp dword [r15 + D_ERR], 0
    jne ds_emit_done
    mov rdi, [r15 + D_DST]
    call ugfx_path_line_to
ds_emitted:
    test eax, eax
    jz ds_emit_done
    mov [r15 + D_ERR], eax
ds_emit_done:
    pop rbx
    ret

; the walk reached the end of interval K at xmm0/xmm1: end or start a dash
ds_toggle:
    push rbx
    test byte [r15 + D_K], 1
    jnz .t_start
    cmp dword [r15 + D_SKIP], 0
    je .t_end
    mov dword [r15 + D_SKIP], 0         ; the held-back first run is over
    jmp .t_next
.t_end:
    call ds_line
    jmp .t_next
.t_start:
    call ds_move
.t_next:
    mov ecx, [r15 + D_K]
    inc ecx
    cmp ecx, [r15 + D_P]
    jb .t_k
    xor ecx, ecx
.t_k:
    mov [r15 + D_K], ecx
    call ds_len
    movsd [r15 + D_REM], xmm1
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ds_contour — dashes the collected contour (D_C0, D_CN, D_CLOSED) into dst
;   and starts an empty one
; -----------------------------------------------------------------------------
ds_contour:
    push rbx
    cmp dword [r15 + D_ERR], 0
    jne .reset
    mov eax, [r15 + D_CN]
    cmp eax, 2
    jb .reset                           ; a lone point has no length
    lea ecx, [rax - 1]
    cmp dword [r15 + D_CLOSED], 0
    je .have_segs
    inc ecx
.have_segs:
    mov [r15 + D_SEGS], ecx
    mov ecx, [r15 + D_K0]
    mov [r15 + D_K], ecx
    movsd xmm0, [r15 + D_REM0]
    movsd [r15 + D_REM], xmm0
    ; a closed contour starting inside a dash holds that run back
    xor eax, eax
    test ecx, 1
    jnz .skip_set
    cmp dword [r15 + D_CLOSED], 0
    je .skip_set
    mov eax, 1
.skip_set:
    mov [r15 + D_SKIP], eax
    test ecx, 1
    jnz .walk
    test eax, eax
    jnz .walk
    xor eax, eax
    call ds_point
    call ds_move
.walk:
    mov dword [r15 + D_I], 0
.seg:
    mov ecx, [r15 + D_I]
    cmp ecx, [r15 + D_SEGS]
    jae .segs_done
    call ds_load_seg
    xorpd xmm0, xmm0
    movsd [r15 + D_S], xmm0
.inner:
    movsd xmm0, [r15 + D_L]
    subsd xmm0, [r15 + D_S]             ; left on this segment
    ucomisd xmm0, [r15 + D_REM]
    jbe .seg_end                        ; the interval outlasts the segment
    movsd xmm2, [r15 + D_S]
    addsd xmm2, [r15 + D_REM]
    movsd [r15 + D_S], xmm2
    divsd xmm2, [r15 + D_L]
    call ds_lerp
    call ds_toggle
    jmp .inner
.seg_end:
    movsd xmm1, [r15 + D_REM]
    subsd xmm1, xmm0
    movsd [r15 + D_REM], xmm1
    test byte [r15 + D_K], 1
    jnz .seg_next
    cmp dword [r15 + D_SKIP], 0
    jne .seg_next
    movsd xmm0, [r15 + D_BX]
    movsd xmm1, [r15 + D_BY]
    call ds_line
.seg_next:
    inc dword [r15 + D_I]
    jmp .seg
.segs_done:
    cmp dword [r15 + D_CLOSED], 0
    je .reset
    test byte [r15 + D_K0], 1
    jnz .reset                          ; started off: nothing held back
    cmp dword [r15 + D_SKIP], 0
    jne .whole
    ; the held-back first run: on from point 0 for REM0, continuing the
    ; last dash if the walk ended on
    test byte [r15 + D_K], 1
    jz .rest
    xor eax, eax
    call ds_point
    call ds_move
.rest:
    movsd xmm0, [r15 + D_REM0]
    movsd [r15 + D_REM], xmm0
    mov dword [r15 + D_I], 0
.rest_seg:
    mov ecx, [r15 + D_I]
    cmp ecx, [r15 + D_SEGS]
    jae .reset
    call ds_load_seg
    movsd xmm0, [r15 + D_L]
    ucomisd xmm0, [r15 + D_REM]
    jae .rest_last
    movsd xmm1, [r15 + D_REM]
    subsd xmm1, xmm0
    movsd [r15 + D_REM], xmm1
    movsd xmm0, [r15 + D_BX]
    movsd xmm1, [r15 + D_BY]
    call ds_line
    inc dword [r15 + D_I]
    jmp .rest_seg
.rest_last:
    xorpd xmm2, xmm2
    xorpd xmm1, xmm1
    ucomisd xmm0, xmm1
    jbe .rest_point                     ; zero-length segment: t = 0
    movsd xmm2, [r15 + D_REM]
    divsd xmm2, xmm0
.rest_point:
    call ds_lerp
    call ds_line
    jmp .reset
.whole:
    ; the whole contour lies inside the first dash: copy it closed
    xor eax, eax
    call ds_point
    call ds_move
    mov dword [r15 + D_I], 1
.whole_point:
    mov eax, [r15 + D_I]
    cmp eax, [r15 + D_CN]
    jae .whole_close
    call ds_point
    call ds_line
    inc dword [r15 + D_I]
    jmp .whole_point
.whole_close:
    cmp dword [r15 + D_ERR], 0
    jne .reset
    mov rdi, [r15 + D_DST]
    call ugfx_path_close
    test eax, eax
    jz .reset
    mov [r15 + D_ERR], eax
.reset:
    mov dword [r15 + D_CN], 0
    mov dword [r15 + D_CLOSED], 0
    pop rbx
    ret

global ugfx_dash_version
ugfx_dash_version:
    mov eax, 1
    ret
