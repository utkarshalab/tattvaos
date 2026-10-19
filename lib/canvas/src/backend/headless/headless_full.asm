; ============================================================================
; Headless Backend — Complete Implementation
; Frames kept in memory, no display hardware
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/fixed.inc"
%include "inc/image.inc"
%include "inc/backend.inc"
%include "inc/struct_offsets.inc"
%include "inc/externs.inc"

section .text

; ---------------------------------------------------------------------------
; headless_init
;   Initialize headless backend
;   IN:  rdi = backend*, rsi = config*
;   OUT: rax = 0 OK, negative error
; ---------------------------------------------------------------------------
global headless_init
headless_init:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    
    ; Zero backend state
    mov rdi, rbx
    mov rcx, Backend.size
    xor eax, eax
    rep stosb
    
    ; Save config
    mov [rbx + Backend.config], r12
    
    ; Initialize output list
    mov qword [rbx + Backend.outputs], 0
    mov qword [rbx + Backend.output_count], 0
    mov qword [rbx + Backend.layout_bounds], 0
    
    ; Create virtual frame clock
    mov rdi, [rbx + Backend.arena]
    mov rsi, FrameClock_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov qword [rbx + Backend.frame_clock], rax
    
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; headless_deinit
;   Deinitialize headless backend
;   IN:  rdi = backend*
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global headless_deinit
headless_deinit:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
    
    ; Destroy all outputs
    mov rdi, [rbx + Backend.outputs]
    test rdi, rdi
    jz .done
.destroy_loop:
    test rdi, rdi
    jz .done
    mov rax, [rdi + Output.next]
    ; Free output resources
    mov rsi, rdi
    mov rdi, [rbx + Backend.arena]
    call arena_free
    mov rdi, rax
    jmp .destroy_loop
.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; headless_modeset
;   Set display mode on virtual output
;   IN:  rdi = controller*, rsi = output*, rdx = mode*
;   OUT: rax = 0 OK, negative error
; ---------------------------------------------------------------------------
global headless_modeset
headless_modeset:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13
    
    ; Validate mode
    mov eax, [r13 + Mode.width]
    test eax, eax
    jz .bad_mode
    mov eax, [r13 + Mode.height]
    test eax, eax
    jz .bad_mode
    
    ; Update output dimensions
    mov eax, [r13 + Mode.width]
    mov [r12 + Output.width], eax
    mov eax, [r13 + Mode.height]
    mov [r12 + Output.height], eax
    
    ; Allocate backing pixbuf if needed
    mov rax, [r12 + Output.current_surface]
    test rax, rax
    jnz .update_surface
    
    ; Create new surface
    mov rdi, [rbx + Backend.arena]
    mov esi, [r13 + Mode.width]
    mov edx, [r13 + Mode.height]
    mov rcx, DRM_FORMAT_BGRA8888
    call pixbuf_create
    test rax, rax
    jz .oom
    mov [r12 + Output.current_surface], rax
    jmp .done
    
.update_surface:
    ; Check if surface needs resize
    mov eax, [rax + Surface.width]
    cmp eax, [r13 + Mode.width]
    jne .resize
    mov eax, [rax + Surface.height]
    cmp eax, [r13 + Mode.height]
    je .done
    
.resize:
    ; Destroy old surface
    mov rdi, [rbx + Backend.arena]
    mov rsi, rax
    call pixbuf_destroy
    ; Create new surface
    mov rdi, [rbx + Backend.arena]
    mov esi, [r13 + Mode.width]
    mov edx, [r13 + Mode.height]
    mov rcx, DRM_FORMAT_BGRA8888
    call pixbuf_create
    test rax, rax
    jz .oom
    mov [r12 + Output.current_surface], rax
    
.done:
    mov qword [r12 + Output.current_mode], r13
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.bad_mode:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; headless_flip
;   Page flip (no-op for headless, just damage tracking)
;   IN:  rdi = controller*, rsi = output*, rdx = buffer*, rcx = fence*
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global headless_flip
headless_flip:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    
    ; Update surface buffer pointer
    mov rax, [r12 + Output.current_surface]
    test rax, rax
    jz .done
    mov [rax + Surface.buffer], r13
    
    ; Signal acquire fence if present
    test r14, r14
    jz .done
    mov rdi, [rbx + Backend.server]
    mov rsi, r14
    call fence_signal
    
.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; headless_vblank_wait
;   Wait for vblank (simulated with timer)
;   IN:  rdi = controller*, rsi = output*, rdx = timeout_ns
;   OUT: rax = 0 OK, -ETIMEDOUT on timeout
; ---------------------------------------------------------------------------
global headless_vblank_wait
headless_vblank_wait:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    
    ; Get current time
    call tv_time_now_ns
    mov rbx, rax
    add rbx, r13
    
.wait_loop:
    call tv_time_now_ns
    cmp rax, rbx
    jae .timeout
    ; Yield (in real impl, would wait on IRQ)
    pause
    jmp .wait_loop
    
.timeout:
    mov rax, -(ETIMEDOUT)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; headless_hotplug
;   Handle hotplug events (simulated)
;   IN:  rdi = controller*
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global headless_hotplug
headless_hotplug:
    PROLOGUE
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; headless_cursor
;   Set cursor (no-op for headless)
;   IN:  rdi = controller*, rsi = output*, rdx = buffer*, rcx = hot_x, r8 = hot_y
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global headless_cursor
headless_cursor:
    PROLOGUE
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; headless_create_virtual_output
;   Create a virtual output for headless backend
;   IN:  rdi = backend*, rsi = width, rdx = height, rcx = format
;   OUT: rax = output*, 0 on error
; ---------------------------------------------------------------------------
global headless_create_virtual_output
headless_create_virtual_output:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    ASSERT_PTR rbx
    
    ; Allocate output structure
    mov rdi, [rbx + Backend.arena]
    mov rsi, Output_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax
    
    ; Initialize output
    mov qword [rbx + Output.x], 0
    mov qword [rbx + Output.y], 0
    mov [rbx + Output.width], r12d
    mov [rbx + Output.height], r13d
    mov byte [rbx + Output.connected], 1
    mov qword [rbx + Output.controller], rdi
    mov dword [rbx + Output.crtc_index], 0
    mov qword [rbx + Output.current_surface], 0
    mov qword [rbx + Output.current_mode], 0
    mov qword [rbx + Output.surfaces], 0
    mov qword [rbx + Output.toplevels], 0
    mov qword [rbx + Output.hotplug_callback], 0
    mov qword [rbx + Output.next], 0
    mov dword [rbx + Output.stride], 0
    
    ; Create initial surface
    mov rdi, [rdi + Backend.arena]
    mov esi, r12d
    mov edx, r13d
    mov rcx, r14
    call pixbuf_create
    test rax, rax
    jz .oom
    mov [rbx + Output.current_surface], rax
    
    ; Add to output list
    mov rdi, [rdi + Backend.outputs]
    test rdi, rdi
    jz .first_output
    mov rsi, rdi
.find_end:
    mov rax, [rsi + Output.next]
    test rax, rax
    jz .append
    mov rsi, rax
    jmp .find_end
.append:
    mov [rsi + Output.next], rbx
    jmp .done
.first_output:
    mov rdi, [rdi + Backend.arena]
    mov qword [rdi + Backend.outputs], rbx
    inc qword [rdi + Backend.output_count]
    
.done:
    mov rax, rbx
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.oom:
    mov rax, 0
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

section .data
global headless_backend_version
headless_backend_version: dq 0x010000