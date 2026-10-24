; =============================================================================
; Utkarsha OS — lib/ugfx/2d/uic.asm
; =============================================================================
; UIC icon packs (docs/UIC.md): open (validate), find by name and pixel
; size, draw onto a context.
;
;   ugfx_uic_open(uic, arena, data, size)
;   ugfx_uic_find(uic, name, length, pixels)            -> icon or -1
;   ugfx_uic_draw(uic, icon, ctx, colours, count, x, y, size, weight)
;
; Opening checks everything (header, index bounds and order, every body's
; commands and operands), so drawing never reads outside the pack. The
; pack's bytes are used in place and must stay valid while it is open.
; =============================================================================

%include "ugfx.inc"

extern ugfx_path_init
extern ugfx_path_reset
extern ugfx_path_move_to
extern ugfx_path_line_to
extern ugfx_path_quad_to
extern ugfx_path_cubic_to
extern ugfx_path_close
extern ugfx_ctx_save
extern ugfx_ctx_restore
extern ugfx_ctx_translate
extern ugfx_ctx_scale
extern ugfx_ctx_set_fill_color
extern ugfx_ctx_set_stroke_color
extern ugfx_ctx_set_fill_rule
extern ugfx_ctx_set_stroke_style
extern ugfx_ctx_set_dash
extern ugfx_ctx_set_alpha
extern ugfx_ctx_fill
extern ugfx_ctx_stroke

%define UIC_MAGIC       0x1A434955      ; "UIC", 0x1A
%define UIC_HEADER      32
%define UIC_ENTRY       16
%define UIC_BODY_FIXED  20

%define UOP_END         0x00
%define UOP_MOVE        0x01
%define UOP_LINE        0x02
%define UOP_QUAD        0x03
%define UOP_CUBIC       0x04
%define UOP_CLOSE       0x05
%define UOP_FILL        0x10
%define UOP_STROKE      0x11
%define UOP_OPACITY     0x20

section .rodata
align 8
uic_f32_max:        dd 0x7F7FFFFF       ; largest finite float
uic_half:           dq 0.5
uic_one:            dq 1.0
uic_four:           dq 4.0
align 16
uic_abs_mask_f:     dd 0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF

section .text

; -----------------------------------------------------------------------------
; ugfx_uic_open — rdi = UgfxUic*, rsi = arena (for the drawing path),
;   rdx = pack bytes, rcx = byte count -> rax = 0, -EINVAL, -ENOMEM
; -----------------------------------------------------------------------------
global ugfx_uic_open
ugfx_uic_open:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 8
    mov rbx, rdi
    mov rax, -(EINVAL)
    test rdi, rdi
    jz .open_out
    test rsi, rsi
    jz .open_out
    test rdx, rdx
    jz .open_out
    cmp rcx, UIC_HEADER
    jb .open_out
    cmp dword [rdx], UIC_MAGIC
    jne .open_out
    cmp word [rdx + 4], 1
    jne .open_out
    cmp word [rdx + 6], 0
    jne .open_out
    mov [rbx + UgfxUic_data], rdx
    mov [rbx + UgfxUic_size], rcx
    mov [rbx + UgfxUic_arena], rsi
    mov r12, rdx                        ; pack
    mov r13, rcx                        ; size
    ; index: offset aligned, n * 16 bytes inside
    mov eax, [r12 + 8]
    mov [rbx + UgfxUic_count], eax
    mov r8d, [r12 + 12]
    test r8d, 3
    jnz .open_bad
    mov r9, rax
    shl r9, 4
    add r9, r8
    cmp r9, r13
    ja .open_bad
    lea rax, [r12 + r8]
    mov [rbx + UgfxUic_index], rax
    ; string table and data inside
    mov r8d, [r12 + 16]
    mov r9d, [r12 + 20]
    add r9, r8
    cmp r9, r13
    ja .open_bad
    lea rax, [r12 + r8]
    mov [rbx + UgfxUic_strings], rax
    mov r8d, [r12 + 24]
    mov r9d, [r12 + 28]
    add r9, r8
    cmp r9, r13
    ja .open_bad
    lea rax, [r12 + r8]
    mov [rbx + UgfxUic_bodies], rax
    ; every entry
    xor r14d, r14d
.open_entry:
    cmp r14d, [rbx + UgfxUic_count]
    jae .open_path
    mov r15, r14
    shl r15, 4
    add r15, [rbx + UgfxUic_index]      ; entry
    movzx eax, word [r15 + 12]          ; name length
    test eax, eax
    jz .open_bad
    mov ecx, [r15]
    add rax, rcx
    mov ecx, [r12 + 20]
    cmp rax, rcx
    ja .open_bad
    mov eax, [r15 + 4]
    mov ecx, [r15 + 8]
    add rax, rcx
    mov ecx, [r12 + 28]
    cmp rax, rcx
    ja .open_bad
    mov esi, [r15 + 4]
    add rsi, [rbx + UgfxUic_bodies]
    mov ecx, [r15 + 8]
    call uic_check_body
    test eax, eax
    jnz .open_bad
    ; strictly after the previous entry
    test r14d, r14d
    jz .open_next
    lea rdi, [r15 - UIC_ENTRY]
    mov rsi, r15
    call uic_compare_entries
    test eax, eax
    jns .open_bad
.open_next:
    inc r14d
    jmp .open_entry
.open_path:
    lea rdi, [rbx + UgfxUic_path]
    mov rsi, [rbx + UgfxUic_arena]
    call ugfx_path_init
    jmp .open_out
.open_bad:
    mov rax, -(EINVAL)
.open_out:
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15

; rbx = uic, rdi / rsi = entries -> eax < 0, 0, > 0 (name, then design size)
uic_compare_entries:
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    mov rdi, [rbx + UgfxUic_strings]
    mov eax, [r12]
    lea rdi, [rdi + rax]
    movzx edx, word [r12 + 12]
    mov rsi, [rbx + UgfxUic_strings]
    mov eax, [r13]
    lea rsi, [rsi + rax]
    movzx ecx, word [r13 + 12]
    call uic_compare_names
    test eax, eax
    jnz .ce_out
    movzx eax, word [r12 + 14]
    movzx ecx, word [r13 + 14]
    sub eax, ecx
.ce_out:
    pop r13
    pop r12
    ret

; rdi, edx = name a; rsi, ecx = name b -> eax < 0, 0, > 0 (bytes unsigned,
;   a prefix first)
uic_compare_names:
    xor r8d, r8d
.cn_byte:
    cmp r8d, edx
    jae .cn_a_done
    cmp r8d, ecx
    jae .cn_greater                     ; b is a prefix of a
    movzx eax, byte [rdi + r8]
    movzx r9d, byte [rsi + r8]
    sub eax, r9d
    jnz .cn_out
    inc r8d
    jmp .cn_byte
.cn_a_done:
    xor eax, eax
    cmp r8d, ecx
    je .cn_out
    mov eax, -1                         ; a is a prefix of b
    ret
.cn_greater:
    mov eax, 1
.cn_out:
    ret

; rsi = body, ecx = body size -> eax = 0 or -EINVAL
uic_check_body:
    cmp ecx, UIC_BODY_FIXED
    jb .cb_bad
    ; viewBox: finite, width and height > 0
    xor eax, eax
.cb_vb:
    movss xmm1, [rsi + rax * 4]
    andps xmm1, [rel uic_abs_mask_f]
    ucomiss xmm1, [rel uic_f32_max]
    jp .cb_bad
    ja .cb_bad
    inc eax
    cmp eax, 4
    jb .cb_vb
    xorps xmm1, xmm1
    movss xmm0, [rsi + 8]
    ucomiss xmm0, xmm1
    jbe .cb_bad
    movss xmm0, [rsi + 12]
    ucomiss xmm0, xmm1
    jbe .cb_bad
    cmp byte [rsi + 16], 14
    ja .cb_bad
    movzx r9d, byte [rsi + 17]          ; slots
    test r9d, r9d
    jz .cb_bad
    cmp r9d, 16
    ja .cb_bad
    cmp word [rsi + 18], 0
    jne .cb_bad
    lea r8d, [r9 * 4 + UIC_BODY_FIXED]  ; first command
    cmp r8d, ecx
    ja .cb_bad
.cb_command:
    cmp r8d, ecx
    jae .cb_bad                         ; no END
    movzx eax, byte [rsi + r8]
    inc r8d
    cmp eax, UOP_END
    je .cb_ok
    mov edx, 4
    cmp eax, UOP_MOVE
    je .cb_operands
    cmp eax, UOP_LINE
    je .cb_operands
    mov edx, 8
    cmp eax, UOP_QUAD
    je .cb_operands
    mov edx, 12
    cmp eax, UOP_CUBIC
    je .cb_operands
    xor edx, edx
    cmp eax, UOP_CLOSE
    je .cb_operands
    mov edx, 1
    cmp eax, UOP_OPACITY
    je .cb_operands
    cmp eax, UOP_FILL
    je .cb_fill
    cmp eax, UOP_STROKE
    je .cb_stroke
    jmp .cb_bad
.cb_fill:
    lea eax, [r8 + 2]
    cmp eax, ecx
    ja .cb_bad
    movzx eax, byte [rsi + r8]
    cmp eax, r9d
    jae .cb_bad
    cmp byte [rsi + r8 + 1], UGFX_FILL_EVENODD
    ja .cb_bad
    add r8d, 2
    jmp .cb_command
.cb_stroke:
    lea eax, [r8 + 4]
    cmp eax, ecx
    ja .cb_bad
    movzx eax, byte [rsi + r8]
    cmp eax, r9d
    jae .cb_bad
    movzx eax, byte [rsi + r8 + 1]
    mov edx, eax
    and eax, 15
    cmp eax, UGFX_JOIN_BEVEL
    ja .cb_bad
    shr edx, 4
    cmp edx, UGFX_CAP_SQUARE
    ja .cb_bad
    cmp word [rsi + r8 + 2], 0
    jle .cb_bad                         ; width > 0 (signed)
    add r8d, 4
    jmp .cb_command
.cb_operands:
    lea eax, [r8 + rdx]
    cmp eax, ecx
    ja .cb_bad
    add r8d, edx
    jmp .cb_command
.cb_ok:
    xor eax, eax
    ret
.cb_bad:
    mov eax, -(EINVAL)
    ret

; -----------------------------------------------------------------------------
; ugfx_uic_find — rdi = const UgfxUic*, rsi = name, edx = length,
;   ecx = pixel size -> rax = icon index, or -1 if the name is absent.
;   Among the name's entries: pixels 0 asks for the scalable one (or the
;   largest without one); otherwise the smallest design size >= pixels,
;   failing that the scalable one (0), else the largest.
; -----------------------------------------------------------------------------
global ugfx_uic_find
ugfx_uic_find:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov [rsp], ecx
    mov rax, -1
    test rdi, rdi
    jz .find_out
    ; lower bound: first entry whose name >= the key
    xor r14d, r14d                      ; lo
    mov r15d, [rbx + UgfxUic_count]     ; hi
.find_bisect:
    cmp r14d, r15d
    jae .find_found_lo
    lea eax, [r14 + r15]
    shr eax, 1
    push rax
    sub rsp, 8
    mov ecx, eax
    call uic_compare_key
    add rsp, 8
    pop rcx
    test eax, eax
    jns .find_upper
    lea r14d, [rcx + 1]                 ; entry < key
    jmp .find_bisect
.find_upper:
    mov r15d, ecx
    jmp .find_bisect
.find_found_lo:
    mov rax, -1
    cmp r14d, [rbx + UgfxUic_count]
    jae .find_out
    mov ecx, r14d
    call uic_compare_key
    test eax, eax
    mov rax, -1
    jnz .find_out
    ; the run of equal names: r14d .. r15d (exclusive)
    mov r15d, r14d
.find_run:
    inc r15d
    cmp r15d, [rbx + UgfxUic_count]
    jae .find_pick
    mov ecx, r15d
    call uic_compare_key
    test eax, eax
    jz .find_run
.find_pick:
    ; sorted by design size: the scalable entry (0) comes first
    mov r8d, -1                         ; scalable entry
    mov rax, r14
    shl rax, 4
    add rax, [rbx + UgfxUic_index]
    cmp word [rax + 14], 0
    jne .find_no_scalable
    mov r8d, r14d
    cmp dword [rsp], 0
    je .find_fallback                   ; pixels 0: the scalable one
.find_no_scalable:
    cmp dword [rsp], 0
    je .find_fallback                   ; pixels 0, no scalable entry: the largest
    ; first non-zero design size >= pixels
    mov ecx, r14d
.find_scan:
    cmp ecx, r15d
    jae .find_fallback
    mov rax, rcx
    shl rax, 4
    add rax, [rbx + UgfxUic_index]
    movzx edx, word [rax + 14]
    test edx, edx
    jnz .find_sized
    mov r8d, ecx
    jmp .find_scan_next
.find_sized:
    cmp edx, [rsp]
    jae .find_this
.find_scan_next:
    inc ecx
    jmp .find_scan
.find_this:
    mov eax, ecx
    jmp .find_out
.find_fallback:
    movsxd rax, r8d
    cmp r8d, -1
    jne .find_out
    lea eax, [r15 - 1]                  ; the largest
.find_out:
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15

; ecx = entry index, rbx = uic, r12 / r13d = key -> eax = entry name vs key
uic_compare_key:
    sub rsp, 8
    mov rax, rcx
    shl rax, 4
    add rax, [rbx + UgfxUic_index]
    mov rdi, [rbx + UgfxUic_strings]
    mov edx, [rax]
    add rdi, rdx
    movzx edx, word [rax + 12]
    mov rsi, r12
    mov ecx, r13d
    call uic_compare_names
    add rsp, 8
    ret

; -----------------------------------------------------------------------------
; ugfx_uic_draw — rdi = const UgfxUic*, esi = icon, rdx = UgfxContext*,
;   rcx = const u32 colours[] (straight BGRA) or 0, r8d = colours given,
;   xmm0 = x, xmm1 = y, xmm2 = size (user space), xmm3 = stroke weight
;   (<= 0 or NaN: 1) -> rax = 0, -EINVAL, or a context error
; -----------------------------------------------------------------------------
%define D_COLOURS   0                   ; overrides
%define D_NCOL      8                   ; u32
%define D_ALPHA     12                  ; u32 the context's alpha on entry
%define D_WEIGHT    16                  ; f64
%define D_BODY      24
%define D_SCALE     32                  ; f64 1 / 2^f
%define D_STYLE     40                  ; UgfxStroke
%define D_ARGS      64                  ; f64[6]
%define D_SIZE      120

global ugfx_uic_draw
ugfx_uic_draw:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, D_SIZE
    mov rbx, rdi
    mov r13, rdx                        ; ctx
    mov rax, -(EINVAL)
    test rdi, rdi
    jz .draw_out
    test rdx, rdx
    jz .draw_out
    cmp esi, [rbx + UgfxUic_count]
    jae .draw_out
    mov [rsp + D_COLOURS], rcx
    test rcx, rcx
    jnz .draw_have_colours
    xor r8d, r8d
.draw_have_colours:
    mov [rsp + D_NCOL], r8d
    xorpd xmm4, xmm4
    ucomisd xmm3, xmm4
    jp .draw_weight1
    ja .draw_weight
.draw_weight1:
    movsd xmm3, [rel uic_one]
.draw_weight:
    movsd [rsp + D_WEIGHT], xmm3
    mov eax, [r13 + UgfxContext_state + UgfxState_alpha]
    mov [rsp + D_ALPHA], eax
    ; the body
    mov eax, esi
    shl rax, 4
    add rax, [rbx + UgfxUic_index]
    mov r12d, [rax + 4]
    add r12, [rbx + UgfxUic_bodies]
    mov [rsp + D_BODY], r12
    ; 1 / 2^f
    movzx ecx, byte [r12 + 16]
    mov eax, 1023
    sub eax, ecx
    shl rax, 52
    mov [rsp + D_SCALE], rax
    ; placement: s = size / max(w, h), centred
    cvtss2sd xmm4, [r12 + 8]            ; w
    cvtss2sd xmm5, [r12 + 12]           ; h
    movapd xmm6, xmm4
    maxsd xmm6, xmm5
    movapd xmm7, xmm2
    divsd xmm7, xmm6                    ; s
    movsd [rsp + D_ARGS], xmm7
    ; dx = (size - w s) / 2, dy = (size - h s) / 2
    mulsd xmm4, xmm7
    movapd xmm6, xmm2
    subsd xmm6, xmm4
    mulsd xmm6, [rel uic_half]
    addsd xmm0, xmm6
    mulsd xmm5, xmm7
    movapd xmm6, xmm2
    subsd xmm6, xmm5
    mulsd xmm6, [rel uic_half]
    addsd xmm1, xmm6
    movsd [rsp + D_ARGS + 8], xmm0
    movsd [rsp + D_ARGS + 16], xmm1
    mov rdi, r13
    call ugfx_ctx_save
    test rax, rax
    jnz .draw_out
    mov rdi, r13
    movsd xmm0, [rsp + D_ARGS + 8]
    movsd xmm1, [rsp + D_ARGS + 16]
    call ugfx_ctx_translate
    mov rdi, r13
    movsd xmm0, [rsp + D_ARGS]
    movapd xmm1, xmm0
    call ugfx_ctx_scale
    mov r12, [rsp + D_BODY]
    cvtss2sd xmm0, [r12]
    cvtss2sd xmm1, [r12 + 4]
    xorpd xmm2, xmm2
    subsd xmm2, xmm0
    xorpd xmm3, xmm3
    subsd xmm3, xmm1
    movapd xmm0, xmm2
    movapd xmm1, xmm3
    mov rdi, r13
    call ugfx_ctx_translate
    mov rdi, r13
    xor esi, esi
    call ugfx_ctx_set_dash              ; icons are never dashed
    lea rdi, [rbx + UgfxUic_path]
    call ugfx_path_reset
    ; commands
    movzx eax, byte [r12 + 17]
    lea r14, [r12 + rax * 4 + UIC_BODY_FIXED]   ; cursor
.draw_command:
    movzx eax, byte [r14]
    inc r14
    cmp eax, UOP_END
    je .draw_done
    cmp eax, UOP_MOVE
    je .d_move
    cmp eax, UOP_LINE
    je .d_line
    cmp eax, UOP_QUAD
    je .d_quad
    cmp eax, UOP_CUBIC
    je .d_cubic
    cmp eax, UOP_CLOSE
    je .d_close
    cmp eax, UOP_FILL
    je .d_fill
    cmp eax, UOP_STROKE
    je .d_stroke
    ; OPACITY: alpha = entry alpha x a / 255
    movzx eax, byte [r14]
    inc r14
    imul eax, [rsp + D_ALPHA]
    add eax, 128
    mov edx, eax
    shr edx, 8
    add eax, edx
    shr eax, 8
    mov rdi, r13
    mov esi, eax
    call ugfx_ctx_set_alpha
    jmp .draw_check
.d_move:
    mov ecx, 2
    call uic_coords
    lea rdi, [rbx + UgfxUic_path]
    call ugfx_path_move_to
    jmp .draw_check
.d_line:
    mov ecx, 2
    call uic_coords
    lea rdi, [rbx + UgfxUic_path]
    call ugfx_path_line_to
    jmp .draw_check
.d_quad:
    mov ecx, 4
    call uic_coords
    lea rdi, [rbx + UgfxUic_path]
    call ugfx_path_quad_to
    jmp .draw_check
.d_cubic:
    mov ecx, 6
    call uic_coords
    lea rdi, [rbx + UgfxUic_path]
    call ugfx_path_cubic_to
    jmp .draw_check
.d_close:
    lea rdi, [rbx + UgfxUic_path]
    call ugfx_path_close
    jmp .draw_check
.d_fill:
    movzx esi, byte [r14]
    call uic_slot_colour
    mov rdi, r13
    mov esi, eax
    call ugfx_ctx_set_fill_color
    mov rdi, r13
    movzx esi, byte [r14 + 1]
    call ugfx_ctx_set_fill_rule
    add r14, 2
    mov rdi, r13
    lea rsi, [rbx + UgfxUic_path]
    call ugfx_ctx_fill
    jmp .draw_drawn
.d_stroke:
    movzx esi, byte [r14]
    call uic_slot_colour
    mov rdi, r13
    mov esi, eax
    call ugfx_ctx_set_stroke_color
    movsx eax, word [r14 + 2]
    cvtsi2sd xmm0, eax
    mulsd xmm0, [rsp + D_SCALE]
    mulsd xmm0, [rsp + D_WEIGHT]
    movsd [rsp + D_STYLE + UgfxStroke_width], xmm0
    movsd xmm0, [rel uic_four]
    movsd [rsp + D_STYLE + UgfxStroke_miter_limit], xmm0
    movzx eax, byte [r14 + 1]
    mov edx, eax
    and eax, 15
    mov [rsp + D_STYLE + UgfxStroke_join], eax
    shr edx, 4
    mov [rsp + D_STYLE + UgfxStroke_cap], edx
    add r14, 4
    mov rdi, r13
    lea rsi, [rsp + D_STYLE]
    call ugfx_ctx_set_stroke_style
    mov rdi, r13
    lea rsi, [rbx + UgfxUic_path]
    call ugfx_ctx_stroke
.draw_drawn:
    test rax, rax
    jnz .draw_fail
    lea rdi, [rbx + UgfxUic_path]
    call ugfx_path_reset
    jmp .draw_command
.draw_check:
    test rax, rax
    jz .draw_command
.draw_fail:
    push rax
    sub rsp, 8
    mov rdi, r13
    call ugfx_ctx_restore
    add rsp, 8
    pop rax
    jmp .draw_out
.draw_done:
    mov rdi, r13
    call ugfx_ctx_restore
.draw_out:
    add rsp, D_SIZE
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15

; ecx = coordinates at r14 (advanced) -> xmm0..xmm5 = q / 2^f
;   (called from ugfx_uic_draw: its frame is at rsp + 8)
uic_coords:
    xor edx, edx
.uc_next:
    movsx eax, word [r14 + rdx * 2]
    cvtsi2sd xmm6, eax
    mulsd xmm6, [rsp + 8 + D_SCALE]
    movsd [rsp + 8 + D_ARGS + rdx * 8], xmm6
    inc edx
    cmp edx, ecx
    jb .uc_next
    lea r14, [r14 + rcx * 2]
    movsd xmm0, [rsp + 8 + D_ARGS]
    movsd xmm1, [rsp + 8 + D_ARGS + 8]
    movsd xmm2, [rsp + 8 + D_ARGS + 16]
    movsd xmm3, [rsp + 8 + D_ARGS + 24]
    movsd xmm4, [rsp + 8 + D_ARGS + 32]
    movsd xmm5, [rsp + 8 + D_ARGS + 40]
    ret

; esi = slot -> eax = its colour premultiplied (an override if given, else the
;   default); called from ugfx_uic_draw (frame at rsp + 8)
uic_slot_colour:
    cmp esi, [rsp + 8 + D_NCOL]
    jae .sc_default
    mov rax, [rsp + 8 + D_COLOURS]
    mov eax, [rax + rsi * 4]
    jmp .sc_premultiply
.sc_default:
    mov rax, [rsp + 8 + D_BODY]
    mov eax, [rax + UIC_BODY_FIXED + rsi * 4]
.sc_premultiply:
    mov r8d, eax
    shr r8d, 24                         ; alpha
    mov r9d, r8d
    shl r9d, 24
    xor ecx, ecx
.sc_channel:
    mov edx, eax
    shr edx, cl
    and edx, 255
    imul edx, r8d
    add edx, 128
    mov r10d, edx
    shr r10d, 8
    add edx, r10d
    shr edx, 8
    shl edx, cl
    or r9d, edx
    add ecx, 8
    cmp ecx, 24
    jb .sc_channel
    mov eax, r9d
    ret

section .data
global ugfx_uic_version
ugfx_uic_version: dq 0x010000
