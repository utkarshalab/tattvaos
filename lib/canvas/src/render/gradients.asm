; ============================================================================
; Gradient Rendering — Linear, Radial, Conical Gradients
; Software implementation with fixed-point math
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/geometry.inc"
%include "inc/fixed.inc"
%include "inc/gradients.inc"
%include "inc/externs.inc"

section .text

; ============================================================================
; gradient_create
;   Create a new gradient
;   IN: rdi = gradient*, rsi = type (GRADIENT_*), rdx = spread
;   OUT: rax = 0 OK
; ============================================================================
global gradient_create
gradient_create:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12d, esi       ; type
    mov r13d, edx       ; spread
    ASSERT_PTR rbx

    mov dword [rbx + Gradient_TYPE], r12d
    mov dword [rbx + Gradient_SPREAD], r13d
    mov qword [rbx + Gradient_STOPS], 0
    mov dword [rbx + Gradient_STOP_COUNT], 0
    mov dword [rbx + Gradient_STOP_CAP], 0

    ; Initialize identity matrix
    mov dword [rbx + Gradient_MATRIX + 0], FIX_ONE      ; m00 = 1
    mov dword [rbx + Gradient_MATRIX + 4], 0            ; m01 = 0
    mov dword [rbx + Gradient_MATRIX + 8], 0            ; m02 = 0
    mov dword [rbx + Gradient_MATRIX + 12], 0           ; m10 = 0
    mov dword [rbx + Gradient_MATRIX + 16], FIX_ONE     ; m11 = 1
    mov dword [rbx + Gradient_MATRIX + 20], 0           ; m12 = 0
    mov dword [rbx + Gradient_MATRIX + 24], 0           ; m20 = 0
    mov dword [rbx + Gradient_MATRIX + 28], 0           ; m21 = 0
    mov dword [rbx + Gradient_MATRIX + 32], FIX_ONE     ; m22 = 1

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ============================================================================
; gradient_add_stop
;   Add color stop to gradient
;   IN: rdi = gradient*, rsi = offset (0.0-1.0 fixed), rdx = color (ARGB)
;   OUT: rax = 0 OK, -ENOMEM on failure
; ============================================================================
global gradient_add_stop
gradient_add_stop:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12d, esi       ; offset
    mov r13d, edx       ; color
    ASSERT_PTR rbx

    ; Check if we need to grow array
    mov eax, [rbx + Gradient_STOP_COUNT]
    cmp eax, [rbx + Gradient_STOP_CAP]
    jl .has_space

    ; Need to grow - allocate new array
    lea eax, [rax + 4]
    imul eax, ColorStop_SIZE
    mov rdi, rax
    call arena_alloc
    test rax, rax
    jz .oom

    ; Copy old stops if any
    mov r14, [rbx + Gradient_STOPS]
    test r14, r14
    jz .no_copy
    mov ecx, [rbx + Gradient_STOP_COUNT]
    test ecx, ecx
    jz .no_copy
    push rdi
    push rsi
    mov rsi, r14
    mov rdi, rax
    mov ecx, [rbx + Gradient_STOP_COUNT]
    imul ecx, ColorStop_SIZE
    call memcopy
    pop rsi
    pop rdi

    ; Free old array if it was dynamically allocated
    ; (In our arena allocator, we don't free individual allocations)
.no_copy:
    mov [rbx + Gradient_STOPS], rax
    mov eax, [rbx + Gradient_STOP_COUNT]
    add eax, 4
    mov [rbx + Gradient_STOP_CAP], eax

.has_space:
    ; Add new stop
    mov r14, [rbx + Gradient_STOPS]
    mov eax, [rbx + Gradient_STOP_COUNT]
    imul eax, ColorStop_SIZE
    add r14, rax
    mov dword [r14 + ColorStop_OFFSET], r12d
    mov dword [r14 + ColorStop_COLOR], r13d
    inc dword [rbx + Gradient_STOP_COUNT]

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.oom:
    mov rax, -ENOMEM
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ============================================================================
; gradient_set_linear
;   Configure linear gradient endpoints
;   IN: rdi = gradient*, rsi = x0, rdx = y0, rcx = x1, r8 = y1
; ============================================================================
global gradient_set_linear
gradient_set_linear:
    PROLOGUE
    mov dword [rdi + Gradient_TYPE], GRADIENT_LINEAR
    mov dword [rdi + Gradient_X0], esi
    mov dword [rdi + Gradient_Y0], edx
    mov dword [rdi + Gradient_X1], ecx
    mov dword [rdi + Gradient_Y1], r8d
    xor rax, rax
    leave
    ret

; ============================================================================
; gradient_set_radial
;   Configure radial gradient
;   IN: rdi = gradient*, rsi = cx, rdx = cy, rcx = r0, r8 = r1, r9 = fx, r10 = fy
; ============================================================================
global gradient_set_radial
gradient_set_radial:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov dword [rbx + Gradient_TYPE], GRADIENT_RADIAL
    mov dword [rbx + Gradient_CX], esi
    mov dword [rbx + Gradient_CY], edx
    mov dword [rbx + Gradient_R0], ecx
    mov dword [rbx + Gradient_R1], r8d
    mov dword [rbx + Gradient_X0], r9d      ; focal x
    mov dword [rbx + Gradient_Y0], r10d     ; focal y
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ============================================================================
; gradient_set_conical
;   Configure conical (angular) gradient
;   IN: rdi = gradient*, rsi = cx, rdx = cy, rcx = angle (radians fixed)
; ============================================================================
global gradient_set_conical
gradient_set_conical:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    mov dword [rbx + Gradient_TYPE], GRADIENT_CONICAL
    mov dword [rbx + Gradient_CX], esi
    mov dword [rbx + Gradient_CY], edx
    mov dword [rbx + Gradient_ANGLE], ecx
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ============================================================================
; gradient_set_matrix
;   Set transform matrix for gradient
;   IN: rdi = gradient*, rsi = matrix[9] (3x3 fixed-point)
; ============================================================================
global gradient_set_matrix
gradient_set_matrix:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov ecx, 9
.copy_loop:
    mov eax, [r12]
    mov [rbx + Gradient_MATRIX + rcx*4 - 4], eax
    add r12, 4
    dec ecx
    jnz .copy_loop

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ============================================================================
; gradient_interpolate
;   Interpolate color at position t (0.0-1.0 fixed)
;   IN: rdi = gradient*, rsi = t (fixed 16.16)
;   OUT: rax = color (ARGB)
; ============================================================================
global gradient_interpolate
gradient_interpolate:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12d, esi       ; t
    ASSERT_PTR rbx

    mov eax, [rbx + Gradient_STOP_COUNT]
    test eax, eax
    jz .default_color

    cmp eax, 1
    je .single_stop

    ; Clamp t based on spread mode
    mov r13d, [rbx + Gradient_SPREAD]
    call .clamp_t

    ; Find interval
    mov r14, [rbx + Gradient_STOPS]
    mov r15d, [rbx + Gradient_STOP_COUNT]
    dec r15d            ; n-1 intervals
    xor r13d, r13d      ; index = 0

.find_interval:
    cmp r13d, r15d
    jge .last_stop

    mov eax, [r14 + r13*ColorStop_SIZE + ColorStop_SIZE + ColorStop_OFFSET]
    cmp r12d, eax
    jl .found_interval

    inc r13d
    jmp .find_interval

.found_interval:
    ; r13 = index of stop1, stop0 = r13-1
    dec r13d

    ; stop0
    mov eax, [r14 + r13*ColorStop_SIZE + ColorStop_OFFSET]
    mov r12d, eax       ; t0
    mov eax, [r14 + r13*ColorStop_SIZE + ColorStop_COLOR]
    mov r14d, eax       ; c0

    ; stop1
    mov eax, [r14 + (r13+1)*ColorStop_SIZE + ColorStop_OFFSET]
    mov r13d, eax       ; t1
    mov eax, [r14 + (r13+1)*ColorStop_SIZE + ColorStop_COLOR]
    mov r15d, eax       ; c1

    ; Interpolation factor: (t - t0) / (t1 - t0)
    sub r13d, r12d      ; t1 - t0
    mov eax, r11d       ; current t
    sub eax, r12d       ; t - t0
    shl eax, 16
    xor edx, edx
    div r13d            ; factor in eax (fixed)
    mov r12d, eax

    ; Interpolate ARGB channels
    call .interp_channels
    jmp .done

.last_stop:
    ; Return last stop color
    mov r14, [rbx + Gradient_STOPS]
    mov eax, [rbx + Gradient_STOP_COUNT]
    dec eax
    imul eax, ColorStop_SIZE
    add r14, rax
    mov eax, [r14 + ColorStop_COLOR]
    jmp .done

.single_stop:
    mov r14, [rbx + Gradient_STOPS]
    mov eax, [r14 + ColorStop_COLOR]
    jmp .done

.default_color:
    mov eax, 0xFF000000
    jmp .done

.interp_channels:
    ; r12 = factor, r14 = c0, r15 = c1
    ; Alpha
    movzx eax, al
    movzx ebx, byte [r15 + 3]
    sub ebx, eax
    imul ebx, r12d
    sar ebx, 16
    add eax, ebx
    mov r8b, al

    ; Blue
    movzx eax, byte [r14 + 0]
    movzx ebx, byte [r15 + 0]
    sub ebx, eax
    imul ebx, r12d
    sar ebx, 16
    add eax, ebx
    mov r9b, al

    ; Green
    movzx eax, byte [r14 + 1]
    movzx ebx, byte [r15 + 1]
    sub ebx, eax
    imul ebx, r12d
    sar ebx, 16
    add eax, ebx
    mov r10b, al

    ; Red
    movzx eax, byte [r14 + 2]
    movzx ebx, byte [r15 + 2]
    sub ebx, eax
    imul ebx, r12d
    sar ebx, 16
    add eax, ebx
    mov r11b, al

    ; Combine
    mov eax, r8d
    shl eax, 24
    or eax, r11d
    shl eax, 8
    or eax, r10d
    shl eax, 8
    or eax, r9d
    ret

.clamp_t:
    ; r12d = t, r13d = spread mode
    cmp r13d, SPREAD_PAD
    je .clamp_pad
    cmp r13d, SPREAD_REPEAT
    je .clamp_repeat
    ; SPREAD_REFLECT
    ; t = abs(t % 2)
    ; if t > 1: t = 2 - t
    mov eax, r12d
    cdq
    mov ecx, 2*FIX_ONE
    idiv ecx
    mov eax, edx
    test eax, eax
    jns .reflect_pos
    neg eax
.reflect_pos:
    cmp eax, FIX_ONE
    jle .clamp_done
    mov ecx, 2*FIX_ONE
    sub ecx, eax
    mov eax, ecx
    jmp .clamp_done

.clamp_repeat:
    mov eax, r12d
    cdq
    mov ecx, FIX_ONE
    idiv ecx
    mov eax, edx
    test eax, eax
    jns .clamp_done
    add eax, FIX_ONE
    jmp .clamp_done

.clamp_pad:
    cmp r12d, 0
    jge .check_max
    xor eax, eax
    mov r12d, eax
    ret
.check_max:
    cmp r12d, FIX_ONE
    jle .clamp_done
    mov r12d, FIX_ONE
.clamp_done:
    ret

.done:
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ============================================================================
; gradient_render_rect
;   Render gradient to rectangle in pixbuf
;   IN: rdi = pixbuf*, rsi = gradient*, rdx = x, rcx = y, r8 = w, r9 = h
;   OUT: rax = 0 OK
; ============================================================================
global gradient_render_rect
gradient_render_rect:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi        ; gradient
    mov r13d, edx       ; x
    mov r14d, ecx       ; y
    mov r13d, r8d       ; w
    mov r14d, r9d       ; h
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Get pixbuf info
    mov eax, [rbx + Pixbuf.stride]
    mov r15, rax
    mov rax, [rbx + Pixbuf.data]
    mov rdi, rax
    mov rsi, rbx        ; save pixbuf for clip checks

    ; Clip rectangle
    mov eax, [rsi + Pixbuf.width]
    mov r10d, eax
    mov eax, [rsi + Pixbuf.height]
    mov r11d, eax

    mov eax, r13d
    test eax, eax
    jle .done
    mov eax, r14d
    test eax, eax
    jle .done

    ; y loop
    mov r13d, r13d      ; x
    mov r14d, r14d      ; y
    mov r15d, r15d      ; w
    mov r10d, r10d      ; h

.y_loop:
    test r10d, r10d
    jle .done

    ; Check y bounds
    cmp r14d, 0
    jl .skip_y
    cmp r14d, r11d
    jge .skip_y

    ; x loop
    mov r11d, r13d      ; x
    mov r12d, r15d      ; w
.x_loop:
    test r12d, r12d
    jle .next_row

    ; Check x bounds
    cmp r11d, 0
    jl .skip_x
    cmp r11d, r10d
    jge .skip_x

    ; Compute gradient parameter t for this pixel
    ; This is simplified - real implementation applies gradient matrix
    mov eax, r11d
    sub eax, r13d       ; x - x0
    shl eax, 16
    mov ebx, r15d       ; w
    xor edx, edx
    div ebx
    mov rsi, rax        ; t

    ; Get color from gradient
    mov rdi, r12        ; gradient
    call gradient_interpolate

    ; Write pixel
    mov rdi, [rsi + Pixbuf.data]
    mov rax, r14
    imul rax, [rsi + Pixbuf.stride]
    add rax, r11
    shl rax, 2
    add rax, rdi
    mov dword [rax], eax

.skip_x:
    inc r11d
    dec r12d
    jmp .x_loop

.next_row:
    inc r14d
    dec r10d
    jmp .y_loop

.skip_y:
    inc r14d
    dec r10d
    jmp .y_loop

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

section .data
global gradient_version
gradient_version: dq 0x010000