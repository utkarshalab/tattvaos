; ============================================================================
; Compositor — Damage-Driven Composition Driver
; Coordinates renderer, damage tracking, frame scheduling
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/render.inc"
%include "inc/backend.inc"

; struct offsets (hoisted above use)
%define Compositor_server        0
%define Compositor.server 0
%define Compositor_renderer      8
%define Compositor.renderer 8
%define Compositor_arena         16
%define Compositor.arena 16
%define Compositor_damage_ring   24
%define Compositor.damage_ring 24
%define Compositor_frame_seq     32
%define Compositor.frame_seq 32
%define Compositor_size          40

section .text

; ---------------------------------------------------------------------------
; compositor_init
;   Initialize compositor
;   IN:  rdi = compositor*, rsi = server*, rdx = arena
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global compositor_init
compositor_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13

    mov qword [rbx + Compositor.server], r12
    mov qword [rbx + Compositor.renderer], 0
    mov qword [rbx + Compositor.arena], r13
    mov qword [rbx + Compositor.damage_ring], 0
    mov qword [rbx + Compositor.frame_seq], 0

    ; Initialize software renderer
    mov rdi, [rbx + Compositor.renderer]
    mov rsi, [r12 + Server.backend]
    mov rdx, r13
    call sw_render_init

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; compositor_deinit
; ---------------------------------------------------------------------------
global compositor_deinit
compositor_deinit:
    PROLOGUE
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; compositor_composite
;   Composite all outputs for current frame
;   IN:  rdi = compositor*
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global compositor_composite
compositor_composite:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    ASSERT_PTR rbx

    mov r12, [rbx + Compositor.server]
    mov r13, [r12 + Server.outputs]
    test r13, r13
    jz .done

.output_loop:
    ; Composite each output
    push r13
    push r12
    push rbx
    mov rdi, r13
    call compositor_composite_output
    test rax, rax
    jnz .fail

    pop rbx
    pop r12
    pop rbx
    mov r13, [r13 + Output.next]
    test r13, r13
    jnz .output_loop

.done:
    ; Increment frame sequence
    inc qword [rbx + Compositor.frame_seq]
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.fail:
    mov rax, -(EIO)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; compositor_composite_output
;   Composite single output
;   IN:  rdi = output*
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
compositor_composite_output:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Get output damage
    mov r12, [rbx + Output.damage]
    test r12, r12
    jz .no_damage

    ; Check for direct scanout candidate
    mov r13, [rbx + Output.surfaces]
    test r13, r13
    jz .no_surfaces

    ; Check for direct scanout candidate
    call direct_scanout_check
    test rax, rax
    jz .composite_normal

    ; Direct scanout path
    call direct_scanout_enable
    test rax, rax
    jz .composite_normal
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.composite_normal:
    ; Begin frame
    mov rdi, [r14 + Compositor.renderer]
    mov rsi, rbx
    mov rdx, r12
    call sw_render_begin_frame
    test rax, rax
    jnz .fail
    mov r14, rax  ; frame_ctx

    ; Iterate surfaces in z-order (bottom to top)
    ; TODO: Iterate surfaces from z-order tree

    ; For now, iterate surface list
    mov r15, [rbx + Output.surfaces]
.surface_loop:
    test r15, r15
    jz .surface_done

    ; Render surface
    push r15
    push r14
    push rbx
    mov rdi, r14
    mov rsi, r15
    mov rdx, [rbx + Output.damage]
    call sw_render_surface
    test rax, rax
    jnz .fail

    pop rbx
    pop r14
    pop r15
    mov r15, [r15 + Surface.z_order_next]
    jmp .surface_loop

.surface_done:
    ; End frame
    push rbx
    mov rdi, [r14 + Compositor.renderer]
    mov rsi, r14
    call sw_render_end_frame
    pop rbx
    test rax, rax
    jnz .fail

    ; Clear damage for next frame
    mov rdi, [rbx + Output.damage]
    call region_clear

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.no_damage:
.no_surfaces:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.fail:
    mov rax, -(EIO)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; compositor_schedule_frame
;   Schedule frame for output
; ---------------------------------------------------------------------------
global compositor_schedule_frame
compositor_schedule_frame:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Schedule frame clock callback
    mov rdi, [r12 + Output.frame_clock]
    mov rsi, compositor_frame_callback
    mov rdx, r12
    call frame_clock_schedule

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; compositor_frame_callback
;   Frame clock callback - triggers composition
; ---------------------------------------------------------------------------
compositor_frame_callback:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Composite
    mov rdi, rbx
    call compositor_composite

    ; Schedule next frame if damage
    mov rdi, [r12 + Output.damage]
    call region_is_empty
    test rax, rax
    jnz .done

    ; Has damage - schedule next
    mov rdi, rbx
    mov rsi, r12
    call compositor_schedule_frame

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

section .data


global compositor_version
compositor_version: dq 0x010000
