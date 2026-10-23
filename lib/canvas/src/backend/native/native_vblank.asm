; ============================================================================
; Native VBlank — VBlank Interrupt Handling
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/struct_offsets.inc"
%include "inc/externs.inc"

section .text

global native_vblank_init
native_vblank_init:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Get controller
    mov r13, [rbx + Backend.state]
    mov r14, [r13 + Controller.state]
    test r14, r14
    jz .fail

    ; Register VBlank IRQ for each CRTC
    mov r13, [r14 + Controller.outputs]
.irq_loop:
    test r13, r13
    jz .done

    mov rax, [r13 + Output.crtc_index]
    mov rdi, [r14 + Controller.irq]
    add rdi, rax  ; CRTC-specific IRQ
    mov rsi, native_vblank_handler
    mov rdx, r13  ; output as user_data
    mov rcx, IRQ_EDGE
    call ut_irq_register
    test rax, rax
    jnz .fail

    mov r13, [r13 + Output.next]
    jmp .irq_loop

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.fail:
    mov rax, -(EIO)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

native_vblank_handler:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi  ; output*
    ASSERT_PTR rbx

    ; Get frame clock
    mov r12, [rbx + Output.frame_clock]
    test r12, r12
    jz .done

    ; Get current time
    call ut_time_now_ns
    mov r13, rax

    ; Update frame clock
    mov [r12 + FrameClock.next_vblank], rax
    add rax, [r12 + FrameClock.refresh_ns]
    mov [r12 + FrameClock.next_vblank], rax

    ; Fire callbacks
    mov r14, [r12 + FrameClock.callbacks]
    test r14, r14
    jz .schedule_next

.callback_loop:
    mov rdi, [r14 + 8]  ; callback_fn
    mov rsi, rbx        ; output
    mov rdx, r13        ; timestamp
    call rdi

    mov r14, [r14 + ListNode.next]
    test r14, r14
    jnz .callback_loop

.schedule_next:
    ; Schedule next vblank
    mov rdi, r12
    call frame_clock_schedule_vblank

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

fail:
    RETURN_ERROR EIO

section .data
global native_vblank_version
native_vblank_version: dq 0x010000
