; ============================================================================
; soak_hotplug — Output Connect/Disconnect Cycles
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

section .text

global soak_hotplug_run
soak_hotplug_run:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    xor r13d, r13d
.loop:
    cmp r13, r12
    jae .done
    mov rdi, rbx
    call output_layout_apply
    inc r13
    jmp .loop
.done:
    xor rax, rax
    ret

section .data
global soak_hotplug_version
soak_hotplug_version: dq 0x010000
