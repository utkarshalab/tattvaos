; ============================================================================
; Framebuffer Linear Backend — Boot FB (VBE/UEFI GOP)
; Simple linear framebuffer, page-flip by copy or double-buffer
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/fixed.inc"
%include "inc/backend.inc"
%include "inc/struct_offsets.inc"
%include "inc/externs.inc"

; struct offsets (hoisted above use)
%define FbLinearState_fb_base     0
%define FbLinearState.fb_base 0
%define FbLinearState_width       8
%define FbLinearState.width 8
%define FbLinearState_height      12
%define FbLinearState.height 12
%define FbLinearState_stride      16
%define FbLinearState.stride 16
%define FbLinearState_format      20
%define FbLinearState.format 20
%define FbLinearState_back_buffer 24
%define FbLinearState.back_buffer 24
%define FbLinearState_size        32

section .text

; ---------------------------------------------------------------------------
; fb_linear_init
;   Initialize fb_linear backend
;   IN:  rdi = backend*, rsi = config*
;   OUT: rax = 0 OK, negative error
; ---------------------------------------------------------------------------
global fb_linear_init
fb_linear_init:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Get boot framebuffer info from Tattva
    ; TODO: tv_fb_get_info syscall or boot info struct
    ; For now, use config
    mov eax, [r12 + Config.fb_width]
    test eax, eax
    jnz .has_fb

    ; Try to discover via VBE/UEFI GOP
    call fb_linear_discover
    test rax, rax
    jnz .oom

.has_fb:
    ; Allocate backend state
    mov rdi, [rbx + Backend.arena]
    mov rsi, 256
    call arena_alloc
    test rax, rax
    jz .oom
    mov r13, rax

    mov qword [rbx + Backend.state], r13
    mov qword [rbx + Backend.outputs], 0
    mov qword [rbx + Backend.output_count], 0

    ; Map boot framebuffer
    ; TODO: tv_mmio_map with MEM_WC for framebuffer
    ; For now, assume identity mapped
    mov rax, [r12 + Config.fb_base]
    mov qword [r13 + FbLinearState.fb_base], rax
    mov eax, [r12 + Config.fb_width]
    mov dword [r13 + FbLinearState.width], eax
    mov eax, [r12 + Config.fb_height]
    mov dword [r13 + FbLinearState.height], eax
    mov eax, [r12 + Config.fb_stride]
    mov dword [r13 + FbLinearState.stride], eax
    mov eax, [r12 + Config.fb_format]
    mov dword [r13 + FbLinearState.format], eax

    ; Create output for boot FB
    call fb_linear_create_output

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; fb_linear_discover
;   Discover boot framebuffer (VBE/UEFI GOP)
;   OUT: rax = 0 OK, negative error
; ---------------------------------------------------------------------------
fb_linear_discover:
    PROLOGUE
    ; TODO: Read boot info from Tattva
    ; For UEFI GOP: read GOP mode info
    ; For VBE: query VBE mode
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; fb_linear_deinit
; ---------------------------------------------------------------------------
global fb_linear_deinit
fb_linear_deinit:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov rax, [rbx + Backend.state]
    test rax, rax
    jz .done

    ; Free output
    ; TODO

    ; Free state
    mov rdi, [rbx + Backend.arena]
    mov rsi, rax
    call arena_free

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; fb_linear_modeset
;   Set mode (not really supported on boot FB, but can switch VBE modes)
; ---------------------------------------------------------------------------
global fb_linear_modeset
fb_linear_modeset:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Boot FB typically fixed mode
    ; Could switch VBE mode if supported
    ; For now, just update output geometry
    mov rax, [r12 + Output.current_mode]
    mov [r12 + Output.current_mode], rdx

    mov eax, [rdx + Mode.width]
    mov [r12 + Output.width], eax
    mov eax, [rdx + Mode.height]
    mov [r12 + Output.height], eax

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; fb_linear_flip
;   Flip to new buffer
;   If double-buffered: copy to back buffer, swap
;   If single-buffered: copy to front buffer
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
    mov rdi, [rbx + Backend.server]
    mov rsi, r14
    mov rdx, 0
    call fence_wait
    test rax, rax
    jnz .fence_fail

.no_fence:
    ; Get framebuffer base
    mov rax, [rbx + Backend.state]
    mov rax, [rax + FbLinearState.fb_base]
    test rax, rax
    jz .no_fb

    ; Check if double-buffered
    mov r15, [rax + FbLinearState.back_buffer]
    test r15, r15
    jz .single_buffered

    ; Double-buffered: copy to back buffer
    mov rdi, r15
    mov rsi, [r13 + Buffer.base]
    mov rdx, [r12 + Output.width]
    mov rcx, [r12 + Output.height]
    mov r8, [rax + FbLinearState.stride]
    mov r9, [r13 + Buffer.stride]
    call blit_copy
    test rax, rax
    jnz .copy_fail

    ; Swap front/back (atomic pointer swap)
    ; TODO: Atomic swap with memory barrier
    jmp .signal_fence

.single_buffered:
    ; Single-buffered: copy directly to front
    mov rdi, rax
    mov rsi, [r13 + Buffer.base]
    mov rdx, [r12 + Output.width]
    mov rcx, [r12 + Output.height]
    mov r8, [rax + FbLinearState.stride]
    mov r9, [r13 + Buffer.stride]
    call blit_copy
    test rax, rax
    jnz .copy_fail

.signal_fence:
    ; Signal release fence
    test r14, r14
    jz .done
    mov rdi, [rbx + Backend.server]
    mov rsi, r14
    call fence_signal

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.no_fb:
    mov rax, -(ENXIO)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.fence_fail:
    mov rax, -(EFENCE_WAIT)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.copy_fail:
    mov rax, -(EIO)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; fb_linear_vblank_wait
;   Wait for vblank (use VBE vblank if available, else sleep)
; ---------------------------------------------------------------------------
global fb_linear_vblank_wait
fb_linear_vblank_wait:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Try VBE vblank wait first
    ; TODO: tv_irq_wait for VBE vblank IRQ

    ; Fallback: sleep for frame time
    mov rax, [r12 + Output.current_mode]
    mov rax, [rax + Mode.refresh_ns]
    mov rdi, rax
    call tv_time_sleep_ns

    ; Return present info
    xor rax, rax
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
;   Set cursor (not supported on boot FB, use software cursor)
; ---------------------------------------------------------------------------
global fb_linear_cursor
fb_linear_cursor:
    PROLOGUE
    ; Software cursor only
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; fb_linear_create_output (internal)
; ---------------------------------------------------------------------------
fb_linear_create_output:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, [rbx + Backend.arena]
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Allocate output
    mov rdi, r12
    mov rsi, 128
    call arena_alloc
    test rax, rax
    jz .oom
    mov r13, rax

    ; Get FB info from state
    mov rax, [rbx + Backend.state]
    mov r14, [rax + FbLinearState.fb_base]

    ; Fill output
    mov qword [r13 + Output.id], 1
    mov qword [r13 + Output.backend], rbx
    mov qword [r13 + Output.framebuffer], r14
    mov eax, [rax + FbLinearState.width]
    mov [r13 + Output.width], eax
    mov eax, [rax + FbLinearState.height]
    mov [r13 + Output.height], eax
    mov eax, [rax + FbLinearState.stride]
    mov [r13 + Output.stride], eax
    mov qword [r13 + Output.scale], FIX_ONE
    mov dword [r13 + Output.rotation], 0

    ; Add to list
    mov rax, [rbx + Backend.outputs]
    mov [r13 + Output.next], rax
    mov [rbx + Backend.outputs], r13
    inc qword [rbx + Backend.output_count]

    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

section .data


global fb_linear_version
fb_linear_version: dq 0x010000
