; ============================================================================
; Mirror — Output Mirroring (Clone Mode)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/struct_offsets.inc"
%include "inc/canvas_client.inc"

extern output_set_mode
extern output_layout_apply

section .text

; ---------------------------------------------------------------------------
; mirror_init
; ---------------------------------------------------------------------------
global mirror_init
mirror_init:
    PROLOGUE
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; mirror_configure
;   Configure mirror mode: source output cloned to target outputs
;   IN:  rdi = server*, rsi = source_output*, rdx = target_outputs_array, rcx = count
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global mirror_configure
mirror_configure:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13

    test r14, r14
    jz .done

    ; Get source mode
    mov rax, [r12 + Output.current_mode]
    test rax, rax
    jz .no_mode

    ; Apply same mode to all targets
    mov r15, r13
.loop:
    test r14, r14
    jz .done

    mov rsi, [r15]
    test rsi, rsi
    jz .next

    ; Set same mode on target
    mov rdi, rbx
    mov rdx, rax
    call output_set_mode
    test rax, rax
    jnz .fail

.next:
    add r15, 8
    dec r14
    jmp .loop

.fail:
    mov rax, -(EOUT_MODE)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.no_mode:
    mov rax, -(EOUT_MODE)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; mirror_disable
;   Disable mirror mode, restore independent outputs
; ---------------------------------------------------------------------------
global mirror_disable
mirror_disable:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, [rbx + Server.outputs]
.restore:
    test r12, r12
    jz .restored
    mov rax, [r12 + Output.current_mode]
    test rax, rax
    jz .next
    mov rdi, rbx
    mov rsi, r12
    mov rdx, rax
    call output_set_mode
    test rax, rax
    jnz .failed
.next:
    mov r12, [r12 + Output.next]
    jmp .restore
.restored:
    call output_layout_apply
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret
.failed:
    mov rax, -(EOUT_MODE)
    EPILOGUE_RESTORE rbx, r12
    ret

section .data
global mirror_version
mirror_version: dq 0x010000
