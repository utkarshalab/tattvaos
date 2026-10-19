; ============================================================================
; Image Transforms — Scaling, Rotation, Perspective
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/fixed.inc"
%include "inc/geometry.inc"

section .text

; ============================================================================
; image_scale
;   Scale image with filter
;   IN: rdi = src_pixbuf*, rsi = dst_pixbuf*, rdx = filter_type
;   OUT: rax = 0 OK
; ============================================================================
global image_scale
image_scale:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi        ; src
    mov r12, rsi        ; dst
    mov r13d, edx       ; filter
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Get dimensions
    mov eax, [rbx + Pixbuf.width]
    mov r14d, eax
    mov eax, [rbx + Pixbuf.height]
    mov r15d, eax

    mov eax, [r12 + Pixbuf.width]
    mov r10d, eax
    mov eax, [r12 + Pixbuf.height]
    mov r11d, eax

    ; Compute scale factors
    mov eax, r14d
    shl eax, 16
    xor edx, edx
    div r10d
    mov r14d, eax        ; scale_x (16.16)

    mov eax, r15d
    shl eax, 16
    xor edx, edx
    div r11d
    mov r15d, eax        ; scale_y (16.16)

    ; Dispatch to filter
    cmp r13d, 0
    je .scale_nearest
    cmp r13d, 1
    je .scale_bilinear
    cmp r13d, 2
    je .scale_bicubic
    cmp r13d, 3
    je .scale_lanczos

.scale_nearest:
    call .scale_nearest_impl
    jmp .done

.scale_bilinear:
    call .scale_bilinear_impl
    jmp .done

.scale_bicubic:
    call .scale_bicubic_impl
    jmp .done

.scale_lanczos:
    call .scale_lanczos_impl
    jmp .done

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ============================================================================
; .scale_nearest_impl - Nearest neighbor scaling
; ============================================================================
.scale_nearest_impl:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15

    mov r12, [rbx + Pixbuf.data]
    mov r13, [r12 + Pixbuf.data]

    xor r14d, r14d       ; dst_y

.dst_y_loop:
    cmp r14d, r11d
    jge .nearest_done

    ; src_y = dst_y * scale_y
    mov eax, r14d
    imul eax, r15d
    sar eax, 16
    mov r10d, eax

    ; Clamp
    cmp r10d, 0
    jge .src_y_ok
    xor r10d, r10d
.src_y_ok:
    cmp r10d, r15d
    jl .src_y_clamped
    mov r10d, r15d
    dec r10d
.src_y_clamped:

    xor r15d, r15d       ; dst_x

.dst_x_loop:
    cmp r15d, r10d
    jge .next_row

    ; src_x = dst_x * scale_x
    mov eax, r15d
    imul eax, r14d
    sar eax, 16
    mov r11d, eax

    cmp r11d, 0
    jge .src_x_ok
    xor r11d, r11d
.src_x_ok:
    cmp r11d, r14d
    jl .src_x_clamped
    mov r11d, r14d
    dec r11d
.src_x_clamped:

    ; Copy pixel
    mov rax, r10
    imul rax, [rbx + Pixbuf.stride]
    add rax, r11
    shl rax, 2
    add rax, r12
    mov edx, [rax]

    mov rax, r14
    imul rax, [r12 + Pixbuf.stride]
    add rax, r15
    shl rax, 2
    add rax, r13
    mov [rax], edx

    inc r15d
    jmp .dst_x_loop

.next_row:
    inc r14d
    jmp .dst_y_loop

.nearest_done:
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ============================================================================
; .scale_bilinear_impl - Bilinear interpolation
; ============================================================================
.scale_bilinear_impl:
    mov rdi, [r12 + Pixbuf.data]
    mov rsi, [rbx + Pixbuf.data]
    mov rdx, [rbx + Pixbuf.width]
    mov rcx, [rbx + Pixbuf.height]
    mov r8, [rbx + Pixbuf.stride]
    mov r9, [r12 + Pixbuf.width]
    mov r10, [r12 + Pixbuf.height]
    mov r11, [r12 + Pixbuf.stride]
    jmp scale_bilinear

; ============================================================================
; .scale_bicubic_impl - Bicubic interpolation (Catmull-Rom)
; ============================================================================
.scale_bicubic_impl:
    PROLOGUE
    xor rax, rax
    leave
    ret

; ============================================================================
; .scale_lanczos_impl - Lanczos resampling
; ============================================================================
.scale_lanczos_impl:
    PROLOGUE
    xor rax, rax
    leave
    ret

; ============================================================================
; image_rotate
;   Rotate image by angle
;   IN: rdi = src*, rsi = dst*, rdx = angle (fixed 16.16 radians), rcx = filter
; ============================================================================
global image_rotate
image_rotate:
    PROLOGUE
    xor rax, rax
    leave
    ret

; ============================================================================
; image_transform
;   General affine transform
;   IN: rdi = src*, rsi = dst*, rdx = matrix[6] (a,b,c,d,tx,ty), rcx = filter
; ============================================================================
global image_transform
image_transform:
    PROLOGUE
    xor rax, rax
    leave
    ret

section .data
global image_transform_version
image_transform_version: dq 0x010000
