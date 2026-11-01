; ============================================================================
; Output Management — Modesetting, Multi-Monitor, DPMS, VRR
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/compositor.inc"
%include "inc/externs.inc"
%include "inc/backend.inc"

section .text

; ============================================================================
; output_create
;   Create output from backend
;   IN: rdi = output*, rsi = backend*, rdx = connector_id, rcx = mode*
; ============================================================================
global output_create
output_create:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r14

    ; Initialize output struct
    mov qword [rbx + Output.backend], r12
    mov dword [rbx + Output.crtc_index], r13d
    mov qword [rbx + Output.current_mode], r14

    ; Copy mode info
    mov eax, [r14 + Mode.width]
    mov [rbx + Output.width], eax
    mov eax, [r14 + Mode.height]
    mov [rbx + Output.height], eax

    ; Default state
    mov byte [rbx + Output.connected], 1
    mov dword [rbx + Output.scale], 1
    mov byte [rbx + Output.rotation], ROTATE_0
    mov byte [rbx + Output.dpms_state], DPMS_ON
    mov qword [rbx + Output.dpms_timeout], 0

    ; Allocate damage region
    mov rdi, rbx
    add rdi, OUTPUT_DAMAGE
    call damage_init
    test rax, rax
    jnz .init_fail

    ; Allocate gamma LUT (256 entries * 3 channels * 2 bytes)
    mov rdi, 256 * 3 * 2
    call arena_alloc
    test rax, rax
    jz .init_fail
    mov [rbx + Output.gamma_lut], rax

    ; Initialize identity gamma
    mov rdi, rax
    mov rcx, 256
    xor rax, rax
.gamma_loop:
    mov word [rdi + rax*2], ax
    inc rax
    cmp rax, 256
    jl .gamma_loop

    ; Create frame clock
    mov rdi, rbx
    add rdi, OUTPUT_FRAME_CLOCK
    call frame_clock_init

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.init_fail:
    mov rax, -ENOMEM
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ============================================================================
; output_destroy
;   Cleanup output
; ============================================================================
global output_destroy
output_destroy:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Destroy damage
    mov rdi, rbx
    add rdi, OUTPUT_DAMAGE
    call damage_destroy

    ; Free gamma LUT
    mov rdi, [rbx + Output.gamma_lut]
    test rdi, rdi
    jz .done
    ; Arena handles it

    ; Destroy frame clock
    mov rdi, rbx
    add rdi, OUTPUT_FRAME_CLOCK
    call frame_clock_deinit

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ============================================================================
; output_set_mode
;   Set output mode (modeset)
;   IN: rdi = output*, rsi = mode*
; ============================================================================
global output_set_mode
output_set_mode:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Call backend modeset
    mov rdi, [rbx + Output.backend]
    mov rsi, [rbx + Output.crtc_index]
    mov rdx, r12
    call backend_modeset
    test rax, rax
    jnz .modeset_fail

    ; Update cached mode
    mov rax, [r12 + Mode.width]
    mov [rbx + Output.width], eax
    mov rax, [r12 + Mode.height]
    mov [rbx + Output.height], eax
    mov [rbx + Output.current_mode], r12

    ; Update stride
    mov eax, [rbx + Output.width]
    mov ecx, 4  ; bytes per pixel (BGRA8888)
    imul eax, ecx
    mov [rbx + Output.stride], eax

    ; Reallocate framebuffer if needed
    call .realloc_framebuffer

    ; Reset damage
    mov rdi, rbx
    add rdi, OUTPUT_DAMAGE
    call damage_clear

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.modeset_fail:
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.realloc_framebuffer:
    ; Calculate size
    mov eax, [rbx + Output.width]
    imul eax, [rbx + Output.height]
    imul eax, 4  ; BGRA8888
    mov rdi, [rbx + Output.backend]
    mov rsi, rax
    call arena_alloc
    test rax, rax
    jz .fb_fail
    mov [rbx + Output.framebuffer], rax
    ret

.fb_fail:
    ret

; ============================================================================
; output_dpms
;   Set DPMS state
; ============================================================================
global output_dpms
output_dpms:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12d, esi
    ASSERT_PTR rbx

    cmp r12b, DPMS_ON
    je .dpms_on
    cmp r12b, DPMS_STANDBY
    je .dpms_standby
    cmp r12b, DPMS_SUSPEND
    je .dpms_suspend
    cmp r12b, DPMS_OFF
    je .dpms_off
    mov rax, -EINVAL
    jmp .done

.dpms_on:
    mov rdi, [rbx + Output.backend]
    mov rsi, [rbx + Output.crtc_index]
    mov rdx, 1  ; on
    call backend_dpms
    mov byte [rbx + Output.dpms_state], DPMS_ON
    jmp .done

.dpms_standby:
    mov rdi, [rbx + Output.backend]
    mov rsi, [rbx + Output.crtc_index]
    mov rdx, 2
    call backend_dpms
    mov byte [rbx + Output.dpms_state], DPMS_STANDBY
    jmp .done

.dpms_suspend:
    mov rdi, [rbx + Output.backend]
    mov rsi, [rbx + Output.crtc_index]
    mov rdx, 3
    call backend_dpms
    mov byte [rbx + Output.dpms_state], DPMS_SUSPEND
    jmp .done

.dpms_off:
    mov rdi, [rbx + Output.backend]
    mov rsi, [rbx + Output.crtc_index]
    mov rdx, 4
    call backend_dpms
    mov byte [rbx + Output.dpms_state], DPMS_OFF
    jmp .done

.done:
    EPILOGUE_RESTORE rbx, r12
    ret

; ============================================================================
; output_set_scale
;   Set output scale factor
; ============================================================================
global output_set_scale
output_set_scale:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    test esi, esi
    jz .invalid
    cmp esi, 8
    jg .invalid

    mov dword [rbx + Output.scale], esi

    ; Update stride
    mov eax, [rbx + Output.width]
    imul eax, esi
    imul eax, 4
    mov [rbx + Output.stride], eax

    ; Reallocate framebuffer
    call .realloc_framebuffer

    xor rax, rax
    leave
    ret

.invalid:
    mov rax, -EINVAL
    leave
    ret

.realloc_framebuffer:
    mov eax, [rbx + Output.width]
    imul eax, [rbx + Output.scale]
    imul eax, [rbx + Output.height]
    imul eax, 4
    mov rdi, [rbx + Output.backend]
    mov rsi, rax
    call arena_alloc
    test rax, rax
    jz .fb_fail
    mov [rbx + Output.framebuffer], rax
    ret

.fb_fail:
    ret

; ============================================================================
; output_set_rotation
;   Set output rotation
; ============================================================================
global output_set_rotation
output_set_rotation:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    cmp esi, ROTATE_0
    je .valid
    cmp esi, ROTATE_90
    je .valid
    cmp esi, ROTATE_180
    je .valid
    cmp esi, ROTATE_270
    je .valid
    mov rax, -EINVAL
    jmp .done

.valid:
    mov byte [rbx + Output.rotation], sil
    ; Backend rotation
    mov rdi, [rbx + Output.backend]
    mov rsi, [rbx + Output.crtc_index]
    mov rdx, rsi
    call backend_dpms  ; reuse for rotation
    xor rax, rax

.done:
    EPILOGUE_RESTORE rbx
    ret

; ============================================================================
; output_schedule_frame
;   Schedule frame for output
; ============================================================================
global output_schedule_frame
output_schedule_frame:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi  ; frame_callback*
    ASSERT_PTR rbx

    ; Add to frame clock
    mov rdi, rbx
    add rdi, OUTPUT_FRAME_CLOCK
    mov rsi, r12
    call frame_clock_schedule

    EPILOGUE_RESTORE rbx, r12
    ret

; ============================================================================
; output_get_info
;   Get output info
; ============================================================================
global output_get_info
output_get_info:
    PROLOGUE
    mov rax, [rdi + Output.width]
    mov rdx, [rdi + Output.height]
    mov r8d, [rdi + Output.scale]
    mov r9b, [rdi + Output.rotation]
    mov r10b, [rdi + Output.dpms_state]
    xor rax, rax
    leave
    ret

section .data
global output_version
output_version: dq 0x010000