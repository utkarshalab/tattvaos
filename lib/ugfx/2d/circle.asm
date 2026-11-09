; ============================================================================
; Circle and Ellipse — Filled Discs (G2D-01)
; ============================================================================
; ellipse_draw fills, in one colour (no blending), every pixel (cx + x,
; cy + y) with
;     ry^2 x^2 + rx^2 y^2 <= rx^2 ry^2 + rx ry (rx + ry) / 2
; which for rx = ry = r is x^2 + y^2 <= r^2 + r: the disc the midpoint
; circle bounds. ry = 0 gives the segment of half-width rx; rx = 0 the
; segment of half-height ry. Each row is one span, worked out exactly (an
; integer square root), and clipped to the buffer. Radii are kept
; to 0..32767 and the centre to -32767..32767, so every product fits 64
; bits. tests/host/prims_check.py checks every pixel against this rule.

%include "ugfx.inc"

%define DISC_LIMIT  32767

section .text

; ============================================================================
; circle_draw
;   IN:  rdi = pixbuf*, esi = cx, edx = cy, ecx = radius, r8d = colour
;   OUT: rax = 0, -EINVAL out of range
; ============================================================================
global circle_draw
circle_draw:
    mov r9d, r8d
    mov r8d, ecx
    jmp ellipse_draw

; ============================================================================
; ellipse_draw
;   IN:  rdi = pixbuf*, esi = cx, edx = cy, ecx = rx, r8d = ry,
;        r9d = colour (premultiplied BGRA)
;   OUT: rax = 0, -EINVAL out of range
; ============================================================================
%define E_Y         0                   ; the row, from -ry to ry
%define E_A2        8                   ; rx^2
%define E_B2        16                  ; ry^2
%define E_R         24                  ; the right-hand side
%define E_COLOUR    32
global ellipse_draw
ellipse_draw:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 40                         ; locals; 16-byte aligned
    cmp esi, -DISC_LIMIT
    jl .bad
    cmp esi, DISC_LIMIT
    jg .bad
    cmp edx, -DISC_LIMIT
    jl .bad
    cmp edx, DISC_LIMIT
    jg .bad
    cmp ecx, DISC_LIMIT
    ja .bad                             ; (negative is above, unsigned)
    cmp r8d, DISC_LIMIT
    ja .bad
    mov rbx, rdi
    mov r12d, esi                       ; cx, cy
    mov r13d, edx
    mov r14d, ecx                       ; rx, ry
    mov r15d, r8d
    mov [rsp + E_COLOUR], r9d
    mov rax, r14
    imul rax, r14
    mov [rsp + E_A2], rax
    mov rcx, r15
    imul rcx, r15
    mov [rsp + E_B2], rcx
    imul rax, rcx                       ; rx^2 ry^2
    mov rcx, r14                        ; + rx ry (rx + ry) / 2
    imul rcx, r15
    lea rdx, [r14 + r15]
    imul rcx, rdx
    shr rcx, 1
    add rax, rcx
    mov [rsp + E_R], rax
    mov rax, r15
    neg rax
    mov [rsp + E_Y], rax
.row:
    mov rax, [rsp + E_Y]
    cmp rax, r15
    jg .done
    mov rcx, rax                        ; t = R - rx^2 y^2
    imul rcx, rax
    imul rcx, [rsp + E_A2]
    mov rdi, [rsp + E_R]
    sub rdi, rcx
    js .next                            ; (cannot be, but never a span)
    mov rcx, [rsp + E_B2]
    test rcx, rcx
    jnz .solve
    mov rsi, r14                        ; ry = 0: the whole segment
    jmp .span
.solve:
    mov rax, rdi                        ; ry^2 x^2 <= t exactly when
    xor edx, edx                        ; x^2 <= q = floor(t / ry^2)
    div rcx
    cvtsi2sd xmm0, rax                  ; q < 2^31 here, and floor(sqrt) of
    sqrtsd xmm0, xmm0                   ; an integer below 2^51 is its exact
    cvttsd2si rsi, xmm0                 ; integer square root: w
.span:
    mov rax, [rsp + E_Y]                ; the row on the buffer?
    movsxd rdx, r13d
    add rax, rdx
    js .next
    cmp rax, [rbx + PixBuf_height]
    jae .next
    movsxd rdx, r12d                    ; x from cx - w to cx + w, clipped
    mov r8, rdx
    sub r8, rsi
    lea r9, [rdx + rsi]
    xor ecx, ecx
    cmp r8, rcx
    cmovl r8, rcx
    mov rcx, [rbx + PixBuf_width]
    dec rcx
    cmp r9, rcx
    cmovg r9, rcx
    cmp r8, r9
    jg .next
    imul rax, [rbx + PixBuf_stride]
    add rax, [rbx + PixBuf_data]
    lea rdi, [rax + r8 * 4]
    lea rcx, [r9 + 1]
    sub rcx, r8
    mov eax, [rsp + E_COLOUR]
    rep stosd
.next:
    inc qword [rsp + E_Y]
    jmp .row
.done:
    xor eax, eax
    add rsp, 40
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
.bad:
    mov rax, -EINVAL
    add rsp, 40
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15

section .data
global circle_version
circle_version: dq 0x020000
global ellipse_version
ellipse_version: dq 0x020000
