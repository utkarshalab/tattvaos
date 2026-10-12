; ============================================================================
; DCN Modeset Implementation — AMD DCN Display Engine Programming
; Uses register definitions from dcn_regs.inc
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "src/backend/family/amd/dcn/dcn_regs.inc"

section .text

; ---------------------------------------------------------------------------
; dcn_modeset
;   Program display mode on DCN CRTC
;   IN:  rdi = controller*, rsi = output*, rdx = mode*
;   OUT: rax = 0 OK, negative error
; ---------------------------------------------------------------------------
global dcn_modeset
dcn_modeset:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
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

    ; Get CRTC index
    mov eax, [r12 + Output.crtc_index]
    mov r15d, eax

    ; Get MMIO base
    mov r14, [rbx + Controller.mmio_base]
    test r14, r14
    jz .no_mmio

    ; Disable CRTC
    call dcn_crtc_disable

    ; Program timing
    call dcn_crtc_program_timing

    ; Program plane
    call dcn_plane_program

    ; Enable CRTC
    call dcn_crtc_enable

    ; Update output state
    mov rax, [r13 + Mode.width]
    mov [r12 + Output.width], eax
    mov eax, [r13 + Mode.height]
    mov [r12 + Output.height], eax
    mov qword [r12 + Output.current_mode], r13

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.bad_mode:
    RETURN_ERROR EINVAL
.no_mmio:
    RETURN_ERROR ENXIO

; ---------------------------------------------------------------------------
; dcn_crtc_disable
; ---------------------------------------------------------------------------
dcn_crtc_disable:
    PROLOGUE_SAVE rbx, r12, r13
    ; r14 = MMIO base, r15 = CRTC index

    mov eax, [r14 + CRTC_CONTROL + r15 * CRTC_STRIDE]
    and eax, ~CRTC_CONTROL_ENABLE
    mov [r14 + CRTC_CONTROL + r15 * CRTC_STRIDE], eax

    mov ecx, 100000
.wait_loop:
    mov eax, [r14 + CRTC_STATUS + r15 * CRTC_STRIDE]
    test eax, CRTC_STATUS_ENABLED
    jz .disabled
    dec ecx
    jnz .wait_loop
    RETURN_ERROR ETIMEDOUT

.disabled:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; dcn_crtc_enable
; ---------------------------------------------------------------------------
dcn_crtc_enable:
    PROLOGUE_SAVE rbx, r12, r13
    mov eax, [r14 + CRTC_CONTROL + r15 * CRTC_STRIDE]
    or eax, CRTC_CONTROL_ENABLE
    mov [r14 + CRTC_CONTROL + r15 * CRTC_STRIDE], eax

    mov ecx, 100000
.wait_loop:
    mov eax, [r14 + CRTC_STATUS + r15 * CRTC_STRIDE]
    test eax, CRTC_STATUS_ENABLED
    jnz .enabled
    dec ecx
    jnz .wait_loop
    RETURN_ERROR ETIMEDOUT

.enabled:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; dcn_crtc_program_timing
; ---------------------------------------------------------------------------
dcn_crtc_program_timing:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, r13
    mov r12, r14
    mov r13, r15

    ; HTOTAL
    mov eax, [rbx + Mode.htotal]
    dec eax
    mov [r12 + CRTC_HTOTAL + r13 * CRTC_STRIDE], eax

    ; H_START (hsync_start)
    mov eax, [rbx + Mode.hsync_start]
    dec eax
    mov [r12 + CRTC_H_START + r13 * CRTC_STRIDE], eax

    ; H_END (hsync_end)
    mov eax, [rbx + Mode.hsync_end]
    dec eax
    mov [r12 + CRTC_H_END + r13 * CRTC_STRIDE], eax

    ; VTOTAL
    mov eax, [rbx + Mode.vtotal]
    dec eax
    mov [r12 + CRTC_VTOTAL + r13 * CRTC_STRIDE], eax

    ; V_START (vsync_start)
    mov eax, [rbx + Mode.vsync_start]
    dec eax
    mov [r12 + CRTC_V_START + r13 * CRTC_STRIDE], eax

    ; V_END (vsync_end)
    mov eax, [rbx + Mode.vsync_end]
    dec eax
    mov [r12 + CRTC_V_END + r13 * CRTC_STRIDE], eax

    ; Polarity
    mov eax, [rbx + Mode.flags]
    test eax, MODE_FLAG_HSYNC_POSITIVE
    jz .hsync_neg
    mov eax, [r12 + CRTC_H_SYNC_POLARITY + r13 * CRTC_STRIDE]
    or eax, 1
    mov [r12 + CRTC_H_SYNC_POLARITY + r13 * CRTC_STRIDE], eax
    jmp .vsync_check

.hsync_neg:
    mov eax, [r12 + CRTC_H_SYNC_POLARITY + r13 * CRTC_STRIDE]
    and eax, ~1
    mov [r12 + CRTC_H_SYNC_POLARITY + r13 * CRTC_STRIDE], eax

.vsync_check:
    test eax, MODE_FLAG_VSYNC_POSITIVE
    jz .vsync_neg
    mov eax, [r12 + CRTC_V_SYNC_POLARITY + r13 * CRTC_STRIDE]
    or eax, 1
    mov [r12 + CRTC_V_SYNC_POLARITY + r13 * CRTC_STRIDE], eax
    jmp .done

.vsync_neg:
    mov eax, [r12 + CRTC_V_SYNC_POLARITY + r13 * CRTC_STRIDE]
    and eax, ~1
    mov [r12 + CRTC_V_SYNC_POLARITY + r13 * CRTC_STRIDE], eax

.done:
    ; Pixel clock
    mov eax, [rbx + Mode.pixel_clock]
    mov [r12 + CRTC_PIXEL_CLOCK + r13 * CRTC_STRIDE], eax

    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; dcn_plane_program
; ---------------------------------------------------------------------------
dcn_plane_program:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    ; r12 = output*, r14 = MMIO base, r15 = CRTC index

    mov r13, [r12 + Output.current_surface]
    test r13, r13
    jz .no_surface

    mov r13, [r13 + Surface.current + SurfaceState.buffer]
    test r13, r13
    jz .no_surface

    mov r13, [r13 + Buffer.base]
    test r13, r13
    jz .no_surface

    ; PLANE_SURFACE_ADDRESS
    mov [r12 + PLANE_SURFACE_ADDRESS + r15 * PLANE_STRIDE], r13
    mov dword [r12 + PLANE_SURFACE_ADDRESS_HIGH + r15 * PLANE_STRIDE], 0

    ; PLANE_SIZE
    mov eax, [r12 + Output.width]
    mov edx, [r12 + Output.height]
    shl rdx, 16
    or rax, rdx
    mov [r12 + PLANE_SIZE + r15 * PLANE_STRIDE], rax

    ; PLANE_SOURCE_SIZE
    mov eax, [r12 + Output.width]
    mov edx, [r12 + Output.height]
    shl rdx, 16
    or rax, rdx
    mov [r12 + PLANE_SOURCE_SIZE + r15 * PLANE_STRIDE], rax

    ; PLANE_STRIDE
    mov eax, [r12 + Output.stride]
    mov [r12 + PLANE_STRIDE + r15 * PLANE_STRIDE], eax

    ; PLANE_FORMAT
    mov eax, PLANE_FORMAT_BGRA8888
    mov [r12 + PLANE_FORMAT + r15 * PLANE_STRIDE], eax

    ; Enable plane
    mov eax, [r12 + PLANE_CONTROL + r15 * PLANE_STRIDE]
    or eax, PLANE_CONTROL_ENABLE
    mov [r12 + PLANE_CONTROL + r15 * PLANE_STRIDE], eax

.no_surface:
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; dcn_flip
;   Page flip using double-buffered surface address
; ---------------------------------------------------------------------------
global dcn_flip
dcn_flip:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13

    ; Get controller
    mov r15, [rbx + Controller.state]
    test r15, r15
    jz .fail

    ; Get CRTC index
    mov eax, [r12 + Output.crtc_index]
    mov r15d, eax

    ; Get MMIO base
    mov r14, [r15 + Controller.mmio_base]

    ; Get new buffer address
    mov r13, [r13 + Buffer.base]
    test r13, r13
    jz .fail

    ; Wait for acquire fence
    test r14, r14
    jz .no_fence
    mov rdi, [rbx + Backend.server]
    mov rsi, r14
    mov rdx, 0
    call fence_wait
    test rax, rax
    jnz .fail

.no_fence:
    ; Program next surface address
    mov [r12 + PLANE_SURFACE_ADDRESS_NEXT + r15 * PLANE_STRIDE], r13
    mov dword [r12 + PLANE_SURFACE_ADDRESS_NEXT_HIGH + r15 * PLANE_STRIDE], 0

    ; Request flip (UPDATE bit)
    mov eax, [r12 + PLANE_CONTROL + r15 * PLANE_STRIDE]
    or eax, PLANE_CONTROL_UPDATE
    mov [r12 + PLANE_CONTROL + r15 * PLANE_STRIDE], eax

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

.fail:
    RETURN_ERROR EIO

section .data
global dcn_modeset_version
dcn_modeset_version: dq 0x010000