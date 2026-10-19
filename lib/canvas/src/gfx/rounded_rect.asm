; ============================================================================
; Rounded Rectangle Primitive
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/geometry.inc"
%include "inc/externs.inc"

section .text

; ============================================================================
; rounded_rect_draw
;   Draw filled rounded rectangle
;   IN: rdi = pixbuf*, rsi = x, rdx = y, rcx = w, r8 = h, r9 = radius, r10 = color
;   OUT: rax = 0 OK
; ============================================================================
global rounded_rect_draw
rounded_rect_draw:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12d, esi       ; x
    mov r13d, edx       ; y
    mov r14d, ecx       ; w
    mov r13d, r8d       ; h
    mov r14d, r9d       ; radius
    mov r15d, r10d      ; color
    ASSERT_PTR rbx

    ; Get pixbuf info
    mov eax, [rbx + Pixbuf.width]
    mov r11d, eax
    mov eax, [rbx + Pixbuf.height]
    mov r10d, eax
    mov rax, [rbx + Pixbuf.stride]
    mov r9, rax
    mov rax, [rbx + Pixbuf.data]
    mov rdi, rax

    ; Clamp radius to half of min(w, h)
    mov eax, r14d
    cmp eax, r13d
    jle .check_w
    mov eax, r13d
.check_w:
    cmp eax, r14d
    jle .radius_ok
    mov eax, r14d
.radius_ok:
    shr eax, 1
    cmp r14d, eax
    jle .radius_ok2
    mov r14d, eax
.radius_ok2:

    ; Draw 4 corners (quarter circles)
    ; Top-left: quadrant 0, center at (x+radius, y+radius)
    mov rdi, rbx
    mov esi, r12d
    add esi, r14d
    mov edx, r13d
    add edx, r14d
    mov ecx, r14d
    mov r8d, 0
    mov r9d, r15d
    call circle_draw_quadrant

    ; Top-right: quadrant 1, center at (x+w-radius, y+radius)
    mov rdi, rbx
    mov esi, r12d
    add esi, r14d
    sub esi, r14d
    add esi, r14d       ; x + w - r
    mov edx, r13d
    add edx, r14d
    mov ecx, r14d
    mov r8d, 1
    mov r9d, r15d
    call circle_draw_quadrant

    ; Bottom-right: quadrant 2, center at (x+w-radius, y+h-radius)
    mov rdi, rbx
    mov esi, r12d
    add esi, r14d
    sub esi, r14d
    add esi, r14d
    mov edx, r13d
    add edx, r13d
    sub edx, r14d
    mov ecx, r14d
    mov r8d, 2
    mov r9d, r15d
    call circle_draw_quadrant

    ; Bottom-left: quadrant 3, center at (x+radius, y+h-radius)
    mov rdi, rbx
    mov esi, r12d
    add esi, r14d
    mov edx, r13d
    add edx, r13d
    sub edx, r14d
    mov ecx, r14d
    mov r8d, 3
    mov r9d, r15d
    call circle_draw_quadrant

    ; Fill center rectangle (top bar above corners)
    ; x+radius to x+w-radius, y to y+radius
    mov rdi, rbx
    mov esi, r12d
    add esi, r14d
    mov edx, r13d
    mov ecx, r14d
    sub ecx, r14d
    shl ecx, 1          ; w - 2*r
    mov r8d, r14d       ; h = radius
    mov r9d, r15d
    call rect_fill

    ; Fill center rectangle (bottom bar below corners)
    mov rdi, rbx
    mov esi, r12d
    add esi, r14d
    mov edx, r13d
    add edx, r13d
    sub edx, r14d
    mov ecx, r14d
    sub ecx, r14d
    shl ecx, 1
    mov r8d, r14d
    mov r9d, r15d
    call rect_fill

    ; Fill middle rectangle (between corners vertically)
    mov rdi, rbx
    mov esi, r12d
    add esi, r14d
    mov edx, r13d
    add edx, r14d
    mov ecx, r14d
    sub ecx, r14d
    shl ecx, 1
    mov r8d, r13d
    sub r8d, r14d
    shl r8d, 1          ; h - 2*r
    mov r9d, r15d
    call rect_fill

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret


; ============================================================================
; rounded_rect_stroke
;   Draw rounded rectangle outline
;   IN: rdi = pixbuf*, rsi = x, rdx = y, rcx = w, r8 = h, r9 = radius
;       r10 = color, r11 = stroke_width
; ============================================================================
global rounded_rect_stroke
rounded_rect_stroke:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12d, esi       ; x
    mov r13d, edx       ; y
    mov r14d, ecx       ; w
    mov r13d, r8d       ; h
    mov r14d, r9d       ; radius
    mov r15d, r10d      ; color
    mov r10d, r11d      ; stroke_width
    ASSERT_PTR rbx

    ; Clamp radius
    mov eax, r14d
    cmp eax, r13d
    jle .check_w2
    mov eax, r13d
.check_w2:
    cmp eax, r14d
    jle .radius_ok3
    mov eax, r14d
.radius_ok3:
    shr eax, 1
    cmp r14d, eax
    jle .radius_ok4
    mov r14d, eax
.radius_ok4:

    ; Draw 4 corner arcs using arc_draw
    ; Top-left arc: 90 to 180 degrees
    mov rdi, rbx
    mov esi, r12d
    add esi, r14d
    mov edx, r13d
    add edx, r14d
    mov ecx, r14d
    mov r8d, r14d
    mov r9d, 90
    mov r10d, 90
    mov r11d, r15d
    call arc_draw

    ; Top-right arc: 0 to 90 degrees
    mov rdi, rbx
    mov esi, r12d
    add esi, r14d
    sub esi, r14d
    add esi, r14d
    mov edx, r13d
    add edx, r14d
    mov ecx, r14d
    mov r8d, r14d
    mov r9d, 0
    mov r10d, 90
    mov r11d, r15d
    call arc_draw

    ; Bottom-right arc: 270 to 360 (or -90 to 0)
    mov rdi, rbx
    mov esi, r12d
    add esi, r14d
    sub esi, r14d
    add esi, r14d
    mov edx, r13d
    add edx, r13d
    sub edx, r14d
    mov ecx, r14d
    mov r8d, r14d
    mov r9d, 270
    mov r10d, 90
    mov r11d, r15d
    call arc_draw

    ; Bottom-left arc: 180 to 270
    mov rdi, rbx
    mov esi, r12d
    add esi, r14d
    mov edx, r13d
    add edx, r13d
    sub edx, r14d
    mov ecx, r14d
    mov r8d, r14d
    mov r9d, 180
    mov r10d, 90
    mov r11d, r15d
    call arc_draw

    ; Draw 4 straight edges
    ; Top edge
    mov rdi, rbx
    mov esi, r12d
    add esi, r14d
    mov edx, r13d
    add edx, r14d
    mov ecx, r14d
    sub ecx, r14d
    shl ecx, 1
    mov r8d, r10d
    mov r9d, r15d
    call line_draw

    ; Right edge
    mov rdi, rbx
    mov esi, r12d
    add esi, r14d
    sub esi, r14d
    add esi, r14d
    mov edx, r13d
    add edx, r14d
    mov ecx, r13d
    sub ecx, r14d
    shl ecx, 1
    mov r8d, r10d
    mov r9d, r15d
    call line_draw

    ; Bottom edge
    mov rdi, rbx
    mov esi, r12d
    add esi, r14d
    mov edx, r13d
    add edx, r13d
    sub edx, r14d
    mov ecx, r14d
    sub ecx, r14d
    shl ecx, 1
    mov r8d, r10d
    mov r9d, r15d
    call line_draw

    ; Left edge
    mov rdi, rbx
    mov esi, r12d
    mov edx, r13d
    add edx, r14d
    mov ecx, r13d
    sub ecx, r14d
    shl ecx, 1
    mov r8d, r10d
    mov r9d, r15d
    call line_draw

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret


section .data
global rounded_rect_version
rounded_rect_version: dq 0x010000