; ============================================================================
; Input Source Interface — Abstract Input Event Source
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

; struct offsets (hoisted above use)
%define INPUT_SOURCE_TV       1
%define INPUT_SOURCE_VIRTUAL  2
%define InputSource_size    48
%define INPUT_EVENT_KEY       1
%define INPUT_EVENT_REL       2
%define INPUT_EVENT_ABS       3
%define INPUT_EVENT_SYN       4
%define InputEvent_size     24

section .text


struc InputSource
    .type:          resd 1
    .name:          resq 1
    .init:          resq 1
    .deinit:        resq 1
    .start:         resq 1
    .stop:          resq 1
    .get_device:    resq 1
    .grab:          resq 1
    .next:          resq 1
endstruc


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
    PROLOGUE
    ; TODO
    xor rax, rax
    leave
    ret

section .data
global input_source_version
input_source_version: dq 0x010000
