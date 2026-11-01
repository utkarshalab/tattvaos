; ============================================================================
; Headless Backend — Frames Kept in Memory, No Display Hardware
; Used for testing, CI, and remote-only servers
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/fixed.inc"
%include "inc/image.inc"
%include "inc/backend.inc"
%include "inc/render.inc"
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

    ; Allocate headless backend state
    mov rdi, [rbx + Backend.arena]
    mov rsi, 256
    call arena_alloc
    test rax, rax
    jz .oom
    mov r13, rax

    ; Fill backend state
    mov qword [rbx + Backend.state], r13
    mov qword [rbx + Backend.outputs], 0
    mov qword [rbx + Backend.output_count], 0

    ; Create a virtual output, honoring the configured framebuffer geometry.
    mov rdi, rbx
    mov rsi, r12
    call headless_create_virtual_output
    test rax, rax
    js .oom

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; headless_deinit
;   Cleanup headless backend
; ---------------------------------------------------------------------------
global headless_deinit
headless_deinit:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov rax, [rbx + Backend.state]
    test rax, rax
    jz .done

    mov r12, [rbx + Backend.outputs]
.free_outputs:
    test r12, r12
    jz .free_state
    mov rax, [r12 + Output.next]
    push rax
    mov rdi, [r12 + Output.framebuffer]
    test rdi, rdi
    jz .skip_pixbuf
    call pixbuf_destroy
.skip_pixbuf:
    mov rdi, [rbx + Backend.arena]
    mov rsi, r12
    call arena_free
    pop r12
    jmp .free_outputs
.free_state:

    ; Free backend state
    mov rdi, [rbx + Backend.arena]
    mov rsi, rax
    call arena_free

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; headless_modeset
;   Set mode on virtual output (no-op, just updates state)
;   IN:  rdi = backend*, rsi = output*, rdx = mode*
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global headless_modeset
headless_modeset:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Update output current mode
    mov rax, [r12 + Output.current_mode]
    mov [r12 + Output.current_mode], rdx
    mov [r12 + Output.current_mode], rdx

    ; Update output geometry
    mov eax, [rdx + Mode.width]
    mov [r12 + Output.width], eax
    mov eax, [rdx + Mode.height]
    mov [r12 + Output.height], eax

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; headless_flip
;   Flip to new buffer (copy to output framebuffer)
;   IN:  rdi = backend*, rsi = output*, rdx = buffer*, rcx = fence
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
    ASSERT_PTR r13

    ; Wait for acquire fence
    test r14, r14
    jz .no_fence
    mov rdi, [rbx + Backend.server]
    mov rsi, r14
    mov rdx, 0
    call fence_wait
    test rax, rax
    jnz .fence_fail

.no_fence:
    ; Copy buffer to output framebuffer
    ; Output framebuffer is in output->framebuffer
    mov rax, [r12 + Output.framebuffer]
    test rax, rax
    jz .no_fb

    mov rdi, rax
    mov rsi, [r13 + Buffer.base]
    mov rdx, [r12 + Output.width]
    mov rcx, [r12 + Output.height]
    mov r8, [r12 + Output.stride]
    mov r9, [r13 + Buffer.stride]
    call blit_copy
    test rax, rax
    jnz .copy_fail

    ; Signal release fence
    test r14, r14
    jz .done
    mov rdi, [rbx + Backend.server]
    mov rsi, r14
    call fence_signal

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.no_fb:
    mov rax, -(ENXIO)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.fence_fail:
    mov rax, -(EFENCE_WAIT)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.copy_fail:
    mov rax, -(EIO)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; headless_vblank_wait
;   Wait for vblank (simulated with timer)
;   IN:  rdi = backend*, rsi = output*, rdx = sequence
;   OUT: rax = PresentInfo*
; ---------------------------------------------------------------------------
global headless_vblank_wait
headless_vblank_wait:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Simulate vblank at 60Hz (16.67ms)
    mov rdi, 16666667  ; 16.67ms in ns
    call ut_time_sleep_ns

    mov rdi, [rbx + Backend.arena]
    mov rsi, PresentInfo_size
    call arena_alloc
    test rax, rax
    jz .present_oom
    mov dword [rax + PresentInfo.kind], PRESENT_KIND_VSYNC
    mov [rax + PresentInfo.seq], r13
    push rax
    call ut_time_now_ns
    mov rdx, rax
    pop rax
    mov [rax + PresentInfo.time], rdx
    mov qword [rax + PresentInfo.refresh_ns], 16666667
    mov dword [rax + PresentInfo.flags], 0
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.present_oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; headless_hotplug
;   Hotplug callback (no-op for headless)
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
; ---------------------------------------------------------------------------
global headless_cursor
headless_cursor:
    PROLOGUE
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; headless_create_virtual_output (internal)
; ---------------------------------------------------------------------------
headless_create_virtual_output:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r15, rsi
    mov r12, [rbx + Backend.arena]
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Allocate output struct
    mov rdi, r12
    mov rsi, 128
    call arena_alloc
    test rax, rax
    jz .oom
    mov r13, rax

    mov r8d, 1920
    mov r9d, 1080
    test r15, r15
    jz .geometry_ready
    cmp dword [r15 + Config.fb_width], 0
    je .geometry_ready
    mov r8d, [r15 + Config.fb_width]
    mov r9d, [r15 + Config.fb_height]
.geometry_ready:
    ; Allocate framebuffer using configured geometry.
    mov rdi, r12
    mov esi, r8d
    mov edx, r9d
    mov rcx, DRM_FORMAT_BGRA8888
    call pixbuf_create
    test rax, rax
    jz .oom
    mov r14, rax

    ; Fill output
    mov qword [r13 + Output.id], 1
    mov qword [r13 + Output.backend], rbx
    mov qword [r13 + Output.framebuffer], r14
    mov [r13 + Output.width], r8d
    mov [r13 + Output.height], r9d
    mov eax, r8d
    shl rax, 2
    mov [r13 + Output.stride], rax
    mov qword [r13 + Output.scale], FIX_ONE
    mov dword [r13 + Output.rotation], 0

    ; Add to backend output list
    mov rax, [rbx + Backend.outputs]
    mov [r13 + Output.next], rax
    mov [rbx + Backend.outputs], r13
    inc qword [rbx + Backend.output_count]

    mov rax, r13
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

section .data

global headless_version
headless_version: dq 0x010000
