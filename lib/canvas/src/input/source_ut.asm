; ============================================================================
; Utkarsha Input Source — Events from Utkarsha Kernel Drivers
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/struct_offsets.inc"
%include "inc/canvas_client.inc"
%include "inc/source_iface.inc"

extern arena_alloc
extern input_source_register

section .text

global input_source_tv_init
input_source_tv_init:
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
    mov dword [r12 + InputSource.type], INPUT_SOURCE_TV
    mov qword [r12 + InputSource.name], ut_source_name
    mov qword [r12 + InputSource.init], ut_source_init
    mov qword [r12 + InputSource.deinit], ut_source_deinit
    mov qword [r12 + InputSource.start], ut_source_start
    mov qword [r12 + InputSource.stop], ut_source_stop
    mov qword [r12 + InputSource.get_device], ut_source_get_device
    mov qword [r12 + InputSource.grab], ut_source_grab

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

ut_source_init:
    PROLOGUE
    ; Utkarsha input callback already registered in input_init
    xor rax, rax
    leave
    ret

ut_source_deinit:
    PROLOGUE
    xor rax, rax
    leave
    ret

ut_source_start:
    PROLOGUE
    xor rax, rax
    leave
    ret

ut_source_stop:
    PROLOGUE
    xor rax, rax
    leave
    ret

ut_source_get_device:
    cmp edi, 0
    je .no_device
    lea rax, [rel ut_device_info]
    mov [rax], edi
    ret
.no_device:
    xor eax, eax
    ret

ut_source_grab:
    test edi, edi
    jz .bad_grab
    mov [rel ut_grabbed_device], edi
    mov [rel ut_grab_state], sil
    xor eax, eax
    ret
.bad_grab:
    mov rax, -(EINVAL)
    ret

section .rodata
ut_source_name: db "utkarsha-input", 0

section .data
ut_device_info: dq 0, ut_source_name, 0
ut_grabbed_device: dd 0
ut_grab_state: db 0
global input_source_tv_version
input_source_tv_version: dq 0x010000
