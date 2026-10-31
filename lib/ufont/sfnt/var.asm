; =============================================================================
; Utkarsha OS — lib/ufont/sfnt/var.asm
; =============================================================================
; Variable fonts (OpenType font variations) as HarfBuzz applies them, as
; tools/varmodel.py and tools/fontmodel.py model them.
;
;   ufont_set_variations(font, settings, count) -> eax 0, -1 (no fvar)
;       settings: u32 tag (as the font writes it), f32 value per axis
;       wanted. fvar's ranges and avar's segment maps give the normalized
;       coordinates (2.14), in float32 step for step with HarfBuzz;
;       outlines, advances, GPOS adjustments and feature variations follow
;       them; the outline cache starts over.
;   ufl_var_init (rbx = font, from ufont_open): the axes, the coordinates
;       (0), GDEF's item variation store
;   ufl_var_delta(rdi = item variation store, rsi = its table's end, edx =
;       outer, ecx = inner, r8 = font) -> xmm0 (f32): region scalars times
;       deltas, summed in float32
;   ufl_var_round: xmm0 (f32) -> eax rounded half away from zero
;   ufl_var_advance(rdi = font, esi = glyph, edx = advance) -> eax with
;       HVAR's rounded delta (at least 0)
;   ufl_var_device(rdi = a Device table, rsi = its table's end, r8 = font)
;       -> eax a VariationIndex device's rounded delta, else 0
;   ufl_var_feature(rdi = GSUB / GPOS, rsi = its end, edx = feature index,
;       r8 = font) -> rax the alternate Feature table the first
;       FeatureVariation record whose conditions hold gives it, 0
;   ufl_var_outline(rdi = font, esi = glyph, rdx = path, xmm0 = scale) ->
;       rax 0, -errno: a glyf glyph varied by gvar - its points (simple) or
;       component offsets (composite) and four phantom points moved by
;       every tuple's deltas (points a tuple leaves out interpolated from
;       its neighbours, IUP), components transformed and placed at their
;       varied offsets, the whole shifted by the varied left side bearing,
;       drawn as quadratic contours at scale, y down; in doubles.
; Not read: avar 2, CFF2, MVAR; components placed by matching points sit at
; offset 0.
; =============================================================================

%include "ugfx.inc"
%include "ufont.inc"

extern arena_alloc
extern ugfx_path_move_to
extern ugfx_path_line_to
extern ugfx_path_quad_to
extern ugfx_path_close

%define VP              32768           ; points (with phantoms) a varied glyph may gather
%define VAR_MAX_DEPTH   6

; the per-font scratch for varied outlines (UfontFont_vscratch)
%define VX_PX           0                       ; f64 x
%define VX_PY           (VX_PX + 8 * VP)
%define VX_SX           (VX_PY + 8 * VP)        ; f64 the deltas summed
%define VX_SY           (VX_SX + 8 * VP)
%define VX_TX           (VX_SY + 8 * VP)        ; f64 one tuple's deltas
%define VX_TY           (VX_TX + 8 * VP)
%define VX_CS           (VX_TY + 8 * VP)        ; f64 x, y: components' offsets and phantoms, stacked
%define VX_IDX          (VX_CS + 16 * VP)       ; u32 a tuple's own point numbers
%define VX_SIDX         (VX_IDX + 4 * VP)       ; u32 the shared ones
%define VX_DX           (VX_SIDX + 4 * VP)      ; i32 a tuple's x deltas
%define VX_DY           (VX_DX + 4 * VP)
%define VX_ON           (VX_DY + 4 * VP)        ; u8 on the curve
%define VX_END          (VX_ON + VP)            ; u8 ends a contour
%define VX_NAMED        (VX_END + VP)           ; u8 a tuple names it
%define VX_SIZE         (VX_NAMED + VP)

section .rodata
align 16
vr_65536f:  dd 65536.0
vr_16384f:  dd 16384.0
vr_onef:    dd 1.0
align 8
vr_half:    dq 0.5
vr_f2dot14: dq 0x3F10000000000000       ; 1 / 16384
align 16
vr_absf:    dd 0x7FFFFFFF, 0, 0, 0

section .text

%macro BE16 2
    movzx %1, word %2
    bswap %1
    shr %1, 16
%endmacro

; ----------------------------------------------------------------------------
; ufl_var_round — xmm0 = f32 -> eax (roundf)
; ----------------------------------------------------------------------------
global ufl_var_round
ufl_var_round:
    cvtss2sd xmm0, xmm0
    xorpd xmm1, xmm1
    ucomisd xmm0, xmm1
    jb .neg
    addsd xmm0, [rel vr_half]
    cvttsd2si eax, xmm0
    ret
.neg:
    subsd xmm1, xmm0
    addsd xmm1, [rel vr_half]
    cvttsd2si eax, xmm1
    neg eax
    ret

; ----------------------------------------------------------------------------
; ufl_var_init — rbx = font
; ----------------------------------------------------------------------------
global ufl_var_init
ufl_var_init:
    push r12
    mov dword [rbx + UfontFont_naxes], 0
    mov qword [rbx + UfontFont_coords], 0
    mov dword [rbx + UfontFont_varied], 0
    mov qword [rbx + UfontFont_varstore], 0
    mov qword [rbx + UfontFont_vscratch], 0
    ; GDEF 1.3's item variation store
    mov rax, [rbx + UfontFont_gdef]
    test rax, rax
    jz .fvar
    cmp qword [rbx + UfontFont_gdef_len], 18
    jb .fvar
    mov ecx, [rax]
    bswap ecx
    cmp ecx, 0x00010003
    jb .fvar
    mov ecx, [rax + 14]
    bswap ecx
    test ecx, ecx
    jz .fvar
    cmp rcx, [rbx + UfontFont_gdef_len]
    jae .fvar
    add rcx, rax
    mov [rbx + UfontFont_varstore], rcx
    mov rcx, [rbx + UfontFont_gdef_len]
    add rcx, rax
    mov [rbx + UfontFont_varstore_end], rcx
.fvar:
    mov rax, [rbx + UfontFont_fvar]
    test rax, rax
    jz .out
    cmp qword [rbx + UfontFont_fvar_len], 16
    jb .none
    BE16 ecx, [rax + 4]                 ; the axis records at
    BE16 edx, [rax + 8]                 ; axes
    BE16 r8d, [rax + 10]                ; a record's size
    cmp r8d, 20
    jb .none
    test edx, edx
    jz .none
    cmp edx, 64
    ja .none
    imul r8d, edx
    add r8d, ecx
    cmp r8, [rbx + UfontFont_fvar_len]
    ja .none
    mov r12d, edx
    mov rdi, [rbx + UfontFont_arena]
    lea esi, [rdx * 4]
    call arena_alloc
    test rax, rax
    jz .none
    mov [rbx + UfontFont_coords], rax
    mov rdi, rax
    mov ecx, r12d
    xor eax, eax
    rep stosd
    mov [rbx + UfontFont_naxes], r12d
    jmp .out
.none:
    mov qword [rbx + UfontFont_fvar], 0
.out:
    pop r12
    ret

; ----------------------------------------------------------------------------
; ufont_set_variations — rdi = font, rsi = settings, edx = count -> eax 0, -1
; ----------------------------------------------------------------------------
%define SV_C16      0                   ; i32 x 64: the coordinates in 16.16
%define SV_SIZE     264

global ufont_set_variations
ufont_set_variations:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, SV_SIZE
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov eax, -1
    cmp dword [rbx + UfontFont_naxes], 0
    je .out
    xor eax, eax
    xor ecx, ecx
.zero:
    mov [rsp + SV_C16 + rcx * 4], eax
    inc ecx
    cmp ecx, 64
    jb .zero
    mov r14, [rbx + UfontFont_fvar]
.setting:
    ; each in order (a later one for the same axis wins)
    test r13d, r13d
    jz .avar
    dec r13d
    mov eax, [r12]
    movss xmm0, [r12 + 4]
    add r12, 8
    BE16 ecx, [r14 + 4]
    add rcx, r14
    BE16 r8d, [r14 + 10]
    xor ebp, ebp
.axis:
    cmp ebp, [rbx + UfontFont_naxes]
    jae .setting
    cmp [rcx], eax
    je .found
    add rcx, r8
    inc ebp
    jmp .axis
.found:
    ; min / default / max (Fixed) as f32, ordered around the default
    mov eax, [rcx + 4]
    bswap eax
    cvtsi2ss xmm1, eax
    divss xmm1, [rel vr_65536f]
    mov eax, [rcx + 8]
    bswap eax
    cvtsi2ss xmm2, eax
    divss xmm2, [rel vr_65536f]
    mov eax, [rcx + 12]
    bswap eax
    cvtsi2ss xmm3, eax
    divss xmm3, [rel vr_65536f]
    minss xmm1, xmm2
    maxss xmm3, xmm2
    maxss xmm0, xmm1                    ; clamped
    minss xmm0, xmm3
    xorps xmm4, xmm4
    ucomiss xmm0, xmm2
    je .normalized
    jb .below
    subss xmm0, xmm2
    subss xmm3, xmm2
    divss xmm0, xmm3
    movss xmm4, xmm0
    jmp .normalized
.below:
    subss xmm0, xmm2
    subss xmm2, xmm1
    divss xmm0, xmm2
    movss xmm4, xmm0
.normalized:
    movss xmm0, xmm4
    mulss xmm0, [rel vr_65536f]
    call ufl_var_round
    mov [rsp + SV_C16 + rbp * 4], eax
    jmp .setting
.avar:
    mov r14, [rbx + UfontFont_avar]
    test r14, r14
    jz .round
    mov r15, [rbx + UfontFont_avar_len]
    add r15, r14
    lea rax, [r14 + 8]
    cmp rax, r15
    ja .round
    BE16 r13d, [r14 + 6]
    cmp r13d, [rbx + UfontFont_naxes]
    jbe .maps
    mov r13d, [rbx + UfontFont_naxes]
.maps:
    lea r12, [r14 + 8]
    xor ebp, ebp
.map:
    cmp ebp, r13d
    jae .round
    lea rax, [r12 + 2]
    cmp rax, r15
    ja .round
    BE16 ecx, [r12]
    lea rax, [r12 + rcx * 4 + 2]
    cmp rax, r15
    ja .round
    cvtsi2ss xmm0, dword [rsp + SV_C16 + rbp * 4]
    divss xmm0, [rel vr_65536f]
    lea rdi, [r12 + 2]
    mov esi, ecx
    call vr_map_float
    mulss xmm0, [rel vr_65536f]
    call ufl_var_round
    mov [rsp + SV_C16 + rbp * 4], eax
    BE16 ecx, [r12]
    lea r12, [r12 + rcx * 4 + 2]
    inc ebp
    jmp .map
.round:
    ; 16.16 -> 2.14; varied when any is not 0
    mov rdi, [rbx + UfontFont_coords]
    xor ecx, ecx
    xor edx, edx
.c14:
    cmp ecx, [rbx + UfontFont_naxes]
    jae .c14_done
    mov eax, [rsp + SV_C16 + rcx * 4]
    add eax, 2
    sar eax, 2
    mov [rdi + rcx * 4], eax
    or edx, eax
    inc ecx
    jmp .c14
.c14_done:
    xor eax, eax
    test edx, edx
    setnz al
    mov [rbx + UfontFont_varied], eax
    mov rdi, [rbx + UfontFont_cache]    ; the outline cache starts over
    test rdi, rdi
    jz .done
    mov ecx, [rbx + UfontFont_nglyphs]
    xor eax, eax
    rep stosq
.done:
    xor eax, eax
.out:
    add rsp, SV_SIZE
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; an AxisValueMap's from (%3 = 0) or to (2) of pair %2 (rdi = the pairs) ->
;   %1 as f32
%macro PAIR 3
    movzx eax, word [rdi + %2 * 4 + %3]
    rol ax, 8
    cwde
    cvtsi2ss %1, eax
    divss %1, [rel vr_16384f]
%endmacro

; vr_map_float — xmm0 = value, rdi = pairs, esi = count -> xmm0 (avar's
;   map_float, f32)
vr_map_float:
    push rbx
    push r12
    cmp esi, 2
    jae .two
    test esi, esi
    jz .out
    xor ebx, ebx
    jmp .shift
.two:
    xor r8d, r8d                        ; start
    mov r9d, esi                        ; end
    movss xmm6, [rel vr_onef]           ; 1
    xorps xmm7, xmm7
    subss xmm7, xmm6                    ; -1
    PAIR xmm1, r8, 0
    PAIR xmm2, r8, 2
    mov r10d, 1
    PAIR xmm3, r10, 0
    ucomiss xmm1, xmm7
    jne .end_check
    ucomiss xmm2, xmm7
    jne .end_check
    ucomiss xmm3, xmm7
    jne .end_check
    inc r8d
.end_check:
    lea r10d, [r9 - 1]
    PAIR xmm1, r10, 0
    PAIR xmm2, r10, 2
    lea r11d, [r9 - 2]
    PAIR xmm3, r11, 0
    ucomiss xmm1, xmm6
    jne .exact
    ucomiss xmm2, xmm6
    jne .exact
    ucomiss xmm3, xmm6
    jne .exact
    dec r9d
.exact:
    mov ebx, r8d
.find:
    cmp ebx, r9d
    jae .lerp
    PAIR xmm1, rbx, 0
    ucomiss xmm0, xmm1
    je .matched
    inc ebx
    jmp .find
.matched:
    mov r12d, ebx
.more:
    lea r10d, [r12 + 1]
    cmp r10d, r9d
    jae .matched_end
    PAIR xmm1, r10, 0
    ucomiss xmm0, xmm1
    jne .matched_end
    inc r12d
    jmp .more
.matched_end:
    cmp ebx, r12d
    jne .several
    PAIR xmm0, rbx, 2
    jmp .out
.several:
    lea r10d, [rbx + 2]
    cmp r10d, r12d
    jne .not_three
    inc ebx
    PAIR xmm0, rbx, 2
    jmp .out
.not_three:
    xorps xmm1, xmm1
    ucomiss xmm0, xmm1
    jb .take_j
    ja .take_i
    PAIR xmm2, rbx, 2                   ; 0: the one mapping closer to 0
    PAIR xmm3, r12, 2
    movss xmm4, xmm2
    andps xmm4, [rel vr_absf]
    movss xmm5, xmm3
    andps xmm5, [rel vr_absf]
    movss xmm0, xmm3
    ucomiss xmm4, xmm5
    jae .out
    movss xmm0, xmm2
    jmp .out
.take_j:
    PAIR xmm0, r12, 2
    jmp .out
.take_i:
    PAIR xmm0, rbx, 2
    jmp .out
.lerp:
    mov ebx, r8d
.seg:
    cmp ebx, r9d
    jae .after
    PAIR xmm1, rbx, 0
    ucomiss xmm0, xmm1
    jb .seg_have
    inc ebx
    jmp .seg
.seg_have:
    test ebx, ebx
    jnz .between
    jmp .shift                          ; before every pair: by the first
.after:
    lea ebx, [r9 - 1]                   ; after every pair: by the last
.shift:
    PAIR xmm1, rbx, 0
    PAIR xmm2, rbx, 2
    subss xmm0, xmm1
    addss xmm0, xmm2
    jmp .out
.between:
    lea r10d, [rbx - 1]
    PAIR xmm1, r10, 0                   ; before.from
    PAIR xmm2, r10, 2                   ; before.to
    PAIR xmm3, rbx, 0                   ; after.from
    PAIR xmm4, rbx, 2                   ; after.to
    subss xmm3, xmm1
    subss xmm4, xmm2
    subss xmm0, xmm1
    mulss xmm4, xmm0
    divss xmm4, xmm3
    addss xmm2, xmm4
    movss xmm0, xmm2
.out:
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------------
; ufl_var_delta — rdi = store, rsi = end, edx = outer, ecx = inner, r8 = font
; ----------------------------------------------------------------------------
%define VD_DELTA    0                   ; f32
%define VD_ROW      8
%define VD_VALUE    16                  ; i32
%define VD_SIZE     24

global ufl_var_delta
ufl_var_delta:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, VD_SIZE
    xorps xmm0, xmm0
    movss [rsp + VD_DELTA], xmm0
    mov rbx, rdi
    mov r12, rsi
    mov r13, r8
    lea rax, [rbx + 8]
    cmp rax, r12
    ja .out
    BE16 eax, [rbx + 6]                 ; data sets
    cmp edx, eax
    jae .out
    lea rax, [rbx + rdx * 4 + 12]
    cmp rax, r12
    ja .out
    mov eax, [rbx + rdx * 4 + 8]
    bswap eax
    lea r14, [rbx + rax]                ; the data set
    lea rax, [r14 + 6]
    cmp rax, r12
    ja .out
    mov eax, [rbx + 2]
    bswap eax
    lea r15, [rbx + rax]                ; the region list
    lea rax, [r15 + 4]
    cmp rax, r12
    ja .out
    BE16 eax, [r14]                     ; items
    cmp ecx, eax
    jae .out
    BE16 ebp, [r14 + 4]                 ; regions
    test ebp, ebp
    jz .out
    lea rax, [r14 + rbp * 2 + 6]
    cmp rax, r12
    ja .out
    BE16 r9d, [r14 + 2]
    mov r10d, r9d
    and r10d, 0x8000                    ; long words
    and r9d, 0x7FFF
    cmp r9d, ebp
    ja .out
    ; the row: words (2 or 4 bytes) then the rest (1 or 2)
    mov eax, ebp
    sub eax, r9d
    test r10d, r10d
    jnz .long_row
    lea eax, [rax + r9 * 2]
    jmp .row
.long_row:
    add eax, eax
    lea eax, [rax + r9 * 4]
.row:
    mov edx, eax
    imul eax, ecx
    lea rdi, [r14 + rbp * 2 + 6]
    add rdi, rax
    lea rax, [rdi + rdx]
    cmp rax, r12
    ja .out
    mov [rsp + VD_ROW], rdi
    xor ecx, ecx
.k:
    cmp ecx, ebp
    jae .out
    mov rdi, [rsp + VD_ROW]
    cmp ecx, r9d
    jae .short
    test r10d, r10d
    jnz .i32
    movzx eax, word [rdi]
    rol ax, 8
    cwde
    add rdi, 2
    jmp .have
.i32:
    mov eax, [rdi]
    bswap eax
    add rdi, 4
    jmp .have
.short:
    test r10d, r10d
    jnz .i16
    movsx eax, byte [rdi]
    inc rdi
    jmp .have
.i16:
    movzx eax, word [rdi]
    rol ax, 8
    cwde
    add rdi, 2
.have:
    mov [rsp + VD_ROW], rdi
    mov [rsp + VD_VALUE], eax
    BE16 edx, [r14 + rcx * 2 + 6]       ; the region
    push rcx
    push r9
    push r10
    sub rsp, 8
    mov rdi, r15
    mov rsi, r12
    mov r8, r13
    call vr_region
    add rsp, 8
    pop r10
    pop r9
    pop rcx
    xorps xmm1, xmm1
    ucomiss xmm0, xmm1
    je .next
    cvtsi2ss xmm1, dword [rsp + VD_VALUE]
    mulss xmm0, xmm1
    addss xmm0, [rsp + VD_DELTA]
    movss [rsp + VD_DELTA], xmm0
.next:
    inc ecx
    jmp .k
.out:
    movss xmm0, [rsp + VD_DELTA]
    add rsp, VD_SIZE
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; vr_region — rdi = region list, rsi = end, edx = region, r8 = font ->
;   xmm0 its scalar (f32)
vr_region:
    push rbx
    push r12
    push r13
    xorps xmm0, xmm0
    BE16 eax, [rdi + 2]
    cmp edx, eax
    jae .out
    BE16 ebx, [rdi]                     ; axes
    imul eax, edx, 6
    imul eax, ebx
    lea r9, [rdi + rax + 4]
    imul eax, ebx, 6
    lea rax, [r9 + rax]
    cmp rax, rsi
    ja .out
    movss xmm0, [rel vr_onef]
    xor ecx, ecx
.axis:
    cmp ecx, ebx
    jae .out
    xor r10d, r10d                      ; the coordinate
    cmp ecx, [r8 + UfontFont_naxes]
    jae .coord
    mov rax, [r8 + UfontFont_coords]
    mov r10d, [rax + rcx * 4]
.coord:
    imul eax, ecx, 6
    movzx r11d, word [r9 + rax + 2]     ; peak
    rol r11w, 8
    movsx r11d, r11w
    movzx r12d, word [r9 + rax]         ; start
    rol r12w, 8
    movsx r12d, r12w
    movzx r13d, word [r9 + rax + 4]     ; end
    rol r13w, 8
    movsx r13d, r13w
    test r11d, r11d
    jz .next
    cmp r10d, r11d
    je .next
    test r10d, r10d
    jz .zero
    cmp r12d, r11d
    jg .next
    cmp r11d, r13d
    jg .next
    test r12d, r12d
    jns .ranged
    test r13d, r13d
    jg .next
.ranged:
    cmp r10d, r12d
    jle .zero
    cmp r13d, r10d
    jle .zero
    cmp r10d, r11d
    jge .falling
    mov edx, r10d
    sub edx, r12d
    cvtsi2ss xmm1, edx
    mov edx, r11d
    sub edx, r12d
    cvtsi2ss xmm2, edx
    jmp .factor
.falling:
    mov edx, r13d
    sub edx, r10d
    cvtsi2ss xmm1, edx
    mov edx, r13d
    sub edx, r11d
    cvtsi2ss xmm2, edx
.factor:
    divss xmm1, xmm2
    mulss xmm0, xmm1
.next:
    inc ecx
    jmp .axis
.zero:
    xorps xmm0, xmm0
.out:
    pop r13
    pop r12
    pop rbx
    ret

; vr_delta_map — rdi = a DeltaSetIndexMap, rsi = end, edx = index -> edx
;   outer, ecx inner
vr_delta_map:
    push rbx
    mov ecx, edx
    xor edx, edx
    lea rax, [rdi + 6]
    cmp rax, rsi
    ja .out
    movzx r8d, byte [rdi + 1]           ; entry format
    cmp byte [rdi], 0
    jne .format1
    BE16 r9d, [rdi + 2]
    lea r10, [rdi + 4]
    jmp .count
.format1:
    cmp byte [rdi], 1
    jne .out
    mov r9d, [rdi + 2]
    bswap r9d
    lea r10, [rdi + 6]
.count:
    test r9d, r9d
    jz .out
    cmp ecx, r9d
    jb .indexed
    lea ecx, [r9 - 1]
.indexed:
    mov eax, r8d
    shr eax, 4
    and eax, 3
    inc eax                             ; entry size
    imul ecx, eax
    lea r10, [r10 + rcx]
    lea r11, [r10 + rax]
    cmp r11, rsi
    ja .zero
    xor ebx, ebx
.byte:
    shl ebx, 8
    movzx r11d, byte [r10]
    or ebx, r11d
    inc r10
    dec eax
    jnz .byte
    mov ecx, r8d
    and ecx, 15
    inc ecx                             ; inner bits
    mov edx, ebx
    shr edx, cl
    mov eax, 1
    shl eax, cl
    dec eax
    and ebx, eax
    mov ecx, ebx
    jmp .out
.zero:
    xor edx, edx
    xor ecx, ecx
.out:
    pop rbx
    ret

; ----------------------------------------------------------------------------
; ufl_var_advance — rdi = font, esi = glyph, edx = advance -> eax
; ----------------------------------------------------------------------------
global ufl_var_advance
ufl_var_advance:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov eax, edx
    cmp dword [rdi + UfontFont_varied], 0
    je .out
    mov rbx, [rdi + UfontFont_hvar]
    test rbx, rbx
    jz .out
    mov r12, [rdi + UfontFont_hvar_len]
    cmp r12, 12
    jb .out
    add r12, rbx                        ; end
    mov r13d, edx
    mov r14, rdi
    mov edx, esi                        ; inner: the glyph, through the map
    xor ecx, ecx
    mov eax, [rbx + 8]
    bswap eax
    test eax, eax
    jz .direct
    lea rdi, [rbx + rax]
    mov rsi, r12
    call vr_delta_map
    jmp .delta
.direct:
    mov ecx, edx
    xor edx, edx
.delta:
    mov eax, [rbx + 4]
    bswap eax
    lea rdi, [rbx + rax]
    mov rsi, r12
    mov r8, r14
    call ufl_var_delta
    call ufl_var_round
    add eax, r13d
    jns .out
    xor eax, eax
.out:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------------
; ufl_var_device — rdi = Device, rsi = end, r8 = font -> eax
; ----------------------------------------------------------------------------
global ufl_var_device
ufl_var_device:
    sub rsp, 8
    xor eax, eax
    cmp dword [r8 + UfontFont_varied], 0
    je .out
    test rdi, rdi
    jz .out
    lea rcx, [rdi + 6]
    cmp rcx, rsi
    ja .out
    cmp word [rdi + 4], 0x0080          ; 0x8000: VariationIndex
    jne .out
    BE16 edx, [rdi]                     ; outer
    BE16 ecx, [rdi + 2]                 ; inner
    mov rdi, [r8 + UfontFont_varstore]
    test rdi, rdi
    jz .out
    mov rsi, [r8 + UfontFont_varstore_end]
    call ufl_var_delta
    call ufl_var_round
.out:
    add rsp, 8
    ret

; ----------------------------------------------------------------------------
; ufl_var_feature — rdi = table, rsi = end, edx = feature index, r8 = font
;   -> rax the alternate Feature table, 0
; ----------------------------------------------------------------------------
global ufl_var_feature
ufl_var_feature:
    push rbx
    push r12
    push r13
    push r14
    push r15
    xor eax, eax
    lea rcx, [rdi + 14]
    cmp rcx, rsi
    ja .out
    cmp word [rdi + 2], 0x0100          ; minor version 1
    jb .out
    mov ecx, [rdi + 10]
    bswap ecx
    test ecx, ecx
    jz .out
    lea r12, [rdi + rcx]                ; FeatureVariations
    lea rcx, [r12 + 8]
    cmp rcx, rsi
    ja .out
    mov r13d, [r12 + 4]
    bswap r13d                          ; records
    xor r14d, r14d
.record:
    cmp r14d, r13d
    jae .none
    lea rbx, [r12 + r14 * 8 + 8]
    lea rcx, [rbx + 8]
    cmp rcx, rsi
    ja .none
    mov ecx, [rbx]
    bswap ecx                           ; the condition set
    test ecx, ecx
    jz .holds
    lea r15, [r12 + rcx]
    lea rcx, [r15 + 2]
    cmp rcx, rsi
    ja .none
    BE16 r9d, [r15]                     ; conditions
    xor r10d, r10d
.condition:
    cmp r10d, r9d
    jae .holds
    lea rcx, [r15 + r10 * 4 + 6]
    cmp rcx, rsi
    ja .none
    mov ecx, [r15 + r10 * 4 + 2]
    bswap ecx
    lea r11, [r15 + rcx]
    lea rcx, [r11 + 8]
    cmp rcx, rsi
    ja .next_record
    cmp word [r11], 0x0100              ; format 1
    jne .next_record
    BE16 ecx, [r11 + 2]                 ; axis
    xor eax, eax
    cmp ecx, [r8 + UfontFont_naxes]
    jae .value
    mov rax, [r8 + UfontFont_coords]
    mov eax, [rax + rcx * 4]
.value:
    movzx ecx, word [r11 + 4]
    rol cx, 8
    movsx ecx, cx
    cmp eax, ecx
    jl .next_record
    movzx ecx, word [r11 + 6]
    rol cx, 8
    movsx ecx, cx
    cmp eax, ecx
    jg .next_record
    inc r10d
    jmp .condition
.next_record:
    inc r14d
    jmp .record
.holds:
    ; this record decides: its substitution for the feature, if any
    mov ecx, [rbx + 4]
    bswap ecx
    test ecx, ecx
    jz .none
    lea r15, [r12 + rcx]
    lea rcx, [r15 + 6]
    cmp rcx, rsi
    ja .none
    BE16 r9d, [r15 + 4]
    xor r10d, r10d
.subst:
    cmp r10d, r9d
    jae .none
    imul ecx, r10d, 6
    lea r11, [r15 + rcx + 6]
    lea rcx, [r11 + 6]
    cmp rcx, rsi
    ja .none
    BE16 ecx, [r11]
    cmp ecx, edx
    jne .subst_next
    mov eax, [r11 + 2]
    bswap eax
    add rax, r15
    lea rcx, [rax + 4]
    cmp rcx, rsi
    ja .none
    jmp .out
.subst_next:
    inc r10d
    jmp .subst
.none:
    xor eax, eax
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------------
; ufl_var_outline — rdi = font, esi = glyph, rdx = path, xmm0 = scale
; ----------------------------------------------------------------------------
; the state (r15)
%define VO_FONT     0
%define VO_X        8                   ; the scratch
%define VO_N        16                  ; u32 points gathered
%define VO_CSP      20                  ; u32 the component stack's top (entries)
%define VO_PATH     24
%define VO_SCALE    32
%define VO_ERR      40
%define VO_SIZE     48

global ufl_var_outline
ufl_var_outline:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, VO_SIZE + 8
    mov r15, rsp
    mov [r15 + VO_FONT], rdi
    mov [r15 + VO_PATH], rdx
    movsd [r15 + VO_SCALE], xmm0
    mov dword [r15 + VO_N], 0
    mov dword [r15 + VO_CSP], 0
    mov qword [r15 + VO_ERR], 0
    mov r12d, esi
    mov rbx, rdi
    ; the scratch, once per font
    mov rax, [rbx + UfontFont_vscratch]
    test rax, rax
    jnz .scratch
    mov rdi, [rbx + UfontFont_arena]
    mov esi, VX_SIZE
    call arena_alloc
    test rax, rax
    jz .nomem
    mov [rbx + UfontFont_vscratch], rax
.scratch:
    mov [r15 + VO_X], rax
    mov edi, r12d
    xor esi, esi
    call vr_points
    test eax, eax
    jz .bad
    ; shifted by the varied left side bearing (the first phantom)
    mov r13, [r15 + VO_X]
    mov ecx, [r15 + VO_N]
    movsd xmm0, [r13 + VX_PX + rcx * 8 - 32]
    xorpd xmm1, xmm1
    ucomisd xmm0, xmm1
    je .draw
    xor edx, edx
.shift:
    cmp edx, ecx
    jae .draw
    movsd xmm1, [r13 + VX_PX + rdx * 8]
    subsd xmm1, xmm0
    movsd [r13 + VX_PX + rdx * 8], xmm1
    inc edx
    jmp .shift
.draw:
    call vr_draw
    mov rax, [r15 + VO_ERR]
    jmp .out
.nomem:
    mov rax, -ENOMEM
    jmp .out
.bad:
    xor eax, eax                        ; a damaged glyph draws nothing
.out:
    add rsp, VO_SIZE + 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; ----------------------------------------------------------------------------
; vr_points — edi = glyph, esi = depth, r15 = state -> eax 1 / 0: its points
;   (then four phantoms) gathered at VO_N, varied
; ----------------------------------------------------------------------------
%define GP_GLYPH    0                   ; u32
%define GP_DEPTH    4
%define GP_BASE     8                   ; u32 its first point
%define GP_DATA     16                  ; its glyf data
%define GP_DEND     24
%define GP_NCOMP    32                  ; u32 components
%define GP_CS       36                  ; u32 its component stack entry
%define GP_K        40
%define GP_CHILD    44                  ; u32 the child's first point
%define GP_COMP     48                  ; the component being placed
%define GP_SIZE     64

vr_points:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    sub rsp, GP_SIZE
    mov [rsp + GP_GLYPH], edi
    mov [rsp + GP_DEPTH], esi
    cmp esi, VAR_MAX_DEPTH
    ja .bad
    mov rbx, [r15 + VO_FONT]
    mov r14, [r15 + VO_X]
    cmp edi, [rbx + UfontFont_nglyphs]
    jae .bad
    mov eax, [r15 + VO_N]
    mov [rsp + GP_BASE], eax
    ; its data (loca)
    mov r8, [rbx + UfontFont_loca]
    cmp dword [rbx + UfontFont_loca_fmt], 0
    jne .long
    BE16 eax, [r8 + rdi * 2]
    BE16 ecx, [r8 + rdi * 2 + 2]
    add rax, rax
    add rcx, rcx
    jmp .located
.long:
    mov eax, [r8 + rdi * 4]
    bswap eax
    mov ecx, [r8 + rdi * 4 + 4]
    bswap ecx
.located:
    xor ebp, ebp                        ; xMin
    mov r12d, 0                         ; contours (0: empty)
    cmp rax, rcx
    jae .phantoms
    cmp rcx, [rbx + UfontFont_glyf_len]
    ja .bad
    lea rdx, [rax + 10]
    cmp rdx, rcx
    ja .bad
    mov r13, [rbx + UfontFont_glyf]
    lea rdx, [r13 + rcx]
    mov [rsp + GP_DEND], rdx
    add r13, rax
    mov [rsp + GP_DATA], r13
    movzx eax, word [r13 + 2]
    rol ax, 8
    movsx ebp, ax                       ; xMin
    movzx eax, word [r13]
    rol ax, 8
    movsx r12d, ax
    test r12d, r12d
    jz .phantoms
    js .composite
    call vr_simple
    test eax, eax
    jz .bad
    jmp .phantoms
.composite:
    call vr_components
    test eax, eax
    jz .bad
.phantoms:
    ; xMin - lsb and the advance from hmtx
    mov edi, [rsp + GP_GLYPH]
    call vr_hmetrics                    ; -> eax advance, edx lsb
    sub ebp, edx                        ; h_delta
    mov ecx, [r15 + VO_N]
    lea edx, [rcx + 4]
    cmp edx, VP
    ja .bad
    cvtsi2sd xmm0, ebp
    add eax, ebp
    cvtsi2sd xmm1, eax
    xorpd xmm2, xmm2
    movsd [r14 + VX_PX + rcx * 8], xmm0
    movsd [r14 + VX_PX + rcx * 8 + 8], xmm1
    movsd [r14 + VX_PX + rcx * 8 + 16], xmm2
    movsd [r14 + VX_PX + rcx * 8 + 24], xmm2
    movsd [r14 + VX_PY + rcx * 8], xmm2
    movsd [r14 + VX_PY + rcx * 8 + 8], xmm2
    movsd [r14 + VX_PY + rcx * 8 + 16], xmm2
    movsd [r14 + VX_PY + rcx * 8 + 24], xmm2
    mov dword [r14 + VX_ON + rcx], 0
    mov dword [r14 + VX_END + rcx], 0
    mov [r15 + VO_N], edx
    ; the deltas
    cmp dword [rbx + UfontFont_varied], 0
    je .varied
    cmp qword [rbx + UfontFont_gvar], 0
    je .varied
    mov edi, [rsp + GP_GLYPH]
    mov esi, [rsp + GP_BASE]
    mov edx, [r15 + VO_N]
    sub edx, esi
    call vr_gvar
.varied:
    test r12d, r12d
    jns .ok
    ; a composite: its offsets and phantoms onto the component stack, then
    ; each component's points placed
    mov eax, [r15 + VO_N]
    sub eax, [rsp + GP_BASE]            ; components + 4
    mov ecx, [r15 + VO_CSP]
    mov [rsp + GP_CS], ecx
    lea edx, [rcx + rax]
    cmp edx, VP
    ja .bad
    mov [r15 + VO_CSP], edx
    lea edx, [rax - 4]
    mov [rsp + GP_NCOMP], edx
    xor edx, edx
.stash:
    cmp edx, eax
    jae .stashed
    mov r8d, [rsp + GP_BASE]
    add r8d, edx
    mov r9d, ecx
    add r9d, edx
    shl r9d, 4
    movsd xmm0, [r14 + VX_PX + r8 * 8]
    movsd [r14 + VX_CS + r9], xmm0
    movsd xmm0, [r14 + VX_PY + r8 * 8]
    movsd [r14 + VX_CS + r9 + 8], xmm0
    inc edx
    jmp .stash
.stashed:
    mov eax, [rsp + GP_BASE]
    mov [r15 + VO_N], eax
    mov rax, [rsp + GP_DATA]
    add rax, 10
    mov [rsp + GP_COMP], rax
    mov dword [rsp + GP_K], 0
.component:
    mov eax, [rsp + GP_K]
    cmp eax, [rsp + GP_NCOMP]
    jae .composed
    mov r13, [rsp + GP_COMP]
    BE16 r12d, [r13]                    ; flags
    BE16 edi, [r13 + 2]                 ; its glyph
    mov eax, [r15 + VO_N]
    mov [rsp + GP_CHILD], eax
    mov esi, [rsp + GP_DEPTH]
    inc esi
    call vr_points
    test eax, eax
    jz .bad
    ; USE_MY_METRICS: its phantoms are ours
    mov ecx, [r15 + VO_N]
    test r12d, 0x200
    jz .placed_metrics
    mov edx, [rsp + GP_CS]
    add edx, [rsp + GP_NCOMP]
    shl edx, 4
    xor r8d, r8d
.metrics:
    lea r9d, [rcx + r8 - 4]
    movsd xmm0, [r14 + VX_PX + r9 * 8]
    movsd [r14 + VX_CS + rdx], xmm0
    movsd xmm0, [r14 + VX_PY + r9 * 8]
    movsd [r14 + VX_CS + rdx + 8], xmm0
    add edx, 16
    inc r8d
    cmp r8d, 4
    jb .metrics
.placed_metrics:
    ; its points transformed and placed at the (varied) offset
    mov eax, [rsp + GP_K]
    add eax, [rsp + GP_CS]
    shl eax, 4
    movsd xmm6, [r14 + VX_CS + rax]     ; tx
    movsd xmm7, [r14 + VX_CS + rax + 8] ; ty
    call vr_matrix                      ; -> xmm2 a, xmm3 b, xmm4 c, xmm5 d; rax past the record
    mov [rsp + GP_COMP], rax
    mov edx, [rsp + GP_CHILD]
    mov ecx, [r15 + VO_N]
    sub ecx, 4
.place:
    cmp edx, ecx
    jae .placed
    movsd xmm0, [r14 + VX_PX + rdx * 8]
    movsd xmm1, [r14 + VX_PY + rdx * 8]
    test r12d, 0x800
    jz .transform_first
    addsd xmm0, xmm6                    ; scaled offsets: translate, then transform
    addsd xmm1, xmm7
    call .transform
    jmp .place_put
.transform_first:
    call .transform
    addsd xmm0, xmm6
    addsd xmm1, xmm7
.place_put:
    movsd [r14 + VX_PX + rdx * 8], xmm0
    movsd [r14 + VX_PY + rdx * 8], xmm1
    inc edx
    jmp .place
.placed:
    mov [r15 + VO_N], ecx               ; its phantoms dropped
    inc dword [rsp + GP_K]
    jmp .component
.composed:
    ; our phantoms after the components' points
    mov ecx, [r15 + VO_N]
    lea eax, [rcx + 4]
    cmp eax, VP
    ja .bad
    mov edx, [rsp + GP_CS]
    add edx, [rsp + GP_NCOMP]
    shl edx, 4
    xor r8d, r8d
.ours:
    lea r9d, [rcx + r8]
    movsd xmm0, [r14 + VX_CS + rdx]
    movsd [r14 + VX_PX + r9 * 8], xmm0
    movsd xmm0, [r14 + VX_CS + rdx + 8]
    movsd [r14 + VX_PY + r9 * 8], xmm0
    mov byte [r14 + VX_ON + r9], 0
    mov byte [r14 + VX_END + r9], 0
    add edx, 16
    inc r8d
    cmp r8d, 4
    jb .ours
    mov [r15 + VO_N], eax
    mov eax, [rsp + GP_CS]
    mov [r15 + VO_CSP], eax
.ok:
    mov eax, 1
    jmp .out
.bad:
    xor eax, eax
.out:
    add rsp, GP_SIZE
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret
; xmm0 / xmm1 = x / y -> (a x + c y, b x + d y) (xmm2 .. xmm5)
.transform:
    movsd xmm8, xmm0
    mulsd xmm8, xmm2
    movsd xmm9, xmm1
    mulsd xmm9, xmm4
    addsd xmm8, xmm9
    mulsd xmm0, xmm3
    mulsd xmm1, xmm5
    addsd xmm0, xmm1
    movsd xmm1, xmm0
    movsd xmm0, xmm8
    ret

; vr_matrix — r13 = a component record, r12d = its flags -> xmm2 .. xmm5 =
;   a, b, c, d; rax past the record
vr_matrix:
    lea rax, [r13 + 4]                  ; flags, glyph
    add rax, 2
    test r12d, 1
    jz .args
    add rax, 2
.args:
    mov rcx, 0x3FF0000000000000
    movq xmm2, rcx
    movsd xmm5, xmm2
    xorpd xmm3, xmm3
    xorpd xmm4, xmm4
    test r12d, 8
    jz .xy
    call .f2dot14
    movsd xmm2, xmm0
    movsd xmm5, xmm0
    ret
.xy:
    test r12d, 0x40
    jz .two
    call .f2dot14
    movsd xmm2, xmm0
    call .f2dot14
    movsd xmm5, xmm0
    ret
.two:
    test r12d, 0x80
    jz .out
    call .f2dot14
    movsd xmm2, xmm0
    call .f2dot14
    movsd xmm3, xmm0
    call .f2dot14
    movsd xmm4, xmm0
    call .f2dot14
    movsd xmm5, xmm0
.out:
    ret
.f2dot14:
    movzx ecx, word [rax]
    rol cx, 8
    movsx ecx, cx
    cvtsi2sd xmm0, ecx
    mulsd xmm0, [rel vr_f2dot14]
    add rax, 2
    ret

; vr_hmetrics — edi = glyph, rbx = font -> eax advance, edx left side bearing
vr_hmetrics:
    mov r8, [rbx + UfontFont_hmtx]
    mov r9d, [rbx + UfontFont_nhm]
    xor edx, edx
    cmp edi, r9d
    jae .short
    BE16 eax, [r8 + rdi * 4]
    movzx edx, word [r8 + rdi * 4 + 2]
    rol dx, 8
    movsx edx, dx
    ret
.short:
    BE16 eax, [r8 + r9 * 4 - 4]         ; the last advance
    mov ecx, edi
    sub ecx, r9d
    lea rcx, [rcx * 2]
    lea rcx, [rcx + r9 * 4]
    lea r10, [rcx + 2]
    cmp r10, [rbx + UfontFont_hmtx_len]
    ja .out
    movzx edx, word [r8 + rcx]
    rol dx, 8
    movsx edx, dx
.out:
    ret

; ----------------------------------------------------------------------------
; vr_simple — (vr_points' frame at rsp + 8) r12d = contours, r13 = the
;   glyph's data: its points (doubles), on-curve flags, contour ends
; ----------------------------------------------------------------------------
%define VS          (8 + 8 * 5 + 8)     ; vr_points' frame from here (after our pushes)

vr_simple:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    lea rbp, [rsp + 8 + 40]             ; vr_points' frame
    mov r8, [rbp + GP_DEND]             ; end
    lea rsi, [r13 + 10]                 ; end points
    lea rax, [rsi + r12 * 2 + 2]
    cmp rax, r8
    ja .bad
    BE16 ebx, [rsi + r12 * 2 - 2]
    inc ebx                             ; points
    mov ecx, [r15 + VO_N]
    lea eax, [rcx + rbx + 4]
    cmp eax, VP
    ja .bad
    ; ends
    xor edx, edx
.clear:
    cmp edx, ebx
    jae .ends
    lea eax, [rcx + rdx]
    mov byte [r14 + VX_END + rax], 0
    inc edx
    jmp .clear
.ends:
    xor edx, edx
    xor r9d, r9d                        ; previous end + 1
.end:
    cmp edx, r12d
    jae .instructions
    BE16 eax, [rsi + rdx * 2]
    cmp eax, ebx
    jae .bad
    lea r10d, [rax + 1]
    cmp r10d, r9d
    jb .bad                             ; not increasing
    mov r9d, r10d
    add eax, ecx
    mov byte [r14 + VX_END + rax], 1
    inc edx
    jmp .end
.instructions:
    lea rsi, [rsi + r12 * 2]
    BE16 eax, [rsi]
    lea rsi, [rsi + rax + 2]            ; the flags
    ; flags (with repeats) into ON
    xor edx, edx
.flag:
    cmp edx, ebx
    jae .xs
    cmp rsi, r8
    jae .bad
    movzx eax, byte [rsi]
    inc rsi
    xor r9d, r9d                        ; repeats
    test eax, 8
    jz .flag_put
    cmp rsi, r8
    jae .bad
    movzx r9d, byte [rsi]
    inc rsi
.flag_put:
    lea r10d, [rcx + rdx]
    mov [r14 + VX_ON + r10], al
    inc edx
    test r9d, r9d
    jz .flag
    cmp edx, ebx
    jae .bad
    dec r9d
    jmp .flag_put
.xs:
    ; x: short (2) with sign (16), same (16 without short), else a word
    xor edx, edx
    xor r9d, r9d
.x:
    cmp edx, ebx
    jae .ys
    lea r10d, [rcx + rdx]
    movzx eax, byte [r14 + VX_ON + r10]
    test eax, 2
    jz .x_long
    cmp rsi, r8
    jae .bad
    movzx r11d, byte [rsi]
    inc rsi
    test eax, 16
    jnz .x_add
    neg r11d
    jmp .x_add
.x_long:
    xor r11d, r11d
    test eax, 16
    jnz .x_add
    lea r11, [rsi + 2]
    cmp r11, r8
    ja .bad
    movzx r11d, word [rsi]
    rol r11w, 8
    movsx r11d, r11w
    add rsi, 2
.x_add:
    add r9d, r11d
    cvtsi2sd xmm0, r9d
    movsd [r14 + VX_PX + r10 * 8], xmm0
    inc edx
    jmp .x
.ys:
    xor edx, edx
    xor r9d, r9d
.y:
    cmp edx, ebx
    jae .on
    lea r10d, [rcx + rdx]
    movzx eax, byte [r14 + VX_ON + r10]
    test eax, 4
    jz .y_long
    cmp rsi, r8
    jae .bad
    movzx r11d, byte [rsi]
    inc rsi
    test eax, 32
    jnz .y_add
    neg r11d
    jmp .y_add
.y_long:
    xor r11d, r11d
    test eax, 32
    jnz .y_add
    lea r11, [rsi + 2]
    cmp r11, r8
    ja .bad
    movzx r11d, word [rsi]
    rol r11w, 8
    movsx r11d, r11w
    add rsi, 2
.y_add:
    add r9d, r11d
    cvtsi2sd xmm0, r9d
    movsd [r14 + VX_PY + r10 * 8], xmm0
    inc edx
    jmp .y
.on:
    ; the flags' on-curve bit only
    xor edx, edx
.on1:
    cmp edx, ebx
    jae .done
    lea r10d, [rcx + rdx]
    and byte [r14 + VX_ON + r10], 1
    inc edx
    jmp .on1
.done:
    add [r15 + VO_N], ebx
    mov eax, 1
    jmp .out
.bad:
    xor eax, eax
.out:
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; vr_components — (vr_points' frame at rsp + 8) r13 = the glyph's data: one
;   point per component, its offset (0 when placed by points), each its own
;   contour
vr_components:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    lea rbp, [rsp + 8 + 40]
    mov r8, [rbp + GP_DEND]
    lea rsi, [r13 + 10]
.component:
    lea rax, [rsi + 4]
    cmp rax, r8
    ja .bad
    BE16 ebx, [rsi]                     ; flags
    add rsi, 4
    xor r9d, r9d                        ; tx
    xor r10d, r10d                      ; ty
    test ebx, 1
    jz .bytes
    lea rax, [rsi + 4]
    cmp rax, r8
    ja .bad
    movzx r9d, word [rsi]
    rol r9w, 8
    movsx r9d, r9w
    movzx r10d, word [rsi + 2]
    rol r10w, 8
    movsx r10d, r10w
    add rsi, 4
    jmp .args
.bytes:
    lea rax, [rsi + 2]
    cmp rax, r8
    ja .bad
    movsx r9d, byte [rsi]
    movsx r10d, byte [rsi + 1]
    add rsi, 2
.args:
    test ebx, 2                         ; ARGS_ARE_XY_VALUES, else matched points: 0
    jnz .offset
    xor r9d, r9d
    xor r10d, r10d
.offset:
    mov ecx, [r15 + VO_N]
    lea eax, [rcx + 5]
    cmp eax, VP
    ja .bad
    cvtsi2sd xmm0, r9d
    movsd [r14 + VX_PX + rcx * 8], xmm0
    cvtsi2sd xmm0, r10d
    movsd [r14 + VX_PY + rcx * 8], xmm0
    mov byte [r14 + VX_ON + rcx], 1
    mov byte [r14 + VX_END + rcx], 1
    inc dword [r15 + VO_N]
    ; past the transform
    test ebx, 8
    jz .xy
    add rsi, 2
    jmp .more
.xy:
    test ebx, 0x40
    jz .two
    add rsi, 4
    jmp .more
.two:
    test ebx, 0x80
    jz .more
    add rsi, 8
.more:
    cmp rsi, r8
    ja .bad
    test ebx, 0x20
    jnz .component
    mov eax, 1
    jmp .out
.bad:
    xor eax, eax
.out:
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; ----------------------------------------------------------------------------
; vr_gvar — edi = glyph, esi = its first point, edx = its points (with the
;   phantoms), r15 = state: moved by gvar's tuples at the font's coordinates
; ----------------------------------------------------------------------------
%define GV_GLYPH    0                   ; u32
%define GV_BASE     4
%define GV_N        8
%define GV_TUPLES   12                  ; u32 left
%define GV_SER      16                  ; serialized data
%define GV_HDR      24                  ; the next tuple header
%define GV_END      32                  ; the glyph's data end
%define GV_SHARED   40                  ; u32 shared point numbers (0: all)
%define GV_PEAK     48                  ; F2Dot14 tuples
%define GV_START    56                  ; (0: none)
%define GV_STOP     64
%define GV_SCALAR   72                  ; f64
%define GV_NEXT     80                  ; the next tuple's data
%define GV_M        88                  ; u32 deltas this tuple
%define GV_ALL      92                  ; u32 1: every point
%define GV_DS       96                  ; this tuple's data
%define GV_SIZE     112

vr_gvar:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    sub rsp, GV_SIZE
    mov [rsp + GV_GLYPH], edi
    mov [rsp + GV_BASE], esi
    mov [rsp + GV_N], edx
    mov rbx, [r15 + VO_FONT]
    mov r14, [r15 + VO_X]
    mov r12, [rbx + UfontFont_gvar]
    mov r13, [rbx + UfontFont_gvar_len]
    add r13, r12                        ; the table's end
    lea rax, [r12 + 20]
    cmp rax, r13
    ja .out
    BE16 eax, [r12 + 12]                ; glyphs
    cmp edi, eax
    jae .out
    ; the glyph's variation data
    mov ebp, [r12 + 16]
    bswap ebp                           ; the data array at
    test word [r12 + 14], 0x0100        ; long offsets
    jnz .long
    lea rax, [r12 + rdi * 2 + 24]
    cmp rax, r13
    ja .out
    BE16 eax, [r12 + rdi * 2 + 20]
    BE16 ecx, [r12 + rdi * 2 + 22]
    add eax, eax
    add ecx, ecx
    jmp .located
.long:
    lea rax, [r12 + rdi * 4 + 28]
    cmp rax, r13
    ja .out
    mov eax, [r12 + rdi * 4 + 20]
    bswap eax
    mov ecx, [r12 + rdi * 4 + 24]
    bswap ecx
.located:
    cmp ecx, eax
    jbe .out
    add rax, rbp
    add rcx, rbp
    add rax, r12
    add rcx, r12
    cmp rcx, r13
    ja .out
    mov [rsp + GV_END], rcx
    lea rdx, [rax + 4]
    cmp rdx, rcx
    ja .out
    BE16 ecx, [rax]                     ; tuples | shared points (0x8000)
    mov edx, ecx
    and ecx, 0x0FFF
    mov [rsp + GV_TUPLES], ecx
    BE16 esi, [rax + 2]
    add rsi, rax
    mov [rsp + GV_SER], rsi
    lea rcx, [rax + 4]
    mov [rsp + GV_HDR], rcx
    ; the deltas summed: 0
    mov ecx, [rsp + GV_BASE]
    mov r8d, [rsp + GV_N]
    xorpd xmm0, xmm0
.zero:
    test r8d, r8d
    jz .zeroed
    movsd [r14 + VX_SX + rcx * 8], xmm0
    movsd [r14 + VX_SY + rcx * 8], xmm0
    inc ecx
    dec r8d
    jmp .zero
.zeroed:
    mov dword [rsp + GV_SHARED], 0
    test edx, 0x8000
    jz .tuple
    mov rsi, [rsp + GV_SER]
    mov rdx, [rsp + GV_END]
    lea rdi, [r14 + VX_SIDX]
    call vr_point_numbers
    jc .out
    mov [rsp + GV_SER], rsi
    mov [rsp + GV_SHARED], eax
.tuple:
    cmp dword [rsp + GV_TUPLES], 0
    je .apply
    dec dword [rsp + GV_TUPLES]
    mov rsi, [rsp + GV_HDR]
    lea rax, [rsi + 4]
    cmp rax, [rsp + GV_END]
    ja .apply
    BE16 r8d, [rsi]                     ; data size
    BE16 r9d, [rsi + 2]                 ; tuple index
    add rsi, 4
    BE16 r10d, [r12 + 4]                ; axes
    test r9d, 0x8000
    jz .shared_peak
    mov [rsp + GV_PEAK], rsi
    lea rsi, [rsi + r10 * 2]
    jmp .intermediate
.shared_peak:
    mov eax, r9d
    and eax, 0x0FFF
    mov qword [rsp + GV_PEAK], 0        ; (out of range: this tuple counts 0)
    BE16 ecx, [r12 + 6]                 ; shared tuples
    cmp eax, ecx
    jae .intermediate
    mov ecx, [r12 + 8]
    bswap ecx
    imul eax, r10d
    lea rax, [rcx + rax * 2]
    add rax, r12
    lea rcx, [rax + r10 * 2]
    cmp rcx, r13
    ja .intermediate
    mov [rsp + GV_PEAK], rax
.intermediate:
    mov qword [rsp + GV_START], 0
    test r9d, 0x4000
    jz .header_done
    mov [rsp + GV_START], rsi
    lea rax, [rsi + r10 * 2]
    mov [rsp + GV_STOP], rax
    lea rsi, [rsi + r10 * 4]
.header_done:
    mov [rsp + GV_HDR], rsi
    cmp rsi, [rsp + GV_END]
    ja .apply
    ; this tuple's data
    mov rax, [rsp + GV_SER]
    mov [rsp + GV_DS], rax
    lea rcx, [rax + r8]
    cmp rcx, [rsp + GV_END]
    ja .apply
    mov [rsp + GV_NEXT], rcx
    mov [rsp + GV_SER], rcx
    push r9
    push r10
    call vr_scalar                      ; -> xmm0
    pop r10
    pop r9
    movsd [rsp + GV_SCALAR], xmm0
    xorpd xmm1, xmm1
    ucomisd xmm0, xmm1
    je .tuple
    ; its point numbers, own or shared
    mov rsi, [rsp + GV_DS]
    lea r11, [r14 + VX_SIDX]
    mov eax, [rsp + GV_SHARED]
    test r9d, 0x2000
    jz .numbers
    mov rdx, [rsp + GV_NEXT]
    lea rdi, [r14 + VX_IDX]
    call vr_point_numbers
    jc .tuple
    lea r11, [r14 + VX_IDX]
.numbers:
    mov ebp, eax                        ; count (0: every point)
    xor ecx, ecx
    test ebp, ebp
    setz cl
    mov [rsp + GV_ALL], ecx
    jz .every
    mov [rsp + GV_M], ebp
    jmp .deltas
.every:
    mov eax, [rsp + GV_N]
    mov [rsp + GV_M], eax
.deltas:
    push r11
    sub rsp, 8
    mov rdx, [rsp + 16 + GV_NEXT]
    mov ecx, [rsp + 16 + GV_M]
    lea rdi, [r14 + VX_DX]
    call vr_deltas
    jc .deltas_bad
    mov rdx, [rsp + 16 + GV_NEXT]
    mov ecx, [rsp + 16 + GV_M]
    lea rdi, [r14 + VX_DY]
    call vr_deltas
    jc .deltas_bad
    add rsp, 8
    pop r11
    movsd xmm2, [rsp + GV_SCALAR]
    cmp dword [rsp + GV_ALL], 0
    je .named
    ; every point: straight into the sums
    mov ecx, [rsp + GV_BASE]
    xor edx, edx
.all:
    cmp edx, [rsp + GV_N]
    jae .tuple
    cvtsi2sd xmm0, dword [r14 + VX_DX + rdx * 4]
    mulsd xmm0, xmm2
    lea eax, [rcx + rdx]
    addsd xmm0, [r14 + VX_SX + rax * 8]
    movsd [r14 + VX_SX + rax * 8], xmm0
    cvtsi2sd xmm0, dword [r14 + VX_DY + rdx * 4]
    mulsd xmm0, xmm2
    addsd xmm0, [r14 + VX_SY + rax * 8]
    movsd [r14 + VX_SY + rax * 8], xmm0
    inc edx
    jmp .all
.deltas_bad:
    add rsp, 8
    pop r11
    jmp .tuple
.named:
    ; the named points' deltas, then the others interpolated
    mov ecx, [rsp + GV_BASE]
    xor edx, edx
    xorpd xmm0, xmm0
.clear:
    cmp edx, [rsp + GV_N]
    jae .cleared
    lea eax, [rcx + rdx]
    movsd [r14 + VX_TX + rax * 8], xmm0
    movsd [r14 + VX_TY + rax * 8], xmm0
    mov byte [r14 + VX_NAMED + rax], 0
    inc edx
    jmp .clear
.cleared:
    xor edx, edx
.name:
    cmp edx, [rsp + GV_M]
    jae .iup
    mov eax, [r11 + rdx * 4]            ; the point
    cmp eax, [rsp + GV_N]
    jae .name_next
    add eax, ecx
    cvtsi2sd xmm0, dword [r14 + VX_DX + rdx * 4]
    mulsd xmm0, xmm2
    addsd xmm0, [r14 + VX_TX + rax * 8]
    movsd [r14 + VX_TX + rax * 8], xmm0
    cvtsi2sd xmm0, dword [r14 + VX_DY + rdx * 4]
    mulsd xmm0, xmm2
    addsd xmm0, [r14 + VX_TY + rax * 8]
    movsd [r14 + VX_TY + rax * 8], xmm0
    mov byte [r14 + VX_NAMED + rax], 1
.name_next:
    inc edx
    jmp .name
.iup:
    mov edi, [rsp + GV_BASE]
    mov esi, [rsp + GV_N]
    call vr_iup
    ; into the sums
    mov ecx, [rsp + GV_BASE]
    xor edx, edx
.sum:
    cmp edx, [rsp + GV_N]
    jae .tuple
    lea eax, [rcx + rdx]
    movsd xmm0, [r14 + VX_SX + rax * 8]
    addsd xmm0, [r14 + VX_TX + rax * 8]
    movsd [r14 + VX_SX + rax * 8], xmm0
    movsd xmm0, [r14 + VX_SY + rax * 8]
    addsd xmm0, [r14 + VX_TY + rax * 8]
    movsd [r14 + VX_SY + rax * 8], xmm0
    inc edx
    jmp .sum
.apply:
    ; the points moved
    mov ecx, [rsp + GV_BASE]
    xor edx, edx
.move:
    cmp edx, [rsp + GV_N]
    jae .out
    lea eax, [rcx + rdx]
    movsd xmm0, [r14 + VX_PX + rax * 8]
    addsd xmm0, [r14 + VX_SX + rax * 8]
    movsd [r14 + VX_PX + rax * 8], xmm0
    movsd xmm0, [r14 + VX_PY + rax * 8]
    addsd xmm0, [r14 + VX_SY + rax * 8]
    movsd [r14 + VX_PY + rax * 8], xmm0
    inc edx
    jmp .move
.out:
    add rsp, GV_SIZE
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; vr_scalar — (vr_gvar's frame at rsp + 8 + 16) r10d = axes, rbx = font ->
;   xmm0 the tuple's scalar (f64)
%define SC (8 + 16)
vr_scalar:
    xorpd xmm0, xmm0
    mov r8, [rsp + SC + GV_PEAK]
    test r8, r8
    jz .out
    mov r9, [rsp + SC + GV_START]
    mov rax, [rbx + UfontFont_coords]
    mov rcx, 0x3FF0000000000000
    movq xmm0, rcx                      ; 1.0
    xor ecx, ecx
.axis:
    cmp ecx, r10d
    jae .out
    movzx edx, word [r8 + rcx * 2]
    rol dx, 8
    movsx edx, dx                       ; peak
    test edx, edx
    jz .next
    xor esi, esi                        ; the coordinate
    cmp ecx, [rbx + UfontFont_naxes]
    jae .v
    mov esi, [rax + rcx * 4]
.v:
    test esi, esi
    jz .zero
    cmp esi, edx
    je .next
    test r9, r9
    jz .peak_only
    ; intermediate: start, end
    movzx edi, word [r9 + rcx * 2]
    rol di, 8
    movsx edi, di                       ; start
    mov r11, [rsp + SC + GV_STOP]
    push rax
    movzx eax, word [r11 + rcx * 2]
    rol ax, 8
    cwde                                ; end
    mov r11d, eax
    pop rax
    cmp edi, edx
    jg .next
    cmp edx, r11d
    jg .next
    test edi, edi
    jns .ranged
    test r11d, r11d
    jg .next
.ranged:
    cmp esi, edi
    jl .zero
    cmp esi, r11d
    jg .zero
    cmp esi, edx
    jge .falling
    cmp edx, edi
    je .next
    sub esi, edi
    cvtsi2sd xmm1, esi
    sub edx, edi
    cvtsi2sd xmm2, edx
    jmp .factor
.falling:
    cmp edx, r11d
    je .next
    mov edi, r11d
    sub edi, esi
    cvtsi2sd xmm1, edi
    sub r11d, edx
    cvtsi2sd xmm2, r11d
    jmp .factor
.peak_only:
    ; v within 0 .. peak
    xor edi, edi
    cmp edx, 0
    jl .neg_peak
    cmp esi, edi
    jl .zero
    cmp esi, edx
    jg .zero
    jmp .ratio
.neg_peak:
    cmp esi, edx
    jl .zero
    cmp esi, edi
    jg .zero
.ratio:
    cvtsi2sd xmm1, esi
    cvtsi2sd xmm2, edx
.factor:
    divsd xmm1, xmm2
    mulsd xmm0, xmm1
.next:
    inc ecx
    jmp .axis
.zero:
    xorpd xmm0, xmm0
.out:
    ret

; vr_point_numbers — rsi = packed point numbers, rdx = end, rdi = u32 out
;   -> eax count (0: every point), rsi past them (CF: damaged)
vr_point_numbers:
    cmp rsi, rdx
    jae .bad
    movzx eax, byte [rsi]
    inc rsi
    test eax, 0x80
    jz .count
    cmp rsi, rdx
    jae .bad
    and eax, 0x7F
    shl eax, 8
    movzx ecx, byte [rsi]
    or eax, ecx
    inc rsi
.count:
    cmp eax, VP
    ja .bad
    push rbx
    xor r8d, r8d                        ; got
    xor r9d, r9d                        ; the last number
.run:
    cmp r8d, eax
    jae .done
    cmp rsi, rdx
    jae .bad_pop
    movzx ecx, byte [rsi]
    inc rsi
    mov ebx, ecx
    and ecx, 0x7F
    inc ecx                             ; run
.value:
    test ebx, 0x80
    jz .byte
    lea r10, [rsi + 2]
    cmp r10, rdx
    ja .bad_pop
    movzx r10d, word [rsi]
    rol r10w, 8
    add rsi, 2
    jmp .add
.byte:
    cmp rsi, rdx
    jae .bad_pop
    movzx r10d, byte [rsi]
    inc rsi
.add:
    add r9d, r10d
    cmp r8d, eax
    jae .done_extra                     ; (a run past the count: read, not kept)
    mov [rdi + r8 * 4], r9d
    inc r8d
.done_extra:
    dec ecx
    jnz .value
    jmp .run
.done:
    pop rbx
    clc
    ret
.bad_pop:
    pop rbx
.bad:
    xor eax, eax
    stc
    ret

; vr_deltas — rsi = packed deltas, rdx = end, ecx = how many, rdi = i32 out
;   -> rsi past them (CF: damaged)
vr_deltas:
    push rbx
    xor r8d, r8d
.run:
    cmp r8d, ecx
    jae .done
    cmp rsi, rdx
    jae .bad
    movzx ebx, byte [rsi]
    inc rsi
    mov r9d, ebx
    and r9d, 0x3F
    inc r9d                             ; run
    and ebx, 0xC0
.value:
    xor eax, eax
    cmp ebx, 0x80
    je .put                             ; zeros
    cmp ebx, 0x40
    je .word
    cmp ebx, 0xC0
    je .long
    cmp rsi, rdx
    jae .bad
    movsx eax, byte [rsi]
    inc rsi
    jmp .put
.word:
    lea r10, [rsi + 2]
    cmp r10, rdx
    ja .bad
    movzx eax, word [rsi]
    rol ax, 8
    cwde
    add rsi, 2
    jmp .put
.long:
    lea r10, [rsi + 4]
    cmp r10, rdx
    ja .bad
    mov eax, [rsi]
    bswap eax
    add rsi, 4
.put:
    cmp r8d, ecx
    jae .extra
    mov [rdi + r8 * 4], eax
.extra:
    inc r8d
    dec r9d
    jnz .value
    jmp .run
.done:
    pop rbx
    clc
    ret
.bad:
    pop rbx
    stc
    ret

; vr_iup — edi = the glyph's first point, esi = its points (with the four
;   phantoms, which are in no contour), r14 = scratch: the points a tuple
;   did not name take deltas from the named ones around them in their
;   contour (TX / TY, NAMED)
vr_iup:
    push rbx
    push rbp
    push r12
    push r13
    push r15
    mov r12d, edi                       ; base
    lea r13d, [rdi + rsi - 4]           ; past the last real point
    mov ebx, r12d                       ; contour start
.contour:
    cmp ebx, r13d
    jae .out
    mov ebp, ebx                        ; its end
.find_end:
    cmp ebp, r13d
    jae .out                            ; (no end: none left)
    cmp byte [r14 + VX_END + rbp], 0
    jne .have_end
    inc ebp
    jmp .find_end
.have_end:
    ; named in it: none or all -> nothing to do
    xor ecx, ecx
    mov edx, ebx
.count:
    cmp edx, ebp
    ja .counted
    movzx eax, byte [r14 + VX_NAMED + rdx]
    add ecx, eax
    inc edx
    jmp .count
.counted:
    test ecx, ecx
    jz .next_contour
    mov eax, ebp
    sub eax, ebx
    inc eax
    cmp ecx, eax
    je .next_contour
    ; each unnamed point
    mov r15d, ebx
.point:
    cmp r15d, ebp
    ja .next_contour
    cmp byte [r14 + VX_NAMED + r15], 0
    jne .point_next
    ; prev: back around the contour to a named point; next: on
    mov r8d, r15d
.prev:
    cmp r8d, ebx
    ja .prev_dec
    mov r8d, ebp
    jmp .prev_test
.prev_dec:
    dec r8d
.prev_test:
    cmp byte [r14 + VX_NAMED + r8], 0
    je .prev
    mov r9d, r15d
.next:
    cmp r9d, ebp
    jb .next_inc
    mov r9d, ebx
    jmp .next_test
.next_inc:
    inc r9d
.next_test:
    cmp byte [r14 + VX_NAMED + r9], 0
    je .next
    ; x, then y
    lea rdi, [r14 + VX_PX]
    lea rsi, [r14 + VX_TX]
    call .infer
    lea rdi, [r14 + VX_PY]
    lea rsi, [r14 + VX_TY]
    call .infer
.point_next:
    inc r15d
    jmp .point
.next_contour:
    lea ebx, [rbp + 1]
    jmp .contour
.out:
    pop r15
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret
; rdi = coordinates, rsi = deltas; r15d = target, r8d = prev, r9d = next
.infer:
    movsd xmm0, [rdi + r15 * 8]         ; t
    movsd xmm1, [rdi + r8 * 8]          ; pv
    movsd xmm2, [rdi + r9 * 8]          ; nv
    movsd xmm3, [rsi + r8 * 8]          ; pd
    movsd xmm4, [rsi + r9 * 8]          ; nd
    ucomisd xmm1, xmm2
    jne .unequal
    xorpd xmm5, xmm5
    ucomisd xmm3, xmm4
    jne .put5
    movsd xmm5, xmm3
    jmp .put5
.unequal:
    movsd xmm6, xmm1
    minsd xmm6, xmm2                    ; min
    ucomisd xmm0, xmm6
    ja .not_below
    ; t <= min: the delta of the lower one
    movsd xmm5, xmm3
    ucomisd xmm1, xmm2
    jb .put5
    movsd xmm5, xmm4
    jmp .put5
.not_below:
    movsd xmm6, xmm1
    maxsd xmm6, xmm2
    ucomisd xmm0, xmm6
    jb .between
    movsd xmm5, xmm3                    ; t >= max: of the higher one
    ucomisd xmm1, xmm2
    ja .put5
    movsd xmm5, xmm4
    jmp .put5
.between:
    subsd xmm0, xmm1                    ; (t - pv) / (nv - pv) * (nd - pd) + pd
    movsd xmm6, xmm2
    subsd xmm6, xmm1
    divsd xmm0, xmm6
    movsd xmm6, xmm4
    subsd xmm6, xmm3
    mulsd xmm0, xmm6
    movsd xmm5, xmm3
    addsd xmm5, xmm0
.put5:
    movsd [rsi + r15 * 8], xmm5
    ret

; ----------------------------------------------------------------------------
; vr_draw — r15 = state: the gathered points' contours drawn (each starts on
;   its first point on the curve, else its last, else the middle of the
;   two; two points off the curve in a row imply the one between them)
; ----------------------------------------------------------------------------
%define DR_START    0                   ; f64 x, y: the contour's start
%define DR_CTRL     16                  ; f64 x, y: the pending control point
%define DR_HAS      32                  ; u32 one is pending
%define DR_N        36                  ; u32 the real points
%define DR_P        40                  ; f64 x, y: the point at hand
%define DR_SIZE     64

vr_draw:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    sub rsp, DR_SIZE
    mov r14, [r15 + VO_X]
    mov eax, [r15 + VO_N]
    sub eax, 4
    mov [rsp + DR_N], eax
    xor ebx, ebx                        ; contour start
.contour:
    cmp ebx, [rsp + DR_N]
    jae .out
    mov ebp, ebx
.find_end:
    cmp ebp, [rsp + DR_N]
    jae .out
    cmp byte [r14 + VX_END + rbp], 0
    jne .have_end
    inc ebp
    jmp .find_end
.have_end:
    mov r12d, ebx                       ; the sequence: r12d .. r13d
    mov r13d, ebp
    cmp byte [r14 + VX_ON + rbx], 0
    je .first_off
    movsd xmm0, [r14 + VX_PX + rbx * 8]
    movsd xmm1, [r14 + VX_PY + rbx * 8]
    inc r12d
    jmp .start
.first_off:
    cmp byte [r14 + VX_ON + rbp], 0
    je .both_off
    movsd xmm0, [r14 + VX_PX + rbp * 8]
    movsd xmm1, [r14 + VX_PY + rbp * 8]
    dec r13d
    jmp .start
.both_off:
    movsd xmm0, [r14 + VX_PX + rbp * 8]
    addsd xmm0, [r14 + VX_PX + rbx * 8]
    mulsd xmm0, [rel vr_half]
    movsd xmm1, [r14 + VX_PY + rbp * 8]
    addsd xmm1, [r14 + VX_PY + rbx * 8]
    mulsd xmm1, [rel vr_half]
.start:
    movsd [rsp + DR_START], xmm0
    movsd [rsp + DR_START + 8], xmm1
    mov dword [rsp + DR_HAS], 0
    call .sc
    mov rdi, [r15 + VO_PATH]
    call ugfx_path_move_to
    call .err
.seq:
    cmp r12d, r13d
    jg .end_contour
    movsd xmm0, [r14 + VX_PX + r12 * 8]
    movsd xmm1, [r14 + VX_PY + r12 * 8]
    movsd [rsp + DR_P], xmm0
    movsd [rsp + DR_P + 8], xmm1
    cmp byte [r14 + VX_ON + r12], 0
    je .off
    cmp dword [rsp + DR_HAS], 0
    je .line
    call .quad                          ; to the point
    mov dword [rsp + DR_HAS], 0
    jmp .seq_next
.line:
    call .sc
    mov rdi, [r15 + VO_PATH]
    call ugfx_path_line_to
    call .err
    jmp .seq_next
.off:
    cmp dword [rsp + DR_HAS], 0
    je .pend
    ; the quad to the middle of the two, this one pending
    addsd xmm0, [rsp + DR_CTRL]
    mulsd xmm0, [rel vr_half]
    addsd xmm1, [rsp + DR_CTRL + 8]
    mulsd xmm1, [rel vr_half]
    call .quad
.pend:
    movsd xmm0, [rsp + DR_P]
    movsd xmm1, [rsp + DR_P + 8]
    movsd [rsp + DR_CTRL], xmm0
    movsd [rsp + DR_CTRL + 8], xmm1
    mov dword [rsp + DR_HAS], 1
.seq_next:
    inc r12d
    jmp .seq
.end_contour:
    cmp dword [rsp + DR_HAS], 0
    je .close
    movsd xmm0, [rsp + DR_START]
    movsd xmm1, [rsp + DR_START + 8]
    call .quad
.close:
    mov rdi, [r15 + VO_PATH]
    call ugfx_path_close
    call .err
    lea ebx, [rbp + 1]
    jmp .contour
.out:
    add rsp, DR_SIZE
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret
; xmm0 / xmm1 = a point -> at scale, y down (no stack)
.sc:
    mulsd xmm0, [r15 + VO_SCALE]
    mulsd xmm1, [r15 + VO_SCALE]
    xorpd xmm7, xmm7
    subsd xmm7, xmm1
    movsd xmm1, xmm7
    ret
.err:
    test rax, rax
    jz .err_out
    cmp qword [r15 + VO_ERR], 0
    jne .err_out
    mov [r15 + VO_ERR], rax
.err_out:
    ret
; the quad from the pending control point to xmm0 / xmm1 (frame at rsp + 8)
.quad:
    call .sc
    movsd xmm2, xmm0
    movsd xmm3, xmm1
    movsd xmm0, [rsp + 8 + DR_CTRL]
    movsd xmm1, [rsp + 8 + DR_CTRL + 8]
    call .sc
    mov rdi, [r15 + VO_PATH]
    sub rsp, 8
    call ugfx_path_quad_to
    add rsp, 8
    jmp .err
