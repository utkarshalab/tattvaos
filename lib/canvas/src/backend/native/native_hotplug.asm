; ============================================================================
; Native Hotplug — Display Connection/Disconnection Handling
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/struct_offsets.inc"
%include "inc/externs.inc"

section .text

global native_hotplug_init
native_hotplug_init:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov r13, [rbx + Backend.state]
    mov r14, [r13 + Controller.state]
    test r14, r14
    jz .fail

    ; Register HPD interrupt for each connector
    mov r13, [r14 + Controller.outputs]
.hpd_loop:
    test r13, r13
    jz .done

    ; Get HPD interrupt for this connector
    mov eax, [r13 + Output.hpd_irq]
    test eax, eax
    jz .next

    mov rdi, eax
    mov rsi, native_hpd_handler
    mov rdx, r13  ; output as user_data
    mov rcx, IRQ_EDGE
    call tv_irq_register
    test rax, rax
    jnz .fail

.next:
    mov r13, [r13 + Output.next]
    jmp .hpd_loop

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

fail:
    RETURN_ERROR EIO

native_hpd_handler:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi  ; output*
    ASSERT_PTR rbx

    ; Read HPD status from register
    mov r12, [rbx + Output.controller]
    mov r13, [r12 + Controller.mmio_base]
    mov eax, [rbx + Output.hpd_register]
    movsxd rax, eax
    mov edx, [r13 + rax]

    test edx, edx
    jnz .connected

    ; Disconnected
    call native_handle_disconnect
    jmp .done

.connected:
    ; Connected - read EDID and setup mode
    call native_handle_connect

.done:
    ; Call user callback
    mov rdi, [rbx + Output.hotplug_callback]
    test rdi, rdi
    jz .no_callback
    mov rsi, rbx
    mov rdx, rdx  ; connected/disconnected
    call rdi

.no_callback:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

native_handle_connect:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Read EDID
    sub rsp, 256
    mov rdi, [rbx + Output.controller]
    mov rsi, rbx
    mov rdx, rsp
    call ddc_read_edid
    test rax, rax
    jnz .edid_fail

    ; Parse EDID
    mov rdi, rsp
    mov rsi, rbx
    add rsi, Output.edid
    call edid_parse
    test rax, rax
    jnz .edid_fail

    ; Find preferred mode
    call edid_find_preferred_mode
    test rax, rax
    jz .no_mode

    ; Set mode
    mov rdi, [rbx + Output.controller]
    mov rsi, rbx
    mov rdx, rax
    call native_modeset
    test rax, rax
    jnz .mode_fail

    ; Mark output as connected
    mov byte [rbx + Output.connected], 1

    add rsp, 256
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.edid_fail:
    add rsp, 256
    mov rax, -(EIO)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.no_mode:
    add rsp, 256
    mov rax, -(ENOTSUP)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.mode_fail:
    add rsp, 256
    mov rax, -(EIO)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

native_handle_disconnect:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Disable CRTC
    mov eax, [rbx + Output.crtc_index]
    ; TODO: Call native_crtc_disable

    ; Mark output as disconnected
    mov byte [rbx + Output.connected], 0
    mov qword [rbx + Output.current_mode], 0

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

section .data
global native_hotplug_version
native_hotplug_version: dq 0x010000
