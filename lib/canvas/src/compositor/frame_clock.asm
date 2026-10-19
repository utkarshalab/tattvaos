; ============================================================================
; Frame Clock — VSync Scheduling, Frame Callbacks
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/compositor.inc"
%include "inc/externs.inc"

section .text

; ============================================================================
; frame_clock_init
;   Initialize frame clock
; ============================================================================
global frame_clock_init
frame_clock_init:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov qword [rbx + FRAME_CLOCK_CALLBACKS], 0
    mov qword [rbx + FRAME_CLOCK_NEXT_VBLANK], 0
    mov dword [rbx + FRAME_CLOCK_REFRESH_NS], 16666667  ; 60Hz default

    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ============================================================================
; frame_clock_deinit
;   Cleanup frame clock
; ============================================================================
global frame_clock_deinit
frame_clock_deinit:
    PROLOGUE
    ; Cancel all callbacks
    xor rax, rax
    leave
    ret

; ============================================================================
; frame_clock_schedule
;   Schedule frame callback for next vblank
;   IN: rdi = frame_clock*, rsi = frame_callback*
; ============================================================================
global frame_clock_schedule
frame_clock_schedule:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Add to callback list
    mov rax, [rbx + FRAME_CLOCK_CALLBACKS]
    mov [r12 + FRAME_CB_NEXT], rax
    mov [rbx + FRAME_CLOCK_CALLBACKS], r12

    ; Schedule vblank if not already scheduled
    mov rax, [rbx + FRAME_CLOCK_NEXT_VBLANK]
    test rax, rax
    jnz .done

    ; Schedule vblank interrupt
    call .schedule_vblank

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.schedule_vblank:
    ; Call backend to schedule vblank
    ret

; ============================================================================
; frame_clock_schedule_vblank
;   Schedule specific vblank
; ============================================================================
global frame_clock_schedule_vblank
frame_clock_schedule_vblank:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Schedule specific vblank time
    ret

; ============================================================================
; frame_clock_vblank_handler
;   Called on vblank interrupt - fire callbacks
; ============================================================================
global frame_clock_vblank_handler
frame_clock_vblank_handler:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Get current timestamp
    call tv_time_now_ns
    mov r12, rax

    ; Fire all pending callbacks
    mov r13, [rbx + FRAME_CLOCK_CALLBACKS]
    mov qword [rbx + FRAME_CLOCK_CALLBACKS], 0
    mov qword [rbx + FRAME_CLOCK_NEXT_VBLANK], 0

.callback_loop:
    test r13, r13
    jz .done

    mov r14, [r13 + FRAME_CB_NEXT]
    mov r15, [r13 + FRAME_CB_SURFACE]

    ; Update callback timestamp
    mov [r13 + FRAME_CB_TIMESTAMP], r12

    ; Fire callback
    ; Callback is a function pointer stored in frame_cb
    ; For now, just mark as fired
    test r15, r15
    jz .next_cb

    ; Get surface damage
    lea rdi, [r15 + SURFACE_DAMAGE]
    call damage_get_rects

.next_cb:
    mov r13, r14
    jmp .callback_loop

.done:
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ============================================================================
; frame_clock_get_refresh
;   Get refresh rate in nanoseconds
; ============================================================================
global frame_clock_get_refresh
frame_clock_get_refresh:
    PROLOGUE
    mov eax, [rdi + FRAME_CLOCK_REFRESH_NS]
    leave
    ret

; ============================================================================
; frame_clock_set_refresh
;   Set refresh rate
; ============================================================================
global frame_clock_set_refresh
frame_clock_set_refresh:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov dword [rbx + FRAME_CLOCK_REFRESH_NS], esi
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

section .data
global frame_clock_version
frame_clock_version: dq 0x010000