; =============================================================================
; Utkarsha OS — lib/ugfx/core/span.asm
; =============================================================================
; Span compositor: blends one row of constant coverage into a PixBuf. This is
; where every rasterizer (2D coverage today, 3D triangles later) meets pixels.
;
; Pixels are premultiplied BGRA. With coverage a (0..255) and source colour
; c, each channel k becomes   s_k = round(c_k * a / 255)
;                             d_k = s_k + round(d_k * (255 - s_alpha) / 255)
; (source-over). round(t / 255) is computed exactly as
; (t + 128 + ((t + 128) >> 8)) >> 8.
; =============================================================================

%include "ugfx.inc"

section .text

; -----------------------------------------------------------------------------
; ugfx_span_fill_solid
;   IN:  rdi = PixBuf*, esi = x, edx = y, ecx = length,
;        r8d = coverage (0..255), r9d = colour (premultiplied BGRA)
;   OUT: rax = 0, -EINVAL. The span is clipped to the buffer.
; -----------------------------------------------------------------------------
global ugfx_span_fill_solid
ugfx_span_fill_solid:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    test rdi, rdi
    jz .bad
    mov r10, [rdi + PixBuf_data]
    test r10, r10
    jz .bad
    test r8d, r8d
    jz .done                            ; nothing to draw
    cmp r8d, 255
    ja .bad
    ; clip the row
    test edx, edx
    js .done
    movsxd rdx, edx
    cmp rdx, [rdi + PixBuf_height]
    jae .done
    movsxd rsi, esi
    movsxd rcx, ecx
    test rcx, rcx
    jle .done
    lea r11, [rsi + rcx]                ; end (exclusive)
    test rsi, rsi
    jns .x_start_ok
    xor esi, esi
.x_start_ok:
    mov rax, [rdi + PixBuf_width]
    cmp r11, rax
    jle .x_end_ok
    mov r11, rax
.x_end_ok:
    cmp rsi, r11
    jge .done
    ; row pointer
    imul rdx, [rdi + PixBuf_stride]
    add r10, rdx
    ; effective source s = colour * coverage
    mov r12d, r9d
    cmp r8d, 255
    je .source_ready
    xor r12d, r12d
    xor ecx, ecx
.source_channel:
    mov eax, r9d
    shr eax, cl
    and eax, 255
    imul eax, r8d
    add eax, 128
    mov edx, eax
    shr edx, 8
    add eax, edx
    shr eax, 8
    shl eax, cl
    or r12d, eax
    add ecx, 8
    cmp ecx, 32
    jb .source_channel
.source_ready:
    mov r13d, r12d
    shr r13d, 24
    mov r14d, 255
    sub r14d, r13d                      ; 255 - source alpha
    jz .opaque
    test r12d, r12d
    jz .done                            ; fully transparent source
.pixel:
    mov r15d, [r10 + rsi * 4]
    xor ebx, ebx                        ; result
    xor ecx, ecx
.blend_channel:
    mov eax, r15d
    shr eax, cl
    and eax, 255
    imul eax, r14d
    add eax, 128
    mov edx, eax
    shr edx, 8
    add eax, edx
    shr eax, 8                          ; round(d * (255 - sa) / 255)
    mov edx, r12d
    shr edx, cl
    and edx, 255
    add eax, edx
    shl eax, cl
    or ebx, eax
    add ecx, 8
    cmp ecx, 32
    jb .blend_channel
    mov [r10 + rsi * 4], ebx
    inc rsi
    cmp rsi, r11
    jb .pixel
    jmp .done
.opaque:
    mov [r10 + rsi * 4], r12d
    inc rsi
    cmp rsi, r11
    jb .opaque
.done:
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
.bad:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15

section .data
global ugfx_span_version
ugfx_span_version: dq 0x010000
