; ============================================================================
; Native Backend — AMD DCN Complete Implementation
; ============================================================================

%include "inc/abi.inc"
%include "macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/image.inc"
%include "inc/backend.inc"
%include "inc/struct_offsets.inc"
%include "src/backend/family/amd/dcn/dcn_regs.inc"

extern arena_free
extern ddc_read_edid
extern edid_parse
extern edid_find_preferred_mode
extern fence_signal
extern fence_wait
extern pixbuf_destroy

section .text

; ---------------------------------------------------------------------------
; native_init
; ---------------------------------------------------------------------------
global native_init
native_init:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    
    mov rdi, rbx
    mov rcx, Backend.size
    xor eax, eax
    rep stosb
    
    mov [rbx + Backend.config], r12
    mov qword [rbx + Backend.outputs], 0
    mov qword [rbx + Backend.output_count], 0
    
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; native_deinit
; ---------------------------------------------------------------------------
global native_deinit
native_deinit:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
    
    mov rdi, [rbx + Backend.outputs]
    test rdi, rdi
    jz .done
.destroy_loop:
    test rdi, rdi
    jz .done
    mov rax, [rdi + Output.next]
    mov rsi, rdi
    mov rdi, [rbx + Backend.arena]
    call arena_free
    mov rdi, rax
    jmp .destroy_loop
.done:
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; native_modeset
; ---------------------------------------------------------------------------
global native_modeset
native_modeset:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13
    
    mov eax, [r13 + Mode.width]
    test eax, eax
    jz .bad_mode
    mov eax, [r13 + Mode.height]
    test eax, eax
    jz .bad_mode
    
    mov eax, [r12 + Output.crtc_index]
    mov r15d, eax
    
    mov r14, [rbx + Controller.mmio_base]
    test r14, r14
    jz .no_mmio
    
    call native_crtc_disable
    call native_crtc_program_timing
    call native_plane_program
    call native_crtc_enable
    
    mov eax, [r13 + Mode.width]
    mov [r12 + Output.width], eax
    mov eax, [r13 + Mode.height]
    mov [r12 + Output.height], eax
    mov qword [r12 + Output.current_mode], r13
    
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.bad_mode:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.no_mmio:
    mov rax, -(ENXIO)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; native_crtc_disable
; ---------------------------------------------------------------------------
global native_crtc_disable
native_crtc_disable:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    
    mov r14, [rbx + Controller.mmio_base]
    mov eax, [r12 + Output.crtc_index]
    mov r15d, eax
    
    mov rax, r15
    imul rax, CRTC_STRIDE
    add rax, r14
    add rax, CRTC_CONTROL
    mov eax, [rax]
    and eax, ~CRTC_CONTROL_ENABLE
    mov [rax], eax
    
    mov ecx, 100000
.wait_loop:
    mov rax, r15
    imul rax, CRTC_STRIDE
    add rax, r14
    add rax, CRTC_STATUS
    mov eax, [rax]
    test eax, CRTC_STATUS_ENABLED
    jz .disabled
    dec ecx
    jnz .wait_loop
    mov rax, -(ETIMEDOUT)
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.disabled:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; native_crtc_enable
; ---------------------------------------------------------------------------
global native_crtc_enable
native_crtc_enable:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    
    mov r14, [rbx + Controller.mmio_base]
    mov eax, [r12 + Output.crtc_index]
    mov r15d, eax
    
    mov rax, r15
    imul rax, CRTC_STRIDE
    add rax, r14
    add rax, CRTC_CONTROL
    mov eax, [rax]
    or eax, CRTC_CONTROL_ENABLE
    mov [rax], eax
    
    mov ecx, 100000
.wait_loop:
    mov rax, r15
    imul rax, CRTC_STRIDE
    add rax, r14
    add rax, CRTC_STATUS
    mov eax, [rax]
    test eax, CRTC_STATUS_ENABLED
    jnz .enabled
    dec ecx
    jnz .wait_loop
    mov rax, -(ETIMEDOUT)
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.enabled:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; native_crtc_program_timing
; ---------------------------------------------------------------------------
global native_crtc_program_timing
native_crtc_program_timing:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13
    ASSERT_PTR r14
    ASSERT_PTR r15
    
    ; r13 = mode*, r14 = mmio_base, r15 = crtc_index
    
%macro CRTC_ADDR 1
    mov rax, r15
    imul rax, CRTC_STRIDE
    add rax, r14
    add rax, %1
%endmacro
    
    mov eax, [r13 + Mode.htotal]
    dec eax
    CRTC_ADDR CRTC_HTOTAL
    mov [rax], eax
    
    mov eax, [r13 + Mode.hsync_start]
    dec eax
    CRTC_ADDR CRTC_H_START
    mov [rax], eax
    
    mov eax, [r13 + Mode.hsync_end]
    dec eax
    CRTC_ADDR CRTC_H_END
    mov [rax], eax
    
    mov eax, [r13 + Mode.vtotal]
    dec eax
    CRTC_ADDR CRTC_VTOTAL
    mov [rax], eax
    
    mov eax, [r13 + Mode.vsync_start]
    dec eax
    CRTC_ADDR CRTC_V_START
    mov [rax], eax
    
    mov eax, [r13 + Mode.vsync_end]
    dec eax
    CRTC_ADDR CRTC_V_END
    mov [rax], eax
    
    mov eax, [r13 + Mode.flags]
    test eax, MODE_FLAG_HSYNC_POSITIVE
    jz .hsync_neg
    CRTC_ADDR CRTC_H_SYNC_POLARITY
    mov eax, [rax]
    or eax, 1
    mov [rax], eax
    jmp .vsync_check
.hsync_neg:
    CRTC_ADDR CRTC_H_SYNC_POLARITY
    mov eax, [rax]
    and eax, ~1
    mov [rax], eax
.vsync_check:
    test eax, MODE_FLAG_VSYNC_POSITIVE
    jz .vsync_neg
    CRTC_ADDR CRTC_V_SYNC_POLARITY
    mov eax, [rax]
    or eax, 1
    mov [rax], eax
    jmp .done
.vsync_neg:
    CRTC_ADDR CRTC_V_SYNC_POLARITY
    mov eax, [rax]
    and eax, ~1
    mov [rax], eax
.done:
    mov eax, [r13 + Mode.pixel_clock]
    CRTC_ADDR CRTC_PIXEL_CLOCK
    mov [rax], eax
    
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; native_plane_program
; ---------------------------------------------------------------------------
global native_plane_program
native_plane_program:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13
    ASSERT_PTR r14
    ASSERT_PTR r15
    
    mov r13, [r12 + Output.current_surface]
    test r13, r13
    jz .no_surface
    mov r13, [r13 + Surface.current + SurfaceState.buffer]
    test r13, r13
    jz .no_surface
    mov r13, [r13 + Buffer.base]
    test r13, r13
    jz .no_surface
    
    mov r14, [rbx + Controller.mmio_base]
    mov eax, [r12 + Output.crtc_index]
    mov r15d, eax
    
%macro PLANE_ADDR 1
    mov rax, r15
    imul rax, PLANE_STRIDE
    add rax, r14
    add rax, %1
%endmacro
    
    PLANE_ADDR PLANE_SURFACE_ADDRESS
    mov [rax], r13
    PLANE_ADDR PLANE_SURFACE_ADDRESS_HIGH
    mov dword [rax], 0
    
    mov eax, [r12 + Output.width]
    mov edx, [r12 + Output.height]
    shl rdx, 16
    or rax, rdx
    PLANE_ADDR PLANE_SIZE
    mov [rax], rax
    
    mov eax, [r12 + Output.width]
    mov edx, [r12 + Output.height]
    shl rdx, 16
    or rax, rdx
    PLANE_ADDR PLANE_SOURCE_SIZE
    mov [rax], rax
    
    mov eax, [r12 + Output.stride]
    PLANE_ADDR PLANE_STRIDE
    mov [rax], eax
    
    mov eax, PLANE_FORMAT_BGRA8888
    PLANE_ADDR PLANE_FORMAT
    mov [rax], eax
    
    PLANE_ADDR PLANE_CONTROL
    mov eax, [rax]
    or eax, PLANE_CONTROL_ENABLE
    mov [rax], eax
    
.no_surface:
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; native_flip
; ---------------------------------------------------------------------------
global native_flip
native_flip:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13
    
    mov r15, [rbx + Controller.state]
    test r15, r15
    jz .fail
    
    mov eax, [r12 + Output.crtc_index]
    mov r15d, eax
    mov r14, [r15 + Controller.mmio_base]
    
    mov r13, [r13 + Buffer.base]
    test r13, r13
    jz .fail
    
    test r14, r14
    jz .no_fence
    mov rdi, [rbx + Backend.server]
    mov rsi, r14
    call fence_wait
    test rax, rax
    jnz .fail
    
.no_fence:
%macro PLANE_ADDR 1
    mov rax, r15
    imul rax, PLANE_STRIDE
    add rax, r14
    add rax, %1
%endmacro
    
    PLANE_ADDR PLANE_SURFACE_ADDRESS_NEXT
    mov [rax], r13
    PLANE_ADDR PLANE_SURFACE_ADDRESS_NEXT_HIGH
    mov dword [rax], 0
    
    PLANE_ADDR PLANE_CONTROL
    mov eax, [rax]
    or eax, PLANE_CONTROL_UPDATE
    mov [rax], eax
    
    test r14, r14
    jz .done
    mov rdi, [rbx + Backend.server]
    mov rsi, r14
    call fence_signal
    
.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.fail:
    mov rax, -(EIO)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; native_vblank_wait
; ---------------------------------------------------------------------------
global native_vblank_wait
native_vblank_wait:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    
    mov eax, [r12 + Output.crtc_index]
    mov r14d, eax
    mov r15, [rbx + Controller.mmio_base]
    
    call tv_time_now_ns
    mov rbx, rax
    add rbx, r13
    
.wait_loop:
    mov rax, r14
    imul rax, CRTC_STRIDE
    add rax, r15
    add rax, CRTC_STATUS
    mov eax, [rax]
    test eax, CRTC_STATUS_VSYNC_ACTIVE
    jnz .vsync
    call tv_time_now_ns
    cmp rax, rbx
    jae .timeout
    pause
    jmp .wait_loop
    
.vsync:
    call tv_time_now_ns
    add rax, 1000000
.wait_vsync_end:
    mov rax, r14
    imul rax, CRTC_STRIDE
    add rax, r15
    add rax, CRTC_STATUS
    mov eax, [rax]
    test eax, CRTC_STATUS_VSYNC_ACTIVE
    jz .done
    pause
    jmp .wait_vsync_end
    
.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.timeout:
    mov rax, -(ETIMEDOUT)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; native_hotplug
; ---------------------------------------------------------------------------
global native_hotplug
native_hotplug:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    ASSERT_PTR rbx
    
    mov r13, [rbx + Controller.outputs]
    test r13, r13
    jz .done
.hpd_loop:
    test r13, r13
    jz .done
    
    mov eax, [r13 + Output.hpd_irq]
    test eax, eax
    jz .next
    
    mov rdi, rax
    mov rsi, native_hpd_handler
    mov rdx, r13
    mov rcx, IRQ_EDGE
    call tv_irq_register
    test rax, rax
    jnz .fail
    
.next:
    mov r13, [r13 + Output.next]
    jmp .hpd_loop
.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.fail:
    mov rax, -(EIO)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; native_hpd_handler
; ---------------------------------------------------------------------------
global native_hpd_handler
native_hpd_handler:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    ASSERT_PTR rbx
    
    mov r12, [rbx + Output.controller]
    mov r13, [r12 + Controller.mmio_base]
    mov eax, [rbx + Output.hpd_register]
    movsxd rax, eax
    mov edx, [r13 + rax]
    
    test edx, edx
    jnz .connected
    call native_handle_disconnect
    jmp .done
.connected:
    call native_handle_connect
.done:
    mov rdi, [rbx + Output.hotplug_callback]
    test rdi, rdi
    jz .no_callback
    mov rsi, rbx
    mov rdx, rdx
    call rdi
.no_callback:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; native_handle_connect
; ---------------------------------------------------------------------------
global native_handle_connect
native_handle_connect:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    ASSERT_PTR rbx
    
    sub rsp, 256
    mov rdi, [rbx + Output.controller]
    mov rsi, rbx
    mov rdx, rsp
    call ddc_read_edid
    test rax, rax
    jnz .edid_fail
    
    mov rdi, rsp
    mov rsi, rbx
    add rsi, Output.edid
    call edid_parse
    test rax, rax
    jnz .edid_fail
    
    mov rdi, rsp
    mov rsi, rbx
    call edid_find_preferred_mode
    test rax, rax
    jz .edid_fail
    
    mov rdi, [rbx + Output.controller]
    mov rsi, rbx
    mov rdx, rax
    call native_modeset
    test rax, rax
    jnz .edid_fail
    
    add rsp, 256
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.edid_fail:
    add rsp, 256
    mov rax, -(EIO)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; native_handle_disconnect
; ---------------------------------------------------------------------------
global native_handle_disconnect
native_handle_disconnect:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    ASSERT_PTR rbx
    
    mov rax, [rbx + Output.current_surface]
    test rax, rax
    jz .done
    mov rdi, [rbx + Output.controller]
    mov rdi, [rdi + Backend.arena]
    mov rsi, rax
    call pixbuf_destroy
    mov qword [rbx + Output.current_surface], 0
.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; native_cursor
; ---------------------------------------------------------------------------
global native_cursor
native_cursor:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14d, ecx
    mov r15d, r8d
    ASSERT_PTR rbx
    ASSERT_PTR r12
    
    mov r14, [rbx + Controller.mmio_base]
    mov eax, [r12 + Output.crtc_index]
    mov r15d, eax
    
    mov rax, [r13 + Buffer.base]
    test rax, rax
    jz .fail
    
%macro CURSOR_ADDR 1
    mov rax, r15
    imul rax, CURSOR_STRIDE
    add rax, r14
    add rax, %1
%endmacro
    
    CURSOR_ADDR CURSOR_SURFACE_ADDRESS
    mov [rax], rax
    CURSOR_ADDR CURSOR_SURFACE_ADDRESS_HIGH
    mov dword [rax], 0
    
    mov eax, [r12 + Output.width]
    mov edx, [r12 + Output.height]
    shl rdx, 16
    or rax, rdx
    CURSOR_ADDR CURSOR_SIZE
    mov [rax], rax
    
    mov eax, r14d
    mov edx, r15d
    shl rdx, 16
    or rax, rdx
    CURSOR_ADDR CURSOR_POSITION
    mov [rax], rax
    
    mov eax, [r14 + CURSOR_CONTROL]
    or eax, CURSOR_CONTROL_ENABLE
    mov [r14 + CURSOR_CONTROL], eax
    
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.fail:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

section .data
global native_backend_version
native_backend_version: dq 0x010000
