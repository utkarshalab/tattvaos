; ============================================================================
; Virtual Input Source — Injected and Remote Input Events
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/struct_offsets.inc"
%include "inc/canvas_client.inc"
%include "inc/source_iface.inc"
%include "inc/event.inc"

extern arena_alloc
extern input_source_register
extern input_submit

section .text

global input_source_virtual_init
input_source_virtual_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Create source struct
    mov rdi, [rbx + Server.arena]
    mov rsi, InputSource_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov r12, rax

    ; Fill source
    mov dword [r12 + InputSource.type], INPUT_SOURCE_VIRTUAL
    lea r11, [rel virtual_source_name]
    mov [r12 + InputSource.name], r11
    lea r11, [rel virtual_source_init]
    mov [r12 + InputSource.init], r11
    lea r11, [rel virtual_source_deinit]
    mov [r12 + InputSource.deinit], r11
    lea r11, [rel virtual_source_start]
    mov [r12 + InputSource.start], r11
    lea r11, [rel virtual_source_stop]
    mov [r12 + InputSource.stop], r11
    lea r11, [rel virtual_source_get_device]
    mov [r12 + InputSource.get_device], r11
    lea r11, [rel virtual_source_grab]
    mov [r12 + InputSource.grab], r11

    ; Register source
    mov rdi, rbx
    mov rsi, r12
    call input_source_register

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12
    ret

virtual_source_init:
    PROLOGUE
    xor rax, rax
    leave
    ret

virtual_source_deinit:
    PROLOGUE
    xor rax, rax
    leave
    ret

virtual_source_start:
    PROLOGUE
    xor rax, rax
    leave
    ret

virtual_source_stop:
    PROLOGUE
    xor rax, rax
    leave
    ret

virtual_source_get_device:
    PROLOGUE
    xor rax, rax
    leave
    ret

virtual_source_grab:
    PROLOGUE
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; virtual_input_inject
;   Inject one raw input event, as if a device had sent it
;   IN:  rdi = server*, esi = type (INPUT_* in inc/event.inc), edx = code,
;        ecx = value, r8d = device
;   OUT: rax = 0, -ENODEV with no seat, -ENOSPC when the queue is full
; ---------------------------------------------------------------------------
global virtual_input_inject
virtual_input_inject:
    PROLOGUE
    sub rsp, RawInput_size + 8
    mov [rsp + RawInput.type], esi
    mov [rsp + RawInput.code], edx
    mov [rsp + RawInput.value], ecx
    mov [rsp + RawInput.device], r8d
    mov qword [rsp + RawInput.time], 0
    mov rsi, rsp
    call input_submit
    EPILOGUE

section .rodata
virtual_source_name: db "virtual-input", 0

section .data

global input_source_virtual_version
input_source_virtual_version: dq 0x010000
