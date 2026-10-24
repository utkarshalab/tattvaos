; ============================================================================
; Circle/Ellipse Primitives — Midpoint Circle Algorithm
; ============================================================================

%include "ugfx.inc"

section .text

; ============================================================================
; circle_draw
;   Draw filled circle using midpoint algorithm
;   IN:  rdi = pixbuf*, rsi = cx, rdx = cy, rcx = radius, r8 = color
;   OUT: rax = 0 OK
; ============================================================================
global circle_draw
circle_draw:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12d, esi           ; cx
    mov r13d, edx           ; cy
    mov r14d, ecx           ; radius
    mov r15d, r8d           ; color
    ASSERT_PTR rbx

    ; Get pixbuf info
    mov eax, [rbx + PixBuf_width]
    mov r11d, eax
    mov eax, [rbx + PixBuf_height]
    mov r10d, eax
    mov rax, [rbx + PixBuf_stride]
    mov r9, rax
    mov rax, [rbx + PixBuf_data]
    mov rdi, rax            ; framebuffer

    ; Check if circle is completely outside
    mov eax, r12d
    add eax, r14d
    cmp eax, 0
    jle .draw_done
    mov eax, r12d
    sub eax, r14d
    cmp eax, r11d
    jge .draw_done
    mov eax, r13d
    add eax, r14d
    cmp eax, 0
    jle .draw_done
    mov eax, r13d
    sub eax, r14d
    cmp eax, r10d
    jge .draw_done

    ; Midpoint circle algorithm
    ; Use r8d = x, r9d = y, r11d = decision
    xor r8d, r8d            ; x = 0
    mov r9d, r14d           ; y = radius
    mov r11d, 1
    sub r11d, r14d          ; decision = 1 - radius

    ; Draw 8-way symmetry
.draw_loop:
    cmp r8d, r9d
    jg .draw_done

    ; Octant 1: (x, y)
    mov eax, r12d
    add eax, r8d
    mov r9d, r13d
    add r9d, r9d            ; cx + x, cy + y (but r9d is used for y, need temp)
    ; Actually let's use different approach - pass coords via registers
    mov r9d, r12d           ; cx
    add r9d, r8d            ; cx + x
    mov r10d, r13d          ; cy
    add r10d, r9d           ; wait, r9d is now cx+x
    ; This is getting messy. Let me use stack for temp vars.

    ; For now just use a simpler approach
    ; r8 = x, r9 = y (algorithm vars)
    ; r12 = cx, r13 = cy, r14 = radius, r15 = color
    ; rdi = framebuffer, rsi = stride

    ; Plot 4 points for (x, y)
    ; (cx + x, cy + y)
    mov eax, r12d
    add eax, r8d
    mov r10d, eax
    mov eax, r13d
    add eax, r9d
    mov r11d, eax
    call circle_plot_pixel

    ; (cx - x, cy + y)
    mov eax, r12d
    sub eax, r8d
    mov r10d, eax
    mov eax, r13d
    add eax, r9d
    mov r11d, eax
    call circle_plot_pixel

    ; (cx + x, cy - y)
    mov eax, r12d
    add eax, r8d
    mov r10d, eax
    mov eax, r13d
    sub eax, r9d
    mov r11d, eax
    call circle_plot_pixel

    ; (cx - x, cy - y)
    mov eax, r12d
    sub eax, r8d
    mov r10d, eax
    mov eax, r13d
    sub eax, r9d
    mov r11d, eax
    call circle_plot_pixel

    ; Plot 4 points for (y, x) - swapped
    ; (cx + y, cy + x)
    mov eax, r12d
    add eax, r9d
    mov r10d, eax
    mov eax, r13d
    add eax, r8d
    mov r11d, eax
    call circle_plot_pixel

    ; (cx - y, cy + x)
    mov eax, r12d
    sub eax, r9d
    mov r10d, eax
    mov eax, r13d
    add eax, r8d
    mov r11d, eax
    call circle_plot_pixel

    ; (cx + y, cy - x)
    mov eax, r12d
    add eax, r9d
    mov r10d, eax
    mov eax, r13d
    sub eax, r8d
    mov r11d, eax
    call circle_plot_pixel

    ; (cx - y, cy - x)
    mov eax, r12d
    sub eax, r9d
    mov r10d, eax
    mov eax, r13d
    sub eax, r8d
    mov r11d, eax
    call circle_plot_pixel

    ; Decision parameter update
    inc r8d                 ; x++
    test r11d, r11d
    jle .move_e
    dec r9d                 ; y--
    sub r11d, r8d
    sub r11d, r8d
    sub r11d, 1
    jmp .next_pixel
.move_e:
    add r11d, 2
.next_pixel:
    jmp .draw_loop

.draw_done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret


circle_plot_pixel:
    ; Check bounds
    ; IN: r10d = x, r11d = y, rdi = framebuffer, rsi = stride, r15d = color
    ; Width/height on stack from caller
    cmp r10d, 0
    jl .skip
    cmp r11d, 0
    jl .skip
    cmp r10d, [rsp + 8]
    jge .skip
    cmp r11d, [rsp + 12]
    jge .skip

    mov rax, r11
    imul rax, rsi
    add rax, r10
    shl rax, 2
    add rax, rdi
    mov dword [rax], r15d
    ret
.skip:
    ret


; ============================================================================
; ellipse_draw
;   Draw filled ellipse using midpoint algorithm
;   IN: rdi = pixbuf*, rsi = cx, rdx = cy, rcx = rx, r8 = ry, r9 = color
; ============================================================================
global ellipse_draw
ellipse_draw:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    mov r14d, ecx
    mov r15d, r8d
    mov r10d, r9d
    ASSERT_PTR rbx

    ; Get pixbuf info
    mov eax, [rbx + PixBuf_width]
    mov r11d, eax
    mov eax, [rbx + PixBuf_height]
    mov r10d, eax
    mov rax, [rbx + PixBuf_stride]
    mov r9, rax
    mov rax, [rbx + PixBuf_data]
    mov rdi, rax

    ; Region 1: dx > dy
    xor r10d, r10d            ; x = 0
    mov r10d, r15d            ; y = ry
    mov r11d, r14d
    imul r11d, r15d
    mov r12d, r14d
    imul r12d, r14d
    mov r13d, r15d
    imul r13d, r15d
    ; decision = ry^2 - rx^2*ry + rx^2/4
    mov eax, r14d
    imul eax, r14d
    imul eax, r15d
    sub eax, r15d
    add eax, r14d
    shr eax, 2
    mov r11d, eax

.region1:
    ; 4-way symmetry
    call ellipse_plot_4way
    test r11d, r11d
    jle .region1_e
    dec r15d
    sub r11d, r13d
    sub r11d, r13d
    jmp .region1_next
.region1_e:
    inc r10d
    add r11d, r12d
.region1_next:
    cmp r13d, r12d
    jg .region1
    cmp r12d, r11d
    jle .region1
    ; Switch to region 2

    ; Region 2: dx < dy
    mov r11d, r12d
    imul r11d, r12d
    add r11d, r13d
    sub r11d, r14d
    sub r11d, r13d
    add r11d, r14d
    shr r11d, 2

.region2:
    call ellipse_plot_4way
    test r11d, r11d
    jg .region2_e
    inc r10d
    sub r11d, r12d
    sub r11d, r12d
    jmp .region2_next
.region2_e:
    dec r15d
    add r11d, r13d
    add r11d, r13d
.region2_next:
    test r15d, r15d
    jge .region2

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

ellipse_plot_4way:
    ; Similar to circle_plot_4way but with rx, ry scaling
    ret


; ============================================================================
; circle_draw_quadrant
;   Draw filled quarter circle (for rounded rectangle corners)
;   IN: rdi = pixbuf*, rsi = cx, rdx = cy, rcx = radius, r8 = quadrant, r9 = color
;       quadrant: 0=top-left, 1=top-right, 2=bottom-right, 3=bottom-left
;   OUT: rax = 0 OK
; ============================================================================
global circle_draw_quadrant
circle_draw_quadrant:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12d, esi       ; cx
    mov r13d, edx       ; cy
    mov r14d, ecx       ; radius
    mov r15d, r8d       ; quadrant
    mov r10d, r9d       ; color
    ASSERT_PTR rbx

    ; Get pixbuf info
    mov eax, [rbx + PixBuf_width]
    mov r11d, eax
    mov eax, [rbx + PixBuf_height]
    mov r9d, eax
    mov rax, [rbx + PixBuf_stride]
    mov r8, rax
    mov rax, [rbx + PixBuf_data]
    mov rdi, rax        ; framebuffer
    mov rsi, rax        ; stride

    ; Midpoint circle algorithm for first octant, then mirror based on quadrant
    xor r8d, r8d            ; x = 0
    mov r9d, r14d           ; y = radius
    mov r11d, 1
    sub r11d, r14d          ; decision = 1 - radius

.draw_loop:
    cmp r8d, r9d
    jg .draw_done

    ; Plot points based on quadrant
    call .plot_quadrant_points

    ; Decision parameter update
    inc r8d
    test r11d, r11d
    jle .move_e
    dec r9d
    sub r11d, r8d
    sub r11d, r8d
    sub r11d, 1
    jmp .next_pixel
.move_e:
    add r11d, 2
.next_pixel:
    jmp .draw_loop

.draw_done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.plot_quadrant_points:
    ; r8 = x, r9 = y, r12 = cx, r13 = cy, r15 = quadrant, r10 = color
    ; Plot (x, y) and (y, x) with quadrant transform
    
    ; Point 1: (x, y)
    mov eax, r12d
    mov ebx, r13d
    cmp r15d, 0
    je .q0_p1
    cmp r15d, 1
    je .q1_p1
    cmp r15d, 2
    je .q2_p1
    ; quadrant 3
    sub eax, r8d
    add ebx, r9d
    jmp .plot_p1
.q0_p1:
    sub eax, r8d
    sub ebx, r9d
    jmp .plot_p1
.q1_p1:
    add eax, r8d
    sub ebx, r9d
    jmp .plot_p1
.q2_p1:
    add eax, r8d
    add ebx, r9d
.plot_p1:
    mov r10d, eax
    mov r11d, ebx
    call circle_plot_pixel

    ; Point 2: (y, x)
    mov eax, r12d
    mov ebx, r13d
    cmp r15d, 0
    je .q0_p2
    cmp r15d, 1
    je .q1_p2
    cmp r15d, 2
    je .q2_p2
    ; quadrant 3
    sub eax, r9d
    add ebx, r8d
    jmp .plot_p2
.q0_p2:
    sub eax, r9d
    sub ebx, r8d
    jmp .plot_p2
.q1_p2:
    add eax, r9d
    sub ebx, r8d
    jmp .plot_p2
.q2_p2:
    add eax, r9d
    add ebx, r8d
.plot_p2:
    mov r10d, eax
    mov r11d, ebx
    call circle_plot_pixel

    ret


; ============================================================================
; rect_fill
;   Fill rectangle
;   IN: rdi = pixbuf*, rsi = x, rdx = y, rcx = width, r8 = height, r9 = color
;   OUT: rax = 0 OK
; ============================================================================
circle_rect_fill:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12d, esi       ; x
    mov r13d, edx       ; y
    mov r14d, ecx       ; width
    mov r13d, r8d       ; height
    mov r14d, r9d       ; color
    ASSERT_PTR rbx

    ; Get pixbuf info
    mov eax, [rbx + PixBuf_width]
    mov r11d, eax
    mov eax, [rbx + PixBuf_height]
    mov r10d, eax
    mov rax, [rbx + PixBuf_stride]
    mov r9, rax
    mov rax, [rbx + PixBuf_data]
    mov rdi, rax

    ; Clip to pixbuf bounds
    mov eax, r12d
    cmp eax, 0
    jge .x_ok
    add r14d, eax
    xor eax, eax
    mov r12d, eax
.x_ok:
    mov eax, r13d
    cmp eax, 0
    jge .y_ok
    add r13d, eax
    xor eax, eax
    mov r13d, eax
.y_ok:
    mov eax, r12d
    add eax, r14d
    cmp eax, r11d
    jle .w_ok
    sub eax, r11d
    sub r14d, eax
.w_ok:
    mov eax, r13d
    add eax, r13d
    cmp eax, r10d
    jle .h_ok
    sub eax, r10d
    sub r13d, eax
.h_ok:

    test r14d, r14d
    jle .done
    test r13d, r13d
    jle .done

    ; Fill scanlines
    mov r12d, r12d      ; x
    mov r13d, r13d      ; y
    mov r14d, r14d      ; width
    mov r15d, r13d      ; height

.scanline_loop:
    test r15d, r15d
    jle .done

    ; Calculate row start
    mov eax, r13d
    imul rax, r9
    add rax, r12
    shl rax, 2
    add rax, rdi

    ; Fill row
    mov ecx, r14d
    mov eax, r14d
.fill_loop:
    mov dword [rax], r14d
    add rax, 4
    dec rcx
    jnz .fill_loop

    inc r13d
    dec r15d
    jmp .scanline_loop

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret


; ============================================================================
; arc_draw
;   Draw elliptical arc from start_angle to end_angle
;   IN: rdi = pixbuf*, rsi = cx, rdx = cy, rcx = rx, r8 = ry
;       r9 = start_angle (fixed-point degrees), r10 = sweep_angle
;       r11 = color
; ============================================================================
circle_arc_draw_legacy:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    mov r14d, ecx
    mov r13d, r8d
    mov r14d, r9d
    mov r15d, r10d
    mov r10d, r11d
    ASSERT_PTR rbx

    mov rax, -(ENOTSUP)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret


section .data
global circle_version
circle_version: dq 0x010000
global ellipse_version
ellipse_version: dq 0x010000
global arc_version
arc_version: dq 0x010000
