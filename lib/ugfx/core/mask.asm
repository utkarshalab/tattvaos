; =============================================================================
; Utkarsha OS — lib/ugfx/core/mask.asm
; =============================================================================
; Coverage masks (A8): one byte per pixel, 0 = outside, 255 = inside. A mask
; is what a clip is made of (ugfx_raster_set_clip), and what a path's
; coverage can be rendered into (ugfx_raster_fill_mask).
;
;   ugfx_mask_init(mask, arena, width, height)   zeroed
;   ugfx_mask_fill(mask, value)
;   ugfx_mask_fill_rect(mask, x, y, w, h, value)  clipped to the mask
;   ugfx_mask_copy(dst, src)                      src outside its size = 0
;   ugfx_mask_intersect(dst, src)                 dst = dst * src / 255
;   ugfx_mask_invert(mask)                        m = 255 - m
;   ugfx_mask_from_alpha(mask, pixbuf)            m = alpha
;   ugfx_mask_from_luminance(mask, pixbuf)        m = luminance (premultiplied)
;   ugfx_span_mask_union  span function: m = c + m (255 - c) / 255
;
; x / 255 products round exactly: (t + 128 + ((t + 128) >> 8)) >> 8.
; Luminance uses the CSS Masking weights 0.2125 R + 0.7154 G + 0.0721 B
; on premultiplied channels (luminance times alpha), as 13926 R + 46884 G +
; 4725 B, rounded >> 16 (the weights sum to 65535: white gives 255).
; =============================================================================

%include "ugfx.inc"

extern arena_alloc

; t (eax) -> eax = round(t / 255), t <= 255 * 255. Clobbers edx.
%macro DIV255 0
    add eax, 128
    mov edx, eax
    shr edx, 8
    add eax, edx
    shr eax, 8
%endmacro

section .text

; -----------------------------------------------------------------------------
; ugfx_mask_init — rdi = UgfxMask*, rsi = arena, rdx = width, rcx = height
;   (both > 0) -> rax = 0, -EINVAL, -ENOMEM. The mask starts at 0.
; -----------------------------------------------------------------------------
global ugfx_mask_init
ugfx_mask_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov rax, -(EINVAL)
    test rdi, rdi
    jz .init_out
    test rdx, rdx
    jz .init_out
    test rcx, rcx
    jz .init_out
    mov r12, rdx
    add r12, 15
    and r12, -16                        ; stride: rows 16-byte aligned
    mov [rbx + UgfxMask_width], rdx
    mov [rbx + UgfxMask_height], rcx
    mov [rbx + UgfxMask_stride], r12
    mov rax, r12
    mul rcx
    jo .init_bad
    mov rdi, rsi
    mov rsi, rax
    call arena_alloc
    test rax, rax
    jz .init_nomem
    mov [rbx + UgfxMask_data], rax
    mov rdi, rbx
    xor esi, esi
    call ugfx_mask_fill
    xor eax, eax
    jmp .init_out
.init_bad:
    mov rax, -(EINVAL)
    jmp .init_out
.init_nomem:
    mov qword [rbx + UgfxMask_data], 0
    mov rax, -(ENOMEM)
.init_out:
    EPILOGUE_RESTORE rbx, r12

; -----------------------------------------------------------------------------
; ugfx_mask_fill — rdi = UgfxMask*, esi = value (0..255) -> rax = 0, -EINVAL
; -----------------------------------------------------------------------------
global ugfx_mask_fill
ugfx_mask_fill:
    test rdi, rdi
    jz mask_bad
    mov r8, rdi
    xor edx, edx
    xor ecx, ecx
    mov r9, [r8 + UgfxMask_width]
    mov r10, [r8 + UgfxMask_height]
    jmp mask_fill_box

; -----------------------------------------------------------------------------
; ugfx_mask_fill_rect — rdi = UgfxMask*, esi = x, edx = y, ecx = w, r8d = h,
;   r9d = value -> rax = 0, -EINVAL. Clipped to the mask.
; -----------------------------------------------------------------------------
global ugfx_mask_fill_rect
ugfx_mask_fill_rect:
    test rdi, rdi
    jz mask_bad
    ; box [x0, x1) x [y0, y1) in i64, clipped
    movsxd rax, esi
    movsxd r10, ecx
    test r10, r10
    jle mask_ok
    add r10, rax                        ; x1
    movsxd r11, edx
    movsxd rcx, r8d
    test rcx, rcx
    jle mask_ok
    add rcx, r11                        ; y1
    xor edx, edx
    test rax, rax
    cmovs rax, rdx
    test r11, r11
    cmovs r11, rdx
    cmp r10, [rdi + UgfxMask_width]
    jle .fr_x1
    mov r10, [rdi + UgfxMask_width]
.fr_x1:
    cmp rcx, [rdi + UgfxMask_height]
    jle .fr_y1
    mov rcx, [rdi + UgfxMask_height]
.fr_y1:
    mov esi, r9d
    mov r8, rdi
    mov rdx, rax                        ; x0
    mov r9, r10                         ; x1
    mov r10, rcx                        ; y1
    mov rcx, r11                        ; y0
    ; fall through

; r8 = mask, rdx = x0, rcx = y0, r9 = x1, r10 = y1, sil = value
mask_fill_box:
    cmp rdx, r9
    jge mask_ok
    cmp rcx, r10
    jge mask_ok
    push rdi
    mov r11, rcx
.box_row:
    mov rdi, r11
    imul rdi, [r8 + UgfxMask_stride]
    add rdi, [r8 + UgfxMask_data]
    add rdi, rdx
    mov rcx, r9
    sub rcx, rdx
    mov eax, esi
    rep stosb
    inc r11
    cmp r11, r10
    jb .box_row
    pop rdi
mask_ok:
    xor eax, eax
    ret
mask_bad:
    mov rax, -(EINVAL)
    ret

; -----------------------------------------------------------------------------
; ugfx_mask_copy — rdi = dst UgfxMask*, rsi = src UgfxMask* -> rax = 0, -EINVAL
;   Over dst's size; dst pixels outside src become 0.
; ugfx_mask_intersect — the same, dst = round(dst * src / 255).
; -----------------------------------------------------------------------------
global ugfx_mask_copy
ugfx_mask_copy:
    xor eax, eax
    jmp mask_combine
global ugfx_mask_intersect
ugfx_mask_intersect:
    mov eax, 1

; eax = 0 copy, 1 intersect
mask_combine:
    test rdi, rdi
    jz mask_bad
    test rsi, rsi
    jz mask_bad
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov r15d, eax
    mov rbx, rdi
    mov r12, rsi
    xor r13d, r13d                      ; row
.cb_row:
    cmp r13, [rbx + UgfxMask_height]
    jae .cb_done
    mov rdi, r13
    imul rdi, [rbx + UgfxMask_stride]
    add rdi, [rbx + UgfxMask_data]
    xor r14d, r14d                      ; column
    xor r8d, r8d
    cmp r13, [r12 + UgfxMask_height]
    jae .cb_px                          ; no source row: 0
    mov r8, r13
    imul r8, [r12 + UgfxMask_stride]
    add r8, [r12 + UgfxMask_data]
.cb_px:
    cmp r14, [rbx + UgfxMask_width]
    jae .cb_next
    xor eax, eax
    test r8, r8
    jz .cb_store
    cmp r14, [r12 + UgfxMask_width]
    jae .cb_store
    movzx eax, byte [r8 + r14]
    test r15d, r15d
    jz .cb_store
    movzx ecx, byte [rdi + r14]
    imul eax, ecx
    DIV255
.cb_store:
    mov [rdi + r14], al
    inc r14
    jmp .cb_px
.cb_next:
    inc r13
    jmp .cb_row
.cb_done:
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15

; -----------------------------------------------------------------------------
; ugfx_mask_invert — rdi = UgfxMask* -> rax = 0, -EINVAL
; -----------------------------------------------------------------------------
global ugfx_mask_invert
ugfx_mask_invert:
    test rdi, rdi
    jz mask_bad
    xor ecx, ecx                        ; row
.inv_row:
    cmp rcx, [rdi + UgfxMask_height]
    jae mask_ok
    mov rsi, rcx
    imul rsi, [rdi + UgfxMask_stride]
    add rsi, [rdi + UgfxMask_data]
    xor edx, edx
.inv_px:
    cmp rdx, [rdi + UgfxMask_width]
    jae .inv_next
    not byte [rsi + rdx]
    inc rdx
    jmp .inv_px
.inv_next:
    inc rcx
    jmp .inv_row

; -----------------------------------------------------------------------------
; ugfx_mask_from_alpha — rdi = UgfxMask*, rsi = const PixBuf* (BGRA)
; ugfx_mask_from_luminance — the same, from premultiplied luminance
;   -> rax = 0, -EINVAL. Over the mask's size; outside the image: 0.
; -----------------------------------------------------------------------------
global ugfx_mask_from_alpha
ugfx_mask_from_alpha:
    xor eax, eax
    jmp mask_from_image
global ugfx_mask_from_luminance
ugfx_mask_from_luminance:
    mov eax, 1

mask_from_image:
    test rdi, rdi
    jz mask_bad
    test rsi, rsi
    jz mask_bad
    cmp qword [rsi + PixBuf_data], 0
    je mask_bad
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov r15d, eax
    mov rbx, rdi
    mov r12, rsi
    xor r13d, r13d
.fi_row:
    cmp r13, [rbx + UgfxMask_height]
    jae .fi_done
    mov rdi, r13
    imul rdi, [rbx + UgfxMask_stride]
    add rdi, [rbx + UgfxMask_data]
    xor r8d, r8d
    cmp r13, [r12 + PixBuf_height]
    jae .fi_have_row
    mov r8, r13
    imul r8, [r12 + PixBuf_stride]
    add r8, [r12 + PixBuf_data]
.fi_have_row:
    xor r14d, r14d
.fi_px:
    cmp r14, [rbx + UgfxMask_width]
    jae .fi_next
    xor eax, eax
    test r8, r8
    jz .fi_store
    cmp r14, [r12 + PixBuf_width]
    jae .fi_store
    mov r9d, [r8 + r14 * 4]
    mov eax, r9d
    shr eax, 24
    test r15d, r15d
    jz .fi_store
    ; (13926 R + 46884 G + 4725 B + 32768) >> 16, at most 255
    mov eax, r9d
    shr eax, 16
    and eax, 255
    imul eax, eax, 13926
    mov ecx, r9d
    shr ecx, 8
    and ecx, 255
    imul ecx, ecx, 46884
    add eax, ecx
    mov ecx, r9d
    and ecx, 255
    imul ecx, ecx, 4725
    add eax, ecx
    add eax, 32768
    shr eax, 16
    cmp eax, 255
    jbe .fi_store
    mov eax, 255
.fi_store:
    mov [rdi + r14], al
    inc r14
    jmp .fi_px
.fi_next:
    inc r13
    jmp .fi_row
.fi_done:
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15

; -----------------------------------------------------------------------------
; ugfx_span_mask_union — span function for ugfx_raster_fill_mask:
;   rdi = UgfxMask*, esi = x, edx = y, ecx = length, r8d = coverage
;   -> each pixel m = c + round(m (255 - c) / 255), clipped to the mask
; -----------------------------------------------------------------------------
global ugfx_span_mask_union
ugfx_span_mask_union:
    test rdi, rdi
    jz mask_bad
    test r8d, r8d
    jz mask_ok
    test edx, edx
    js mask_ok
    movsxd rdx, edx
    cmp rdx, [rdi + UgfxMask_height]
    jae mask_ok
    movsxd rsi, esi
    movsxd rcx, ecx
    lea r10, [rsi + rcx]                ; end
    xor eax, eax
    test rsi, rsi
    cmovs rsi, rax
    cmp r10, [rdi + UgfxMask_width]
    jle .mu_end
    mov r10, [rdi + UgfxMask_width]
.mu_end:
    cmp rsi, r10
    jge mask_ok
    imul rdx, [rdi + UgfxMask_stride]
    add rdx, [rdi + UgfxMask_data]
    mov r9, rdx
    mov r11d, 255
    sub r11d, r8d                       ; 255 - c
.mu_px:
    movzx eax, byte [r9 + rsi]
    imul eax, r11d
    DIV255
    add eax, r8d
    mov [r9 + rsi], al
    inc rsi
    cmp rsi, r10
    jb .mu_px
    xor eax, eax
    ret

section .data
global ugfx_mask_version
ugfx_mask_version: dq 0x010000
