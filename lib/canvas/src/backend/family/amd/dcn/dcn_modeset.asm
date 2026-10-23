; ============================================================================
; DCN Modeset Implementation — AMD DCN Display Engine Programming
; Uses register definitions from dcn_regs.inc
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/struct_offsets.inc"
%include "inc/externs.inc"
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
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.no_mmio:
    mov rax, -(ENXIO)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; dcn_crtc_disable
; ---------------------------------------------------------------------------
dcn_crtc_disable:
    PROLOGUE_SAVE rbx, r12, r13
    ; r14 = MMIO base, r15 = CRTC index

    mov rax, r15
    imul rax, CRTC_STRIDE
    add rax, r14
    add rax, CRTC_CONTROL
    mov eax, [rax]
    and eax, ~CRTC_CONTROL_ENABLE
    mov [rax], eax

    mov rax, r15
    imul rax, CRTC_STRIDE
    add rax, r14
    add rax, CRTC_STATUS
    mov eax, [rax]
    test eax, CRTC_STATUS_ENABLED
    jz .disabled
    dec ecx
    jnz .wait_loop
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
; dcn_crtc_enable
; ---------------------------------------------------------------------------
dcn_crtc_enable:
    PROLOGUE_SAVE rbx, r12, r13

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
; dcn_crtc_program_timing
; ---------------------------------------------------------------------------
dcn_crtc_program_timing:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, r13
    mov r12, r14
    mov r13, r15

    ; Helper: compute CRTC register address in rax
    ; IN: r13 = register offset (CRTC_*), OUT: rax = absolute address
    ; Uses: r12 = MMIO base, r13 = CRTC index (clobbered), r14 = temp
%macro CRTC_ADDR 1
    mov rax, r13
    imul rax, CRTC_STRIDE
    add rax, r12
    add rax, %1
%endmacro

    ; HTOTAL
    mov eax, [rbx + Mode.htotal]
    dec eax
    CRTC_ADDR CRTC_HTOTAL
    mov [rax], eax

    ; H_START (hsync_start)
    mov eax, [rbx + Mode.hsync_start]
    dec eax
    CRTC_ADDR CRTC_H_START
    mov [rax], eax

    ; H_END (hsync_end)
    mov eax, [rbx + Mode.hsync_end]
    dec eax
    CRTC_ADDR CRTC_H_END
    mov [rax], eax

    ; VTOTAL
    mov eax, [rbx + Mode.vtotal]
    dec eax
    CRTC_ADDR CRTC_VTOTAL
    mov [rax], eax

    ; V_START (vsync_start)
    mov eax, [rbx + Mode.vsync_start]
    dec eax
    CRTC_ADDR CRTC_V_START
    mov [rax], eax

    ; V_END (vsync_end)
    mov eax, [rbx + Mode.vsync_end]
    dec eax
    CRTC_ADDR CRTC_V_END
    mov [rax], eax

    ; Polarity
    mov eax, [rbx + Mode.flags]
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
    ; Pixel clock
    mov eax, [rbx + Mode.pixel_clock]
    CRTC_ADDR CRTC_PIXEL_CLOCK
    mov [rax], eax

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

    ; Helper: compute plane register address in rax
    ; Uses: r12 = MMIO base, r15 = plane index, PLANE_STRIDE
%macro PLANE_ADDR 1
    mov rax, r15
    imul rax, PLANE_STRIDE
    add rax, r12
    add rax, %1
%endmacro

    ; PLANE_SURFACE_ADDRESS
    PLANE_ADDR PLANE_SURFACE_ADDRESS
    mov [rax], r13
    PLANE_ADDR PLANE_SURFACE_ADDRESS_HIGH
    mov dword [rax], 0

    ; PLANE_SIZE
    mov eax, [r12 + Output.width]
    mov edx, [r12 + Output.height]
    shl rdx, 16
    or rax, rdx
    PLANE_ADDR PLANE_SIZE
    mov [rax], rax

    ; PLANE_SOURCE_SIZE
    mov eax, [r12 + Output.width]
    mov edx, [r12 + Output.height]
    shl rdx, 16
    or rax, rdx
    PLANE_ADDR PLANE_SOURCE_SIZE
    mov [rax], rax

    ; PLANE_STRIDE
    mov eax, [r12 + Output.stride]
    PLANE_ADDR PLANE_STRIDE
    mov [rax], eax

    ; PLANE_FORMAT
    mov eax, PLANE_FORMAT_BGRA8888
    PLANE_ADDR PLANE_FORMAT
    mov [rax], eax

    ; Enable plane
    PLANE_ADDR PLANE_CONTROL
    mov eax, [rax]
    or eax, PLANE_CONTROL_ENABLE
    mov [rax], eax

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
    ; Helper: compute plane register address in rax
%macro PLANE_ADDR2 1
    mov rax, r15
    imul rax, PLANE_STRIDE
    add rax, r12
    add rax, %1
%endmacro

    ; Program next surface address
    PLANE_ADDR2 PLANE_SURFACE_ADDRESS_NEXT
    mov [rax], r13
    PLANE_ADDR2 PLANE_SURFACE_ADDRESS_NEXT_HIGH
    mov dword [rax], 0

    ; Request flip (UPDATE bit)
    PLANE_ADDR2 PLANE_CONTROL
    mov eax, [rax]
    or eax, PLANE_CONTROL_UPDATE
    mov [rax], eax

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
    mov rax, -(EIO)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

section .data
global dcn_modeset_version
dcn_modeset_version: dq 0x010000
