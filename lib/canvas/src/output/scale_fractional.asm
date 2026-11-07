; ============================================================================
; Fractional Scale — Non-Integer Scale Factors (1.25x, 1.5x, 1.75x, 2.25x, etc.)
; ============================================================================
; Helpers, not yet part of drawing (OUT-08, PRO-16 decide how an output's
; scale applies): an output's scale as 16.16, a size times it, and one
; surface's buffer stretched over its output's whole frame (a fullscreen
; app drawn smaller than the screen), nearest neighbour at a whole scale and
; bilinear otherwise. The stretch copies: it is for opaque buffers.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/fixed.inc"
%include "inc/struct_offsets.inc"
%include "inc/canvas_client.inc"
%include "inc/render.inc"
%include "inc/backend.inc"

extern handle_resolve
extern sw_scale_bilinear
extern sw_scale_nearest

%define SCALE_NEAREST    0
%define SCALE_BILINEAR   1
%define SCALE_BICUBIC    2

section .text

; ---------------------------------------------------------------------------
; scale_fractional_init
; ---------------------------------------------------------------------------
global scale_fractional_init
scale_fractional_init:
    PROLOGUE
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; scale_fractional_compute
;   Compute scale factors for fractional scaling
;   IN:  rdi = output*, rsi = scale_numerator, rdx = scale_denominator
;   OUT: rax = 0 OK, output.scale updated
; ---------------------------------------------------------------------------
global scale_fractional_compute
scale_fractional_compute:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx

    test r12, r12
    jz .zero
    test r13, r13
    jz .zero

    ; scale = numerator / denominator (16.16 fixed)
    mov rax, r12
    shl rax, 16
    xor rdx, rdx
    div r13

    mov [rdi + Output.scale], rax
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.zero:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; scale_fractional_render
;   A surface's buffer stretched over the frame's output, nearest neighbour
;   (method 0) or bilinear (1); bilinear whatever is asked when the output's
;   scale is not a whole number
;   IN:  rdi = frame_ctx*, rsi = surface*, rdx = scale_method
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global scale_fractional_render
scale_fractional_render:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Get output scale
    mov rax, [rbx + FrameCtx.output]
    mov rax, [rax + Output.scale]

    ; Check if integer scale
    mov rcx, rax
    and rcx, 0xFFFF
    test rcx, rcx
    jz .integer_scale

    ; Fractional scale - use bilinear
    mov r13, SCALE_BILINEAR

.integer_scale:
    ; The surface's buffer, through its client's server
    mov rsi, [r12 + Surface.current + SurfaceState.buffer]
    test rsi, rsi
    jz .done
    mov rax, [r12 + Surface.client]
    test rax, rax
    jz .done
    mov rax, [rax + Client.server]
    mov rdi, [rax + Server.buffer_table]
    call handle_resolve
    test rax, rax
    jz .done
    mov r14, rax

    ; Over the output's own pixels, all of them
    mov r15, [rbx + FrameCtx.output]
    mov rdi, [r15 + Output.framebuffer]
    mov rsi, [r14 + Buffer.base]
    mov rdx, [r14 + Buffer.width]
    mov rcx, [r14 + Buffer.height]
    mov r8, [r14 + Buffer.stride]
    mov r9d, [r15 + Output.width]
    mov r10d, [r15 + Output.height]
    mov r11, [r15 + Output.stride]
    cmp r13, SCALE_NEAREST
    je .nearest
    call sw_scale_bilinear
    jmp .done
.nearest:
    call sw_scale_nearest

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; scale_fractional_calculate_dest
;   A size times a scale, rounded down
;   IN:  rdi = width, rsi = height, rdx = scale (16.16), rcx = where the
;        two scaled dwords go
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global scale_fractional_calculate_dest
scale_fractional_calculate_dest:
    ASSERT_PTR rcx
    mov rax, rdi
    imul rax, rdx
    shr rax, 16
    mov [rcx], eax
    mov rax, rsi
    imul rax, rdx
    shr rax, 16
    mov [rcx + 4], eax
    xor eax, eax
    ret

section .data
global scale_fractional_version
scale_fractional_version: dq 0x010000
