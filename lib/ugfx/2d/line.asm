; ============================================================================
; Line — One-Pixel Lines (G2D-01)
; ============================================================================
; line_draw sets the pixels of the all-octant Bresenham line from one end to
; the other, both ends included, to one colour (no blending). Pixels off
; the buffer are skipped, so a line's pixels are the same whether it is
; clipped or not. Coordinates are kept to -32767..32767, which bounds a
; line to 65535 steps.
;
; The steps, exactly (tests/host/prims_check.py has the same):
;     dx = |x1 - x0|, sx = sign; dy = -|y1 - y0|, sy = sign; err = dx + dy
;     loop: plot (x0, y0); stop at (x1, y1); e2 = 2 err;
;           e2 >= dy: err += dy, x0 += sx;  e2 <= dx: err += dx, y0 += sy

%include "ugfx.inc"

%define LINE_LIMIT  32767

section .text

; ============================================================================
; line_draw
;   IN:  rdi = pixbuf*, esi = x0, edx = y0, ecx = x1, r8d = y1,
;        r9d = colour (premultiplied BGRA)
;   OUT: rax = 0, -EINVAL for a coordinate past LINE_LIMIT
; ============================================================================
global line_draw
line_draw:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
%macro LINE_IN_RANGE 1
    cmp %1, -LINE_LIMIT
    jl .bad
    cmp %1, LINE_LIMIT
    jg .bad
%endmacro
    LINE_IN_RANGE esi
    LINE_IN_RANGE edx
    LINE_IN_RANGE ecx
    LINE_IN_RANGE r8d
    mov rbx, rdi
    mov r12d, esi                       ; x0
    mov r13d, edx                       ; y0
    mov r14d, ecx                       ; x1
    mov r15d, r8d                       ; y1
    mov r10d, r9d                       ; the colour
    mov eax, r14d                       ; dx, sx
    sub eax, r12d
    mov r8d, 1
    jge .dx
    neg eax
    mov r8d, -1
.dx:
    mov r9d, eax
    mov eax, r15d                       ; dy (negative), sy
    sub eax, r13d
    mov r11d, 1
    jge .dy
    neg eax
    mov r11d, -1
.dy:
    neg eax
    mov ecx, eax                        ; ecx = dy
    lea edx, [r9 + rcx]                 ; edx = err
.step:
    mov eax, r12d                       ; the pixel, if on the buffer
    cmp rax, [rbx + PixBuf_width]
    jae .off
    mov eax, r13d
    cmp rax, [rbx + PixBuf_height]
    jae .off
    mov rax, [rbx + PixBuf_stride]
    imul rax, r13
    add rax, [rbx + PixBuf_data]
    mov [rax + r12 * 4], r10d
.off:
    cmp r12d, r14d
    jne .on
    cmp r13d, r15d
    je .done
.on:
    lea eax, [rdx + rdx]                ; e2
    cmp eax, ecx
    jl .no_x
    add edx, ecx
    add r12d, r8d
.no_x:
    cmp eax, r9d
    jg .step
    add edx, r9d
    add r13d, r11d
    jmp .step
.done:
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
.bad:
    mov rax, -EINVAL
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15

section .data
global line_version
line_version: dq 0x020000
