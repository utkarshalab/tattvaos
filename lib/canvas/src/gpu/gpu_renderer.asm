; ============================================================================
; GPU Renderer — AMD GFX9 (RDNA/CDNA) Hardware Acceleration
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/fixed.inc"
%include "inc/gpu_render.inc"
%include "inc/externs.inc"

section .text

; ============================================================================
; gpu_renderer_init
;   Initialize GPU renderer for AMD GFX9
;   IN: rdi = gpu_renderer*, rsi = gpu_device*, rdx = arena
;   OUT: rax = 0 OK
; ============================================================================
global gpu_renderer_init
gpu_renderer_init:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r15, r14  ; save r15 in r14 temporarily
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13

    ; Store device and arena
    mov [rbx + GPU_DEV], r12

    ; Allocate command ring buffer (256KB)
    mov rdi, r13
    mov rsi, 256*1024
    call arena_alloc
    test rax, rax
    jz .oom
    mov [rbx + GPU_CMD_RING], rax
    mov qword [rbx + GPU_CMD_RING + 8], 0    ; write ptr
    mov qword [rbx + GPU_CMD_RING + 16], 256*1024  ; size

    ; Allocate compute ring buffer (64KB)
    mov rdi, r13
    mov rsi, 64*1024
    call arena_alloc
    test rax, rax
    jz .oom
    mov [rbx + GPU_COMP_RING], rax
    mov qword [rbx + GPU_COMP_RING + 8], 0
    mov qword [rbx + GPU_COMP_RING + 16], 64*1024

    ; Allocate descriptor heap (1MB)
    mov rdi, r13
    mov rsi, 1024*1024
    call arena_alloc
    test rax, rax
    jz .oom
    mov [rbx + GPU_DESC_HEAP], rax

    ; Initialize shader cache
    mov qword [rbx + GPU_SHADER_CACHE], 0

    ; Initialize pipeline cache
    mov qword [rbx + GPU_PIPELINE_CACHE], 0

    ; Initialize stats (simpler loop)
    lea rdi, [rbx + GPU_STATS]
    mov rcx, 8
    xor rax, rax
.init_stats_loop:
    mov qword [rdi], rax
    add rdi, 8
    dec rcx
    jnz .init_stats_loop

    ; Load default shaders
    call .load_default_shaders

    mov r14, r15
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.oom:
    mov rax, -ENOMEM
    mov r14, r15
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.load_default_shaders:
    ; Load pre-compiled shader binaries for:
    ; - Solid color fill (VS + PS)
    ; - Texture sampling (VS + PS)
    ; - Gradient evaluation (PS)
    ; - Path tessellation (CS)
    ; - Image scaling (CS)
    ; - Compositing (PS)
    ret

; ============================================================================
; gpu_renderer_deinit
;   Cleanup GPU renderer
; ============================================================================
global gpu_renderer_deinit
gpu_renderer_deinit:
    PROLOGUE
    ; Wait for GPU idle
    ; Free resources
    xor rax, rax
    leave
    ret

; ============================================================================
; gpu_submit_commands
;   Submit command buffer to GPU
; ============================================================================
global gpu_submit_commands
gpu_submit_commands:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Get write pointer
    mov rax, [rbx + GPU_CMD_RING + 8]
    test rax, rax
    jz .nothing_to_submit

    ; Write command buffer to GPU ring
    ; Using gpu_ring_write syscall
    mov rdi, [rbx + GPU_DEV]
    mov rsi, [rbx + GPU_CMD_RING]
    mov rdx, rax
    call gpu_ring_write
    test rax, rax
    jnz .submit_error

    ; Reset write pointer
    mov qword [rbx + GPU_CMD_RING + 8], 0

    ; Insert fence
    call gpu_fence_init
    mov [rbx + GPU_FRAME_FENCE], rax

.nothing_to_submit:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.submit_error:
    mov rax, -EINVAL
    EPILOGUE_RESTORE rbx, r12
    ret

; ============================================================================
; gpu_path_tessellate
;   Tessellate path on GPU (compute shader)
;   IN: rdi = gpu_renderer*, rsi = path*, rdx = flatness, rcx = output_buffer
; ============================================================================
global gpu_path_tessellate
gpu_path_tessellate:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov r14, rcx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r14

    ; Upload path data to GPU buffer
    call .upload_path_data

    ; Dispatch compute shader for tessellation
    ; Shader reads path, writes line segments to output buffer
    mov rdi, [rbx + GPU_COMP_RING]
    call .dispatch_tessellation_shader

    ; Wait for completion (or use fence)
    call gpu_submit_commands

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.upload_path_data:
    ret

.dispatch_tessellation_shader:
    ret

; ============================================================================
; gpu_gradient_render
;   Render gradient on GPU
; ============================================================================
global gpu_gradient_render
gpu_gradient_render:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13

    ; Create gradient texture or use shader evaluation
    ; Option 1: Generate 1D/2D gradient texture
    ; Option 2: Evaluate gradient in pixel shader

    ; Emit draw command for gradient-filled rect
    mov rdi, [rbx + GPU_CMD_RING]
    call .emit_gradient_draw

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.emit_gradient_draw:
    ret

; ============================================================================
; gpu_image_scale
;   Scale image on GPU (compute shader)
; ============================================================================
global gpu_image_scale
gpu_image_scale:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14d, ecx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13

    ; Upload source texture
    call .upload_texture

    ; Dispatch compute shader for scaling
    ; Supports: nearest, bilinear, bicubic, lanczos
    mov rdi, [rbx + GPU_COMP_RING]
    call .dispatch_scale_shader

    ; Download result
    call .download_texture

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.upload_texture:
    ret

.dispatch_scale_shader:
    ret

.download_texture:
    ret

; ============================================================================
; gpu_composite
;   Composite surfaces on GPU
; ============================================================================
global gpu_composite
gpu_composite:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi        ; src surfaces[]
    mov r13d, edx       ; count
    mov r14, rcx        ; dst
    ASSERT_PTR rbx

    ; Set up blend states for each surface
    ; Emit draw commands
    mov rdi, [rbx + GPU_CMD_RING]
    call .emit_composite_commands

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.emit_composite_commands:
    ret

; ============================================================================
; gpu_wait_idle
;   Wait for GPU to complete all work
; ============================================================================
global gpu_wait_idle
gpu_wait_idle:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Wait on frame fence
    mov rdi, [rbx + GPU_FRAME_FENCE]
    call fence_wait

    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ============================================================================
; gpu_get_stats
;   Get GPU performance stats
; ============================================================================
global gpu_get_stats
gpu_get_stats:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Copy stats
    mov rdi, r12
    lea rsi, [rbx + GPU_STATS]
    mov rcx, 64
    call memcopy

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

section .data
global gpu_renderer_version
gpu_renderer_version: dq 0x010000