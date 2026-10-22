; ============================================================================
; Output Management — Multi-Monitor, Layout, Scale, Rotation, VRR
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/fixed.inc"
%include "inc/struct_offsets.inc"
%include "inc/canvas_client.inc"

extern config_parse
extern arena_alloc
extern region_init
extern region_destroy
extern frame_clock_init
extern frame_clock_deinit
extern backend_modeset
extern vrr_enable
extern vrr_disable
extern memcopy
extern mirror_configure
extern tv_timer_register
extern frame_clock_vblank

section .text
%define FIX_ONE                0x10000
%define FrameClock_phase       24

section .text

; ---------------------------------------------------------------------------
; output_init
;   Initialize output subsystem
;   IN:  rdi = server*, rsi = arena
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global output_init
output_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + Server.outputs], 0
    mov qword [rbx + Server.output_count], 0
    mov qword [rbx + Server.arena], r12

    ; Load output configuration
    call output_load_config

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; output_load_config
;   Load output configuration from file
; ---------------------------------------------------------------------------
output_load_config:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    lea rsi, [rel outputs_config_path]
    call config_parse
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; output_create
;   Create output object
;   IN:  rdi = server*, rsi = backend*, rdx = connector_info*
;   OUT: rax = output*, 0 on error
; ---------------------------------------------------------------------------
global output_create
output_create:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Allocate output
    mov rdi, [rbx + Server.arena]
    mov rsi, Output_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov r14, rax

    ; Initialize output
    mov qword [r14 + Output.id], 0
    mov qword [r14 + Output.name], 0
    mov qword [r14 + Output.backend], r12
    mov qword [r14 + Output.framebuffer], 0
    mov dword [r14 + Output.width], 0
    mov dword [r14 + Output.height], 0
    mov qword [r14 + Output.stride], 0
    mov qword [r14 + Output.scale], FIX_ONE
    mov dword [r14 + Output.rotation], 0
    mov qword [r14 + Output.gamma_lut], 0
    mov qword [r14 + Output.icc_profile], 0
    mov byte [r14 + Output.vrr_enabled], 0
    mov qword [r14 + Output.current_mode], 0
    mov qword [r14 + Output.modes], 0
    mov qword [r14 + Output.position], 0
    mov qword [r14 + Output.frame_clock], 0
    mov qword [r14 + Output.damage], 0
    mov qword [r14 + Output.next], 0

    ; Initialize damage region
    mov rdi, [rbx + Server.arena]
    call region_init
    test rax, rax
    jnz .damage_ok
    jmp .oom

.damage_ok:
    mov qword [r14 + Output.damage], rax

    ; Initialize frame clock
    mov rdi, [rbx + Server.arena]
    mov rsi, 40
    call arena_alloc
    test rax, rax
    jz .oom
    mov qword [r14 + Output.frame_clock], rax

    ; Initialize frame clock
    mov rdi, rax
    mov rsi, r14
    mov rdx, 16666667  ; 60Hz default
    call frame_clock_init

    ; Add to server output list
    mov rax, [rbx + Server.outputs]
    mov [r14 + Output.next], rax
    mov [rbx + Server.outputs], r14
    inc qword [rbx + Server.output_count]

    mov rax, r14
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; output_destroy
; ---------------------------------------------------------------------------
global output_destroy
output_destroy:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    lea rax, [rbx + Server.outputs]
.unlink:
    mov rcx, [rax]
    test rcx, rcx
    jz .not_linked
    cmp rcx, r12
    je .found
    lea rax, [rcx + Output.next]
    jmp .unlink
.found:
    mov rcx, [r12 + Output.next]
    mov [rax], rcx
    dec qword [rbx + Server.output_count]
.not_linked:

    ; Destroy damage region
    mov rdi, [r12 + Output.damage]
    call region_destroy

    ; Destroy frame clock
    mov rdi, [r12 + Output.frame_clock]
    test rdi, rdi
    jz .destroyed
    call frame_clock_deinit
.destroyed:

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; Arm one native one-shot timer for the output's next vertical blank.
global output_schedule_vblank
output_schedule_vblank:
    PROLOGUE_SAVE rbx
    mov rbx, [rdi + Output.frame_clock]
    test rbx, rbx
    jz .schedule_invalid
    mov rdi, [rbx + FrameClock.next_vblank]
    lea rsi, [rel output_vblank_timer]
    mov rdx, rbx
    call tv_timer_register
    test rax, rax
    js .schedule_out
    mov [rbx + FrameClock_phase], rax
.schedule_out:
    EPILOGUE_RESTORE rbx
    ret
.schedule_invalid:
    mov rax, -(EINVAL)
    jmp .schedule_out

; Tattva timer callback: rdi=user_data, rsi=fire timestamp.
output_vblank_timer:
    mov qword [rdi + FrameClock_phase], 0
    jmp frame_clock_vblank

; ---------------------------------------------------------------------------
; output_set_mode
;   Set output mode
;   IN:  rdi = server*, rsi = output*, rdx = mode*
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global output_set_mode
output_set_mode:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13

    ; Call backend modeset
    mov rdi, [rbx + Server.backend]
    mov rsi, r12
    mov rdx, r13
    call backend_modeset
    test rax, rax
    jnz .fail

    ; Update frame clock with new refresh rate
    mov rdi, [r12 + Output.frame_clock]
    mov rax, [r13 + Mode.refresh_ns]
    mov [rdi + FrameClock.refresh_ns], rax

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.fail:
    mov rax, -(EOUT_MODE)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; output_set_scale
;   Set output scale factor
;   IN:  rdi = server*, rsi = output*, rdx = scale (fixed 16.16)
; ---------------------------------------------------------------------------
global output_set_scale
output_set_scale:
    PROLOGUE
    ASSERT_PTR rdi
    ASSERT_PTR rsi

    mov qword [rsi + Output.scale], rdx
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; output_set_rotation
;   Set output rotation
; ---------------------------------------------------------------------------
global output_set_rotation
output_set_rotation:
    PROLOGUE
    ASSERT_PTR rdi
    ASSERT_PTR rsi

    mov dword [rsi + Output.rotation], edx
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; output_set_position
;   Set output position in global layout
; ---------------------------------------------------------------------------
global output_set_position
output_set_position:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov eax, [r12 + 0]
    mov [rbx + 0], eax
    mov eax, [r12 + 4]
    mov [rbx + 4], eax

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; output_enable_vrr
;   Enable/disable VRR
; ---------------------------------------------------------------------------
global output_enable_vrr
output_enable_vrr:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rdi
    ASSERT_PTR rsi

    test dl, dl
    jz .disable
    mov rdx, [r12 + Output.vrr_caps]
    test rdx, rdx
    jz .unsupported
    mov rdi, rbx
    mov rsi, r12
    call vrr_enable
    EPILOGUE_RESTORE rbx, r12
    ret
.disable:
    mov rdi, rbx
    mov rsi, r12
    call vrr_disable
    EPILOGUE_RESTORE rbx, r12
    ret
.unsupported:
    mov rax, -(ENOTSUP)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; output_set_gamma
;   Set gamma LUT
; ---------------------------------------------------------------------------
global output_set_gamma
output_set_gamma:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Copy gamma LUT (256 * 3 * 2 bytes = 1536 bytes)
    mov rdi, [rbx + Output.gamma_lut]
    test rdi, rdi
    jz .alloc_gamma

    mov rsi, r12
    mov rcx, 768
    call memcopy
    EPILOGUE_RESTORE rbx, r12
    ret

.alloc_gamma:
    mov rdi, [rbx + Server.arena]
    mov rsi, 1536
    call arena_alloc
    test rax, rax
    jz .oom
    mov [rbx + Output.gamma_lut], rax
    mov rdi, rax
    mov rsi, r12
    mov rcx, 768
    call memcopy
    EPILOGUE_RESTORE rbx, r12
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; output_set_icc_profile
;   Set ICC color profile
; ---------------------------------------------------------------------------
global output_set_icc_profile
output_set_icc_profile:
    PROLOGUE
    ASSERT_PTR rdi
    mov [rdi + Output.icc_profile], rsi
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; output_layout_apply
;   Apply multi-monitor layout
; ---------------------------------------------------------------------------
global output_layout_apply
output_layout_apply:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Calculate total layout bounds
    mov r10, [rbx + Server.outputs]
    test r10, r10
    jz .done

    ; Find min/max bounds
    mov r13d, 0x7FFFFFFF
    mov r14d, 0x7FFFFFFF
    mov r15d, 0x80000000
    mov r11d, 0x80000000

.bounds_loop:
    test r10, r10
    jz .bounds_done

    mov eax, [r10 + Output.position + 0]
    cmp eax, r13d
    cmovl r13d, eax

    mov eax, [r10 + Output.position + 4]
    cmp eax, r14d
    cmovl r14d, eax

    mov eax, [r10 + Output.position + 0]
    add eax, [r10 + Output.width]
    cmp eax, r15d
    cmovg r15d, eax

    mov eax, [r10 + Output.position + 4]
    add eax, [r10 + Output.height]
    cmp eax, r11d
    cmovg r11d, eax

    mov r10, [r10 + Output.next]
    jmp .bounds_loop

.bounds_done:
    ; Store layout bounds
    mov [rbx + Server.layout_bounds + 0], r13d
    mov [rbx + Server.layout_bounds + 4], r14d
    mov [rbx + Server.layout_bounds + 8], r15d
    mov [rbx + Server.layout_bounds + 12], r11d

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; output_mirror
;   Configure mirror mode
; ---------------------------------------------------------------------------
global output_mirror
output_mirror:
    jmp mirror_configure

section .data
outputs_config_path: db '/conf/canvas/outputs.conf', 0






global output_version
output_version: dq 0x010000
