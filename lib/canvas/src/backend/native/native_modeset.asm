; ============================================================================
; Native Modeset - AMD DCN Display Engine Programming
; Atomic commit to hardware registers
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

section .text

global native_modeset
native_modeset:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13

    mov r14, [rbx + Backend.state]
    mov r15, [r14 + Controller.state]
    test r15, r15
    jz .no_controller

    mov eax, [r13 + Mode.width]
    test eax, eax
    jz .bad_mode
    mov eax, [r13 + Mode.height]
    test eax, eax
    jz .bad_mode

    mov r14, [r15 + Controller.mmio_base]
    test r14, r14
    jz .no_mmio

    mov eax, [r12 + Output.crtc_index]
    mov r15d, eax

    call native_crtc_disable
    call native_crtc_program_timing
    call native_plane_program
    call native_crtc_enable

    mov rax, [r13 + Mode.width]
    mov [r12 + Output.width], eax
    mov eax, [r13 + Mode.height]
    mov [r12 + Output.height], eax
    mov qword [r12 + Output.current_mode], r13

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.no_controller: RETURN_ERROR ENXIO
.bad_mode: RETURN_ERROR EINVAL
.no_mmio: RETURN_ERROR ENXIO

native_crtc_disable:
    PROLOGUE_SAVE rbx, r12, r13
    mov eax, [r14 + DCN_CRTC_CONTROL + r15 * 4]
    and eax, ~1
    mov [r14 + DCN_CRTC_CONTROL + r15 * 4], eax
    mov ecx, 100000
.wait_loop:
    mov eax, [r14 + DCN_CRTC_STATUS + r15 * 4]
    test eax, 1
    jz .disabled
    dec ecx
    jnz .wait_loop
    RETURN_ERROR ETIMEDOUT
.disabled:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

native_crtc_enable:
    PROLOGUE_SAVE rbx, r12, r13
    mov eax, [r14 + DCN_CRTC_CONTROL + r15 * 4]
    or eax, 1
    mov [r14 + DCN_CRTC_CONTROL + r15 * 4], eax
    mov ecx, 100000
.wait_loop:
    mov eax, [r14 + DCN_CRTC_STATUS + r15 * 4]
    test eax, 1
    jnz .enabled
    dec ecx
    jnz .wait_loop
    RETURN_ERROR ETIMEDOUT
.enabled:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

native_crtc_program_timing:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, r13
    mov r12, r14
    mov r13, r15

    mov eax, [rbx + Mode.htotal]
    dec eax
    mov [r12 + DCN_CRTC_HTOTAL + r13 * 4], eax

    mov eax, [rbx + Mode.hsync_start]
    dec eax
    mov [r12 + DCN_CRTC_H_START + r13 * 4], eax

    mov eax, [rbx + Mode.hsync_end]
    dec eax
    mov [r12 + DCN_CRTC_H_END + r13 * 4], eax

    mov eax, [rbx + Mode.vtotal]
    dec eax
    mov [r12 + DCN_CRTC_VTOTAL + r13 * 4], eax

    mov eax, [rbx + Mode.vsync_start]
    dec eax
    mov [r12 + DCN_CRTC_V_START + r13 * 4], eax

    mov eax, [rbx + Mode.vsync_end]
    dec eax
    mov [r12 + DCN_CRTC_V_END + r13 * 4], eax

    mov eax, [rbx + Mode.flags]
    test eax, MODE_FLAG_HSYNC_POSITIVE
    jz .hsync_neg
    mov eax, [r12 + DCN_CRTC_H_SYNC_POLARITY + r13 * 4]
    or eax, 1
    mov [r12 + DCN_CRTC_H_SYNC_POLARITY + r13 * 4], eax
    jmp .vsync_check

.hsync_neg:
    mov eax, [r12 + DCN_CRTC_H_SYNC_POLARITY + r13 * 4]
    and eax, ~1
    mov [r12 + DCN_CRTC_H_SYNC_POLARITY + r13 * 4], eax

.vsync_check:
    test eax, MODE_FLAG_VSYNC_POSITIVE
    jz .vsync_neg
    mov eax, [r12 + DCN_CRTC_V_SYNC_POLARITY + r13 * 4]
    or eax, 1
    mov [r12 + DCN_CRTC_V_SYNC_POLARITY + r13 * 4], eax
    jmp .done

.vsync_neg:
    mov eax, [r12 + DCN_CRTC_V_SYNC_POLARITY + r13 * 4]
    and eax, ~1
    mov [r12 + DCN_CRTC_V_SYNC_POLARITY + r13 * 4], eax

.done:
    mov eax, [rbx + Mode.pixel_clock]
    mov [r12 + DCN_CRTC_PIXEL_CLOCK + r13 * 4], eax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

native_plane_program:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov r13, [r12 + Output.current_surface]
    test r13, r13
    jz .no_surface
    mov r13, [r13 + Surface.current + SurfaceState.buffer]
    test r13, r13
    jz .no_surface
    mov r13, [r13 + Buffer.base]
    test r13, r13
    jz .no_surface

    mov [r12 + DCN_PLANE_SURFACE_ADDRESS + r15 * 8], r13

    mov eax, [r12 + Output.width]
    mov edx, [r12 + Output.height]
    shl rdx, 16
    or rax, rdx
    mov [r12 + DCN_PLANE_SIZE + r15 * 4], rax

    mov eax, [r12 + Output.width]
    mov edx, [r12 + Output.height]
    shl rdx, 16
    or rax, rdx
    mov [r12 + DCN_PLANE_SOURCE_SIZE + r15 * 4], rax

    mov eax, [r12 + Output.stride]
    mov [r12 + DCN_PLANE_STRIDE + r15 * 4], eax

    mov eax, DRM_FORMAT_BGRA8888
    mov [r12 + DCN_PLANE_FORMAT + r15 * 4], eax

    mov eax, [r12 + DCN_PLANE_CONTROL + r15 * 4]
    or eax, 1
    mov [r12 + DCN_PLANE_CONTROL + r15 * 4], eax

.no_surface:
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

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

    mov r15, [rbx + Backend.state]
    mov r15, [r15 + Controller.state]
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
    mov rdx, 0
    call fence_wait
    test rax, rax
    jnz .fail

.no_fence:
    mov [r12 + DCN_PLANE_SURFACE_ADDRESS_NEXT + r15 * 8], r13

    mov eax, [r12 + DCN_PLANE_CONTROL + r15 * 4]
    or eax, 2
    mov [r12 + DCN_PLANE_CONTROL + r15 * 4], eax

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
    RETURN_ERROR EIO

section .rodata
DCN_CRTC_CONTROL:              dd 0x0000
DCN_CRTC_STATUS:               dd 0x0010
DCN_CRTC_HTOTAL:               dd 0x0020
DCN_CRTC_H_START:              dd 0x0030
DCN_CRTC_H_END:                dd 0x0040
DCN_CRTC_VTOTAL:               dd 0x0050
DCN_CRTC_V_START:              dd 0x0060
DCN_CRTC_V_END:                dd 0x0070
DCN_CRTC_H_SYNC_POLARITY:      dd 0x0080
DCN_CRTC_V_SYNC_POLARITY:      dd 0x0090
DCN_CRTC_PIXEL_CLOCK:          dd 0x00A0

DCN_PLANE_CONTROL:             dd 0x1000
DCN_PLANE_SURFACE_ADDRESS:     dd 0x1010
DCN_PLANE_SURFACE_ADDRESS_NEXT: dd 0x1020
DCN_PLANE_SIZE:                dd 0x1030
DCN_PLANE_SOURCE_SIZE:         dd 0x1040
DCN_PLANE_STRIDE:              dd 0x1050
DCN_PLANE_FORMAT:              dd 0x1060

MODE_FLAG_HSYNC_POSITIVE:      dd (1 << 0)
MODE_FLAG_VSYNC_POSITIVE:      dd (1 << 1)
MODE_FLAG_INTERLACED:          dd (1 << 2)

section .data
global native_modeset_version
native_modeset_version: dq 0x010000