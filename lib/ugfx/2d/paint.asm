; =============================================================================
; Utkarsha OS — lib/ugfx/2d/paint.asm
; =============================================================================
; Paints: what ugfx_raster_fill_paint puts under the coverage.
;
;   ugfx_paint_solid(paint, colour)
;   ugfx_paint_linear(paint, arena, stops, n, spread, x0, y0, x1, y1)
;   ugfx_paint_radial(paint, arena, stops, n, spread, cx, cy, r)
;   ugfx_paint_conic(paint, arena, stops, n, cx, cy, start_angle)
;   ugfx_paint_set_transform(paint, m)      paint space -> device space
;
; Gradients map each pixel centre, taken back to paint space through the
; inverse transform, to a position t:
;   linear  t = (p - p0) . (p1 - p0) / |p1 - p0|^2
;   radial  t = |p - c| / r
;   conic   t = angle of p around c (clockwise on screen, y down), in turns
;           from start_angle, in [0, 1)
; then spread: pad clamps t to [0, 1], repeat takes its fraction, reflect
; folds it back every other period. The colour comes from a 1024-entry
; table (UGFX_GRADIENT_LUT) built from the stops: positions are clamped to
; [0, 1] and to at least the previous stop (equal positions make a hard
; edge), colours are interpolated premultiplied (CSS Images 4, no dark
; fringes towards transparent stops), and before the first and after the
; last stop the end colours continue.
;
; Geometry (UgfxPaint_geom): linear x0, y0, kx, ky with k = d / |d|^2;
; radial cx, cy, 1 / r; conic cx, cy, start_angle / 2pi.
; =============================================================================

%include "ugfx.inc"

extern arena_alloc
extern ugfx_span_fill_solid
extern ugfx_span_blend_colors
extern umath_affine2_identity
extern umath_affine2_invert
extern umath_atan2_f64
extern umath_floor_f64_fractional

%define PAINT_CHUNK 64                  ; pixels coloured per ugfx_span_blend_colors

section .rodata
align 8
paint_zero:         dq 0.0
paint_half:         dq 0.5
paint_one:          dq 1.0
paint_two:          dq 2.0
paint_lut_last:     dq 1023.0           ; UGFX_GRADIENT_LUT - 1
paint_inv_255:      dq 0x3F70101010101010   ; 1 / 255
paint_inv_2pi:      dq 0x3FC45F306DC9C883   ; 1 / (2 pi)
paint_max:          dq 0x7FEFFFFFFFFFFFFF   ; largest finite double

section .text

; -----------------------------------------------------------------------------
; ugfx_paint_solid — rdi = UgfxPaint*, esi = colour (premultiplied BGRA)
;   -> rax = 0, -EINVAL
; -----------------------------------------------------------------------------
global ugfx_paint_solid
ugfx_paint_solid:
    test rdi, rdi
    jz .solid_bad
    lea rax, [rel pt_span_solid]
    mov [rdi + UgfxPaint_span], rax
    mov dword [rdi + UgfxPaint_type], UGFX_PAINT_SOLID
    mov dword [rdi + UgfxPaint_spread], UGFX_SPREAD_PAD
    mov [rdi + UgfxPaint_color], esi
    mov qword [rdi + UgfxPaint_lut], 0
    push rdi
    lea rdi, [rdi + UgfxPaint_inverse]
    call umath_affine2_identity
    pop rdi
    xor eax, eax
    ret
.solid_bad:
    mov rax, -(EINVAL)
    ret

; -----------------------------------------------------------------------------
; ugfx_paint_linear — rdi = UgfxPaint*, rsi = arena, rdx = const UgfxStop*,
;   ecx = stop count (>= 1), r8d = UGFX_SPREAD_*, xmm0..xmm3 = x0, y0, x1, y1
;   -> rax = 0, -EINVAL (bad stops, spread or p0 = p1), -ENOMEM
; -----------------------------------------------------------------------------
global ugfx_paint_linear
ugfx_paint_linear:
    ; k = d / |d|^2, d = p1 - p0
    subsd xmm2, xmm0
    subsd xmm3, xmm1
    movapd xmm4, xmm2
    mulsd xmm4, xmm2
    movapd xmm5, xmm3
    mulsd xmm5, xmm3
    addsd xmm4, xmm5
    xorpd xmm5, xmm5
    ucomisd xmm4, xmm5
    jp pt_bad
    je pt_bad                           ; p0 = p1
    ucomisd xmm4, [rel paint_max]
    ja pt_bad
    divsd xmm2, xmm4
    divsd xmm3, xmm4
    mov r9d, UGFX_PAINT_LINEAR
    jmp pt_gradient

; -----------------------------------------------------------------------------
; ugfx_paint_radial — rdi = UgfxPaint*, rsi = arena, rdx = const UgfxStop*,
;   ecx = stop count, r8d = UGFX_SPREAD_*, xmm0..xmm2 = cx, cy, r (> 0)
;   -> rax = 0, -EINVAL, -ENOMEM
; -----------------------------------------------------------------------------
global ugfx_paint_radial
ugfx_paint_radial:
    xorpd xmm5, xmm5
    ucomisd xmm2, xmm5
    jp pt_bad
    jbe pt_bad
    ucomisd xmm2, [rel paint_max]
    ja pt_bad
    movsd xmm4, [rel paint_one]
    divsd xmm4, xmm2
    movapd xmm2, xmm4
    xorpd xmm3, xmm3
    mov r9d, UGFX_PAINT_RADIAL
    jmp pt_gradient

; -----------------------------------------------------------------------------
; ugfx_paint_conic — rdi = UgfxPaint*, rsi = arena, rdx = const UgfxStop*,
;   ecx = stop count, xmm0..xmm2 = cx, cy, start angle (radians)
;   -> rax = 0, -EINVAL, -ENOMEM. t runs once around, so there is no spread.
; -----------------------------------------------------------------------------
global ugfx_paint_conic
ugfx_paint_conic:
    movapd xmm4, xmm2
    andpd xmm4, [rel paint_abs_mask]
    ucomisd xmm4, [rel paint_max]
    jp pt_bad
    ja pt_bad
    mulsd xmm2, [rel paint_inv_2pi]
    xorpd xmm3, xmm3
    mov r8d, UGFX_SPREAD_PAD
    mov r9d, UGFX_PAINT_CONIC
    jmp pt_gradient

pt_bad:
    mov rax, -(EINVAL)
    ret

; -----------------------------------------------------------------------------
; pt_gradient — the shared constructor: rdi = paint, rsi = arena, rdx = stops,
;   ecx = n, r8d = spread, r9d = type, xmm0..xmm3 = geometry
; -----------------------------------------------------------------------------
%define G_PAINT     0
%define G_ARENA     8
%define G_STOPS     16
%define G_N         24                  ; u32
%define G_I         28                  ; u32
%define G_J         32                  ; u32
%define G_SCRATCH   40                  ; per stop: offset, b, g, r, a (f64)
%define G_T         48
%define G_SIZE      56

pt_gradient:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, G_SIZE
    mov r15, rsp
    test rdi, rdi
    jz .g_bad
    test rdx, rdx
    jz .g_bad
    test ecx, ecx
    jz .g_bad
    cmp r8d, UGFX_SPREAD_REFLECT
    ja .g_bad
    ; the geometry must be finite
    movapd xmm4, xmm0
    andpd xmm4, [rel paint_abs_mask]
    ucomisd xmm4, [rel paint_max]
    jp .g_bad
    ja .g_bad
    movapd xmm4, xmm1
    andpd xmm4, [rel paint_abs_mask]
    ucomisd xmm4, [rel paint_max]
    jp .g_bad
    ja .g_bad
    movapd xmm4, xmm2
    andpd xmm4, [rel paint_abs_mask]
    ucomisd xmm4, [rel paint_max]
    jp .g_bad
    ja .g_bad
    movapd xmm4, xmm3
    andpd xmm4, [rel paint_abs_mask]
    ucomisd xmm4, [rel paint_max]
    jp .g_bad
    ja .g_bad
    mov [r15 + G_PAINT], rdi
    mov [r15 + G_ARENA], rsi
    mov [r15 + G_STOPS], rdx
    mov [r15 + G_N], ecx
    mov dword [rdi + UgfxPaint_type], r9d
    mov dword [rdi + UgfxPaint_spread], r8d
    mov dword [rdi + UgfxPaint_color], 0
    movsd [rdi + UgfxPaint_geom], xmm0
    movsd [rdi + UgfxPaint_geom + 8], xmm1
    movsd [rdi + UgfxPaint_geom + 16], xmm2
    movsd [rdi + UgfxPaint_geom + 24], xmm3
    xorpd xmm0, xmm0
    movsd [rdi + UgfxPaint_geom + 32], xmm0
    movsd [rdi + UgfxPaint_geom + 40], xmm0
    ; stops: clamped offsets and premultiplied colours, 40 bytes each
    mov rdi, rsi
    mov esi, ecx
    imul rsi, rsi, 40
    call arena_alloc
    test rax, rax
    jz .g_nomem
    mov [r15 + G_SCRATCH], rax
    mov r12, rax                        ; scratch
    mov r13, [r15 + G_STOPS]
    xor ebx, ebx
    xorpd xmm7, xmm7                    ; previous offset (and the floor 0)
.g_stop:
    movsd xmm0, [r13 + UgfxStop_offset]
    ucomisd xmm0, xmm0
    jp .g_bad                           ; NaN position
    maxsd xmm0, xmm7                    ; >= 0 and >= the previous stop
    minsd xmm0, [rel paint_one]
    movapd xmm7, xmm0
    movsd [r12], xmm0
    mov eax, [r13 + UgfxStop_color]
    mov edx, eax
    shr edx, 24
    cvtsi2sd xmm6, edx                  ; alpha
    movsd [r12 + 32], xmm6
    mulsd xmm6, [rel paint_inv_255]     ; alpha / 255
    xor ecx, ecx
.g_channel:
    mov edx, eax
    shr edx, cl
    and edx, 255
    cvtsi2sd xmm1, edx
    mulsd xmm1, xmm6                    ; premultiplied
    mov edx, ecx
    shr edx, 3
    movsd [r12 + 8 + rdx * 8], xmm1
    add ecx, 8
    cmp ecx, 24
    jb .g_channel
    add r12, 40
    add r13, UgfxStop_SIZE
    inc ebx
    cmp ebx, [r15 + G_N]
    jb .g_stop
    ; the table
    mov rdi, [r15 + G_ARENA]
    mov esi, UGFX_GRADIENT_LUT * 4
    call arena_alloc
    test rax, rax
    jz .g_nomem
    mov rdi, [r15 + G_PAINT]
    mov [rdi + UgfxPaint_lut], rax
    mov r14, rax
    mov r12, [r15 + G_SCRATCH]
    mov dword [r15 + G_I], 0
    mov dword [r15 + G_J], 0            ; last stop with offset <= t
.g_entry:
    mov eax, [r15 + G_I]
    cvtsi2sd xmm0, eax
    divsd xmm0, [rel paint_lut_last]    ; t
    ; advance j while the next stop is at or before t
.g_advance:
    mov eax, [r15 + G_J]
    inc eax
    cmp eax, [r15 + G_N]
    jae .g_have_j
    imul rdx, rax, 40
    ucomisd xmm0, [r12 + rdx]
    jb .g_have_j
    mov [r15 + G_J], eax
    jmp .g_advance
.g_have_j:
    mov eax, [r15 + G_J]
    imul rbx, rax, 40
    add rbx, r12                        ; stop j
    ; before the first stop, or at/after the last: the end colour
    ucomisd xmm0, [rbx]
    jb .g_flat
    inc eax
    cmp eax, [r15 + G_N]
    jae .g_flat
    ; f = (t - o_j) / (o_j+1 - o_j), o_j+1 > t >= o_j
    subsd xmm0, [rbx]
    movsd xmm1, [rbx + 40]
    subsd xmm1, [rbx]
    divsd xmm0, xmm1
    jmp .g_mix
.g_flat:
    xorpd xmm0, xmm0
.g_mix:
    ; channel k = c_j + (c_j+1 - c_j) f, with c_j+1 = c_j for flat
    xor r13d, r13d                      ; packed colour
    xor ecx, ecx
.g_mix_channel:
    mov edx, ecx
    shr edx, 3
    movsd xmm1, [rbx + 8 + rdx * 8]
    xorpd xmm2, xmm2
    ucomisd xmm0, xmm2
    je .g_mix_round                     ; f = 0 (also flat: no next stop read)
    movsd xmm2, [rbx + 48 + rdx * 8]
    subsd xmm2, xmm1
    mulsd xmm2, xmm0
    addsd xmm1, xmm2
.g_mix_round:
    cvtsd2si eax, xmm1                  ; nearest
    shl eax, cl
    or r13d, eax
    add ecx, 8
    cmp ecx, 32
    jb .g_mix_channel
    mov eax, [r15 + G_I]
    mov [r14 + rax * 4], r13d
    inc dword [r15 + G_I]
    cmp dword [r15 + G_I], UGFX_GRADIENT_LUT
    jb .g_entry
    ; identity transform, the gradient span
    mov rdi, [r15 + G_PAINT]
    lea rax, [rel pt_span_gradient]
    mov [rdi + UgfxPaint_span], rax
    lea rdi, [rdi + UgfxPaint_inverse]
    call umath_affine2_identity
    xor eax, eax
    jmp .g_out
.g_bad:
    mov rax, -(EINVAL)
    jmp .g_out
.g_nomem:
    mov rax, -(ENOMEM)
.g_out:
    add rsp, G_SIZE
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15

; -----------------------------------------------------------------------------
; ugfx_paint_set_transform — rdi = UgfxPaint*, rsi = const double m[6]
;   (paint space -> device space) -> rax = 0, -EINVAL (singular; unchanged)
; -----------------------------------------------------------------------------
global ugfx_paint_set_transform
ugfx_paint_set_transform:
    test rdi, rdi
    jz pt_bad
    test rsi, rsi
    jz pt_bad
    lea rdi, [rdi + UgfxPaint_inverse]
    call umath_affine2_invert
    test eax, eax
    jnz pt_bad
    ret

; -----------------------------------------------------------------------------
; Span functions (ugfx_raster_fill_paint): rdi = PixBuf*, esi = x, edx = y,
;   ecx = length, r8d = coverage, r9 = const UgfxPaint*
; -----------------------------------------------------------------------------
pt_span_solid:
    mov r9d, [r9 + UgfxPaint_color]
    jmp ugfx_span_fill_solid

%define S_PIX       0
%define S_PAINT     8
%define S_Y         16                  ; u32
%define S_COV       20                  ; u32
%define S_X         24                  ; u32 first pixel of the chunk
%define S_END       28                  ; u32
%define S_N         32                  ; u32 pixels in the chunk
%define S_K         36                  ; u32
%define S_PX        40                  ; paint-space position of the pixel
%define S_PY        48
%define S_T         56
%define S_BUF       64                  ; u32[PAINT_CHUNK]
%define S_SIZE      (64 + PAINT_CHUNK * 4 + 8)

pt_span_gradient:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, S_SIZE
    mov r15, rsp
    xor eax, eax
    test r8d, r8d
    jz .s_out
    ; clip to the buffer first, so only visible pixels are coloured
    test edx, edx
    js .s_out
    movsxd rax, edx
    cmp rax, [rdi + PixBuf_height]
    jae .s_ok
    movsxd rsi, esi
    movsxd rcx, ecx
    lea rax, [rsi + rcx]
    mov r10, [rdi + PixBuf_width]
    cmp rax, r10
    jle .s_end_ok
    mov rax, r10
.s_end_ok:
    test rsi, rsi
    jns .s_start_ok
    xor esi, esi
.s_start_ok:
    cmp rsi, rax
    jge .s_ok
    mov [r15 + S_PIX], rdi
    mov [r15 + S_PAINT], r9
    mov [r15 + S_Y], edx
    mov [r15 + S_COV], r8d
    mov [r15 + S_X], esi
    mov [r15 + S_END], eax
.s_chunk:
    mov eax, [r15 + S_END]
    sub eax, [r15 + S_X]
    jle .s_ok
    cmp eax, PAINT_CHUNK
    jbe .s_chunk_n
    mov eax, PAINT_CHUNK
.s_chunk_n:
    mov [r15 + S_N], eax
    mov dword [r15 + S_K], 0
    ; p = inverse * (x + 0.5, y + 0.5)
    mov rbx, [r15 + S_PAINT]
    cvtsi2sd xmm0, dword [r15 + S_X]
    addsd xmm0, [rel paint_half]
    cvtsi2sd xmm1, dword [r15 + S_Y]
    addsd xmm1, [rel paint_half]
    movsd xmm2, [rbx + UgfxPaint_inverse]
    mulsd xmm2, xmm0
    movsd xmm3, [rbx + UgfxPaint_inverse + 16]
    mulsd xmm3, xmm1
    addsd xmm2, xmm3
    addsd xmm2, [rbx + UgfxPaint_inverse + 32]
    movsd [r15 + S_PX], xmm2
    movsd xmm2, [rbx + UgfxPaint_inverse + 8]
    mulsd xmm2, xmm0
    movsd xmm3, [rbx + UgfxPaint_inverse + 24]
    mulsd xmm3, xmm1
    addsd xmm2, xmm3
    addsd xmm2, [rbx + UgfxPaint_inverse + 40]
    movsd [r15 + S_PY], xmm2
.s_pixel:
    mov rbx, [r15 + S_PAINT]
    movsd xmm0, [r15 + S_PX]
    movsd xmm1, [r15 + S_PY]
    subsd xmm0, [rbx + UgfxPaint_geom]
    subsd xmm1, [rbx + UgfxPaint_geom + 8]
    mov eax, [rbx + UgfxPaint_type]
    cmp eax, UGFX_PAINT_LINEAR
    je .s_linear
    cmp eax, UGFX_PAINT_RADIAL
    je .s_radial
    ; conic: atan2(dy, dx) in turns from the start, wrapped to [0, 1)
    movapd xmm2, xmm0
    movapd xmm0, xmm1
    movapd xmm1, xmm2
    call umath_atan2_f64
    mulsd xmm0, [rel paint_inv_2pi]
    subsd xmm0, [rbx + UgfxPaint_geom + 16]
    call umath_floor_f64_fractional
    jmp .s_pad
.s_linear:
    mulsd xmm0, [rbx + UgfxPaint_geom + 16]
    mulsd xmm1, [rbx + UgfxPaint_geom + 24]
    addsd xmm0, xmm1
    jmp .s_spread
.s_radial:
    mulsd xmm0, xmm0
    mulsd xmm1, xmm1
    addsd xmm0, xmm1
    sqrtsd xmm0, xmm0
    mulsd xmm0, [rbx + UgfxPaint_geom + 16]
.s_spread:
    mov eax, [rbx + UgfxPaint_spread]
    cmp eax, UGFX_SPREAD_REPEAT
    je .s_repeat
    cmp eax, UGFX_SPREAD_REFLECT
    jne .s_pad
    ; reflect: u = 2 frac(t / 2), folded: u > 1 -> 2 - u
    mulsd xmm0, [rel paint_half]
    call umath_floor_f64_fractional
    addsd xmm0, xmm0
    ucomisd xmm0, [rel paint_one]
    jbe .s_pad
    movsd xmm1, [rel paint_two]
    subsd xmm1, xmm0
    movapd xmm0, xmm1
    jmp .s_pad
.s_repeat:
    call umath_floor_f64_fractional
.s_pad:
    maxsd xmm0, [rel paint_zero]        ; NaN -> 0
    minsd xmm0, [rel paint_one]
    mulsd xmm0, [rel paint_lut_last]
    addsd xmm0, [rel paint_half]
    cvttsd2si eax, xmm0
    mov rbx, [r15 + S_PAINT]
    mov rdx, [rbx + UgfxPaint_lut]
    mov eax, [rdx + rax * 4]
    mov ecx, [r15 + S_K]
    mov [r15 + S_BUF + rcx * 4], eax
    ; next pixel: p += (a, b)
    movsd xmm0, [r15 + S_PX]
    addsd xmm0, [rbx + UgfxPaint_inverse]
    movsd [r15 + S_PX], xmm0
    movsd xmm0, [r15 + S_PY]
    addsd xmm0, [rbx + UgfxPaint_inverse + 8]
    movsd [r15 + S_PY], xmm0
    inc dword [r15 + S_K]
    mov eax, [r15 + S_K]
    cmp eax, [r15 + S_N]
    jb .s_pixel
    ; blend the chunk
    mov rdi, [r15 + S_PIX]
    mov esi, [r15 + S_X]
    mov edx, [r15 + S_Y]
    mov ecx, [r15 + S_N]
    mov r8d, [r15 + S_COV]
    lea r9, [r15 + S_BUF]
    call ugfx_span_blend_colors
    mov eax, [r15 + S_N]
    add [r15 + S_X], eax
    jmp .s_chunk
.s_ok:
    xor eax, eax
.s_out:
    add rsp, S_SIZE
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15

section .rodata
align 16
paint_abs_mask:     dq 0x7FFFFFFFFFFFFFFF, 0x7FFFFFFFFFFFFFFF

section .data
global ugfx_paint_version
ugfx_paint_version: dq 0x010000
