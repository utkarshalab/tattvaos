; ============================================================================
; Input Source Interface — Abstract Input Event Source
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/canvas_client.inc"

; struct offsets (hoisted above use)
%define INPUT_SOURCE_TV       1
%define INPUT_SOURCE_VIRTUAL  2
%define InputSource_SIZE    48
%define InputEvent_SIZE     24

section .text


; InputSource struct layout (manual offsets)\n; Offsets defined in inc/struct_offsets.inc\n\n; ----------\n


struc InputEvent
    .type:      resd 1
    .code:      resd 1
    .value:     resd 1
    .time_ns:   resq 1
    .device_id: resd 1
endstruc

; ---------------------------------------------------------------------------
; input_source_register
;   Register input source
; ---------------------------------------------------------------------------
global input_source_register
input_source_register:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Add to source list
    mov rax, [rbx + Server.input_sources]
    mov [r12 + InputSource.next], rax
    mov [rbx + Server.input_sources], r12

    ; Call init
    mov rdi, [r12 + InputSource.init]
    mov rsi, rbx
    call rdi

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; input_source_unregister
; ---------------------------------------------------------------------------
global input_source_unregister
input_source_unregister:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    lea rcx, [rbx + Server.input_sources]
.find:
    mov rax, [rcx]
    test rax, rax
    jz .missing
    cmp rax, r12
    je .remove
    lea rcx, [rax + InputSource.next]
    jmp .find
.remove:
    mov rax, [r12 + InputSource.next]
    mov [rcx], rax
    mov rax, [r12 + InputSource.deinit]
    test rax, rax
    jz .ok
    mov rdi, r12
    call rax
.ok:
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12
    ret
.missing:
    mov rax, -(ENOENT)
    EPILOGUE_RESTORE rbx, r12
    ret

section .data
global input_source_version
input_source_version: dq 0x010000
