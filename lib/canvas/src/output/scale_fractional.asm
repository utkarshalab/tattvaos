; ============================================================================
; Fractional Scale — Non-Integer Scale Factors (1.25x, 1.5x, 1.75x, 2.25x, etc.)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/fixed.inc"
%include "inc/struct_offsets.inc"
%include "inc/canvas_client.inc"

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
;   Render with fractional scale
;   IN:  rdi = frame_ctx*, rsi = surface*, rdx = scale_method
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
    ; Get surface buffer
    mov r14, [r12 + Surface.current + SurfaceState.buffer]
    test r14, r14
    jz .done

    ; Get buffer
    mov r15, [r12 + Server.buffer_table]
    mov rdi, r15
    mov rsi, r14
    call handle_resolve
    test rax, rax
    jz .done
    mov r14, rax

    ; Get scale factor
    mov rax, [rbx + FrameCtx.output]
    mov rax, [rax + Output.scale]

    mov rdi, [rbx + FrameCtx.framebuffer]
    mov rsi, [r14 + Buffer.base]
    mov rdx, [r14 + Buffer.width]
    mov rcx, [r14 + Buffer.height]
    mov r8, [r14 + Buffer.stride]
    mov r9d, [rbx + FrameCtx.width]
    mov r10d, [rbx + FrameCtx.height]
    mov r11, [rbx + FrameCtx.stride]
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
;   Calculate destination rect for fractional scale
; ---------------------------------------------------------------------------
global scale_fractional_calculate_dest
scale_fractional_calculate_dest:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13
    ASSERT_PTR r14

    ; src_w * scale = dst_w
    mov rax, r12
    imul rax, r13
    shr rax, 16
    mov [r14 + 0], eax

    mov rax, r12
    imul rax, r13
    shr rax, 16
    mov [r14 + 4], eax

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

section .data
global scale_fractional_version
scale_fractional_version: dq 0x010000
