; ============================================================================
; GPU Render — GPU-Accelerated Composition Path (blit + fill + planes)
; Falls back to software renderer when GPU unavailable
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/render.inc"

; struct offsets (hoisted above use)
%define GpuRenderer_size    24

section .text

struc GpuRenderer
    .base:          resq 1
    .gpu:           resq 1
    .sw_fallback:   resb 1
endstruc

; ---------------------------------------------------------------------------
; gpu_render_init
; ---------------------------------------------------------------------------
global gpu_render_init
gpu_render_init:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13
    mov rdi, [rbx + Server.arena]
    mov rsi, GpuRenderer_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax
    mov qword [rbx + GpuRenderer.base], rdi
    mov rax, [r12 + Server.gpu]
    mov qword [rbx + GpuRenderer.gpu], rax
    test rax, rax
    jz .sw_only
    mov rax, [rax + GpuDevice.enabled]
    test al, al
    jnz .gpu_ok
.sw_only:
    mov byte [rbx + GpuRenderer.sw_fallback], 1
    jmp .done
.gpu_ok:
    mov byte [rbx + GpuRenderer.sw_fallback], 0
.done:
    mov qword [rdi + Server.gpu_renderer], rbx
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; gpu_render_surface
;   GPU path: SDMA copy for opaque, SW blend for alpha
; ---------------------------------------------------------------------------
global gpu_render_surface
gpu_render_surface:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    cmp byte [rbx + GpuRenderer.sw_fallback], 1
    je .fallback
    ; check opaque fast path
    mov rax, [r12 + Surface.current + SurfaceState.opaque]
    test rax, rax
    jz .fallback
    ; TODO: emit SDMA copy via gfx9_emit_copy + fence
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.fallback:
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call sw_render_surface
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; gpu_render_fill
; ---------------------------------------------------------------------------
global gpu_render_fill
gpu_render_fill:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
    cmp byte [rbx + GpuRenderer.sw_fallback], 1
    je .fallback
    ; TODO: gfx9_emit_fill
    EPILOGUE_RESTORE rbx
    ret
.fallback:
    call fill_solid
    EPILOGUE_RESTORE rbx
    ret

section .data
global gpu_render_version
gpu_render_version: dq 0x010000
