; ============================================================================
; Line Primitives — Line Segment Operations
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/geometry.inc"
%include "inc/externs.inc"

section .text

; ============================================================================
; line_draw
;   Draw line segment using Bresenham algorithm
;   IN:  rdi = pixbuf*, rsi = x1, rdx = y1, rcx = x2, r8 = y2, r9 = color
;   OUT: rax = 0 OK
; ============================================================================
global line_draw
line_draw:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    mov r14d, ecx
    mov r15d, r8d
    ASSERT_PTR rbx
    mov r10d, r9d

    ; Get pixbuf info
    mov eax, [rbx + Pixbuf.width]
    mov r11d, eax
    mov eax, [rbx + Pixbuf.height]
    mov r9d, eax
    mov rax, [rbx + Pixbuf.stride]
    mov r8, rax
    mov rax, [rbx + Pixbuf.data]
    mov rdi, rax

    ; Clip line to pixbuf bounds
    call line_clip_cohen_sutherland
    test rax, rax
    jz .done

    ; Bresenham line algorithm
    ; r12 = x1, r13 = y1, r14 = x2, r15 = y2
    mov eax, r14d
    sub eax, r12d
    cdq
    xor eax, edx
    sub eax, edx
    mov r10d, eax                    ; dx = abs(x2 - x1)
    mov esi, r12d
    cmp esi, r14d
    jle .x_increasing
    neg esi
    mov esi, -1
    jmp .dx_done
.x_increasing:
    mov esi, 1
.dx_done:
    mov eax, r15d
    sub eax, r13d
    cdq
    xor eax, edx
    sub eax, edx
    mov r11d, eax                    ; dy = abs(y2 - y1)
    mov edi, r13d
    cmp edi, r15d
    jle .y_increasing
    neg edi
    mov edi, -1
    jmp .dy_done
.y_increasing:
    mov edi, 1
.dy_done:

    cmp r10d, r11d
    jge .steep_false
    ; Steep line (dy > dx) - swap roles
    mov eax, r10d
    mov r10d, r11d
    mov r11d, eax
    mov eax, esi
    mov esi, edi
    mov edi, eax
.steep_false:
    ; r10 = major axis delta, r11 = minor axis delta
    ; esi = step major, edi = step minor
    mov r14d, r11d
    shl r14d, 1
    sub r14d, r10d                   ; error = 2*dy - dx
    mov r15, rdi                     ; framebuffer

    mov r9d, r10d
    inc r9d
.draw_loop:
    ; Plot pixel
    ; r12 = x, r13 = y (or swapped for steep)
    call line_plot_pixel
    
    test r14d, r14d
    jle .no_adjust
    add r13d, edi
    sub r14d, r10d
    sub r14d, r10d
.no_adjust:
    add r12d, esi
    dec r9d
    jnz .draw_loop

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret


; ============================================================================
; line_plot_pixel
;   Plot pixel at (r12, r13) or (r13, r12) for steep lines
;   IN:  rdi = framebuffer, rsi = stride, r12 = x, r13 = y, r10d = color
; ============================================================================
line_plot_pixel:
    ; Check bounds
    cmp r12d, 0
    jl .skip
    cmp r13d, 0
    jl .skip
    cmp r12d, [rsp + 8]  ; width saved on stack
    jge .skip
    cmp r13d, [rsp + 12] ; height saved on stack
    jge .skip

    ; Calculate pixel address: fb + y * stride + x * 4
    mov rax, r13
    imul rax, rsi
    add rax, r12
    shl rax, 2
    add rax, rdi
    mov dword [rax], r10d
    ret
.skip:
    ret


; ============================================================================
; line_clip_cohen_sutherland
;   Clip line to rectangle using Cohen-Sutherland algorithm
;   IN:  r12=x1, r13=y1, r14=x2, r15=y2, r9=width, r11=height
;   OUT: rax=0 if rejected, 1 if accepted; registers updated
; ============================================================================
line_clip_cohen_sutherland:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi

    ; Outcodes
    %define OUT_LEFT    1
    %define OUT_RIGHT   2
    %define OUT_BOTTOM  4
    %define OUT_TOP     8

.clip_loop:
    ; Compute outcodes
    xor rax, rax
    mov rbx, r12
    cmp rbx, 0
    jge .x_ok
    or al, OUT_LEFT
.x_ok:
    mov rbx, [rsp + 8]
    cmp rbx, r12
    jg .x1_ok
    or al, OUT_RIGHT
.x1_ok:
    mov rbx, r13
    cmp rbx, 0
    jge .y_ok
    or al, OUT_BOTTOM
.y_ok:
    mov rbx, [rsp + 12]
    cmp rbx, r13
    jg .y1_ok
    or al, OUT_TOP
.y1_ok:
    mov r10b, al

    ; Second point
    xor rax, rax
    mov rbx, r14
    cmp rbx, 0
    jge .x2_ok
    or al, OUT_LEFT
.x2_ok:
    mov rbx, [rsp + 8]
    cmp rbx, r14
    jg .x2_ok2
    or al, OUT_RIGHT
.x2_ok2:
    mov rbx, r15
    cmp rbx, 0
    jge .y2_ok
    or al, OUT_BOTTOM
.y2_ok:
    mov rbx, [rsp + 12]
    cmp rbx, r15
    jg .y2_ok2
    or al, OUT_TOP
.y2_ok2:
    mov r11b, al

    ; Trivial accept
    test r10b, r11b
    jz .accept

    ; Trivial reject
    test r10b, r11b
    jnz .reject

    ; Clip against edges
    ; Left
    test r10b, OUT_LEFT
    jz .test_right
    mov eax, r14d
    sub eax, r12d
    mov ebx, r15d
    sub ebx, r13d
    imul ebx, eax
    mov eax, r12d
    cdq
    idiv ebx
    add r13d, eax
    mov r12d, 0
    jmp .clip_loop

.test_right:
    test r10b, OUT_RIGHT
    jz .test_bottom
    mov eax, [rsp + 8]
    sub eax, r12d
    mov ebx, r15d
    sub ebx, r13d
    imul ebx, eax
    mov eax, r14d
    cdq
    idiv ebx
    add r13d, eax
    mov r12d, [rsp + 8]
    jmp .clip_loop

.test_bottom:
    test r10b, OUT_BOTTOM
    jz .test_top
    mov eax, r13d
    imul eax, r14d
    sub eax, r12d
    mov ebx, r15d
    sub ebx, r13d
    idiv ebx
    add r12d, eax
    mov r13d, 0
    jmp .clip_loop

.test_top:
    test r10b, OUT_TOP
    jz .accept
    mov eax, [rsp + 12]
    sub eax, r13d
    imul eax, r14d
    sub eax, r12d
    mov ebx, r15d
    sub ebx, r13d
    idiv ebx
    add r12d, eax
    mov r13d, [rsp + 12]
    jmp .clip_loop

.accept:
    mov rax, 1
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.reject:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret


; ============================================================================
; line_intersect_rect
;   Check if line intersects rectangle
;   IN:  rdi = x1, rsi = y1, rdx = x2, rcx = y2
;        r8 = rect_x, r9 = rect_y, r10 = rect_w, r11 = rect_h
;   OUT: rax = 1 if intersects, 0 if not
; ============================================================================
global line_intersect_rect
line_intersect_rect:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8

    ; Check if either endpoint inside rect
    mov eax, r12d
    cmp eax, r8d
    jl .check_p2
    cmp eax, r10d
    jge .check_p2
    mov eax, r13d
    cmp eax, r9d
    jl .check_p2
    cmp eax, r11d
    jge .check_p2
    mov rax, 1
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.check_p2:
    mov eax, r13d
    cmp eax, r8d
    jl .cohen_sutherland
    cmp eax, r10d
    jge .cohen_sutherland
    mov eax, r12d
    cmp eax, r9d
    jl .cohen_sutherland
    cmp eax, r11d
    jge .cohen_sutherland

.cohen_sutherland:
    ; Cohen-Sutherland line-rect intersection
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    mov rcx, r14
    mov r8, r15
    call line_clip_cohen_sutherland
    ret

section .data
global line_version
line_version: dq 0x010000