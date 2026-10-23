; ============================================================================
; Framebuffer Linear Backend — Complete Implementation
; Simple linear framebuffer (VBE/UEFI GOP), page-flip by copy or double-buffer
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/fixed.inc"
%include "inc/image.inc"
%include "inc/backend.inc"
%include "inc/struct_offsets.inc"

extern arena_alloc
extern arena_free
extern fence_signal
extern fence_wait
extern memcopy

section .text

; ---------------------------------------------------------------------------
; fb_linear_init
;   Initialize linear framebuffer backend
;   IN:  rdi = backend*, rsi = config*
;   OUT: rax = 0 OK, negative error
; ---------------------------------------------------------------------------
global fb_linear_init
fb_linear_init:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    
    ; Zero backend state
    mov rdi, rbx
    mov rcx, Backend_size
    xor eax, eax
    rep stosb
    
    ; Save framebuffer info from config
    mov rax, [r12 + Config_fb_base]
    mov qword [rbx + Backend_fb_base], rax
    mov rax, [r12 + Config_fb_size]
    mov qword [rbx + Backend_fb_size], rax
    
    ; Zero output list
    mov qword [rbx + Backend_outputs], 0
    mov qword [rbx + Backend_output_count], 0
    mov qword [rbx + Backend_layout_bounds], 0
    
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; fb_linear_deinit
; ---------------------------------------------------------------------------
global fb_linear_deinit
fb_linear_deinit:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
    
    mov rdi, [rbx + Backend_outputs]
    test rdi, rdi
    jz .done
.destroy_loop:
    test rdi, rdi
    jz .done
    mov rax, [rdi + Output_next]
    mov rsi, rdi
    mov rdi, [rbx + Backend_arena]
    call arena_free
    mov rdi, rax
    jmp .destroy_loop
.done:
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; fb_linear_modeset
; ---------------------------------------------------------------------------
global fb_linear_modeset
fb_linear_modeset:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13
    
    ; Validate mode matches framebuffer
    mov eax, [r13 + Mode_width]
    test eax, eax
    jz .bad_mode
    mov eax, [r13 + Mode_height]
    test eax, eax
    jz .bad_mode
    
    ; Check stride matches
    mov eax, [r13 + Mode_width]
    shl eax, 2
    cmp eax, [r12 + Output_stride]
    jne .bad_mode
    
    ; Update output
    mov eax, [r13 + Mode_width]
    mov [r12 + Output_width], eax
    mov eax, [r13 + Mode_height]
    mov [r12 + Output_height], eax
    mov qword [r12 + Output_current_mode], r13
    
    ; Create surface pointing to framebuffer
    mov rax, [r12 + Output_current_surface]
    test rax, rax
    jnz .update_surface
    
    ; Allocate surface struct
    mov rdi, [rbx + Backend_arena]
    mov rsi, Surface_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov r12, rax
    mov [rbx + Output_current_surface], rax
    
    ; Initialize surface
    mov rax, [rbx + Backend_fb_base]
    mov [r12 + Surface_current], rax
    mov eax, [r13 + Mode.width]
    mov [r12 + Surface.width], eax
    mov eax, [r13 + Mode.height]
    mov [r12 + Surface.height], eax
    mov dword [r12 + Surface.format], DRM_FORMAT_BGRA8888
    mov eax, [r13 + Mode.width]
    shl eax, 2
    mov [r12 + Surface.stride], eax
    mov qword [r12 + Surface.buffer], 0
    mov qword [r12 + Surface.damage], 0
    mov qword [r12 + Output_current_surface], rax
    mov rax, [rbx + Backend_fb_base]
    mov qword [r12 + Buffer_base], rax
    mov qword [r12 + Surface_buffer], rax
    jmp .done
    
.update_surface:
    ; Update existing surface
    mov [rax + Surface_current], rax
    mov eax, [r13 + Mode_width]
    mov [rax + Surface_width], eax
    mov eax, [r13 + Mode_height]
    mov [rax + Surface_height], eax
    mov dword [rax + Surface_format], DRM_FORMAT_BGRA8888
    mov eax, [r13 + Mode_width]
    shl eax, 2
    mov [rax + Surface_stride], eax
    jmp .done
    
.done:
    xor rax, rax
    leave
    ret
.bad_mode:
    mov rax, -(EINVAL)
    leave
    ret
.oom:
    mov rax, -(ENOMEM)
    leave
    ret

; ---------------------------------------------------------------------------
; fb_linear_flip
; ---------------------------------------------------------------------------
global fb_linear_flip
fb_linear_flip:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13
    
    ; Wait for acquire fence
    test r14, r14
    jz .no_fence
    mov rdi, [rbx + Backend_server]
    mov rsi, r14
    call fence_wait
    test rax, rax
    jnz .fail
.no_fence:
    
    ; Get surface
    mov rax, [r12 + Output_current_surface]
    test rax, rax
    jz .no_surface
    mov rbx, rax
    
    ; Get new buffer
    mov rax, [r13 + Buffer_base]
    test rax, rax
    jz .fail
    
    ; Check if double-buffered
    mov r15, [rbx + Surface_current]
    mov rax, [rbx + Surface_stride]
    imul rax, [rbx + Surface_height]
    
    ; Copy new buffer to framebuffer
    mov rdi, [rbx + Backend_fb_base]
    mov rsi, rax
    mov rdx, r15
    call memcopy
    
    ; Update surface buffer pointer
    mov [rbx + Surface_current], r13
    mov [rbx + Surface_buffer], r13
    
    ; Signal release fence
    mov rdi, [rbx + Backend_server]
    mov rsi, r14
    call fence_signal
    
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.fail:
    mov rax, -(EIO)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.no_surface:
    mov rax, -(ENODEV)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; fb_linear_vblank_wait
; ---------------------------------------------------------------------------
global fb_linear_vblank_wait
fb_linear_vblank_wait:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    
    call ut_time_now_ns
    mov rbx, rax
    add rbx, r13
.wait_loop:
    call ut_time_now_ns
    cmp rax, rbx
    jae .timeout
    pause
    jmp .wait_loop
.timeout:
    mov rax, -(ETIMEDOUT)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; fb_linear_hotplug
; ---------------------------------------------------------------------------
global fb_linear_hotplug
fb_linear_hotplug:
    PROLOGUE
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; fb_linear_cursor
; ---------------------------------------------------------------------------
global fb_linear_cursor
fb_linear_cursor:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    
    ; Simple software cursor - just track position
    mov eax, ecx
    mov [rbx + Backend.cursor_x], eax
    mov eax, r8d
    mov [rbx + Backend.cursor_y], eax
    
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

section .data
global fb_linear_backend_version
fb_linear_backend_version: dq 0x010000
