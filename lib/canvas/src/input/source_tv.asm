; ============================================================================
; Tattva Input Source — Events from Tattva Kernel Drivers
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
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
    mov qword [r12 + InputSource.name], tv_source_name
    mov qword [r12 + InputSource.init], tv_source_init
    mov qword [r12 + InputSource.deinit], tv_source_deinit
    mov qword [r12 + InputSource.start], tv_source_start
    mov qword [r12 + InputSource.stop], tv_source_stop
    mov qword [r12 + InputSource.get_device], tv_source_get_device
    mov qword [r12 + InputSource.grab], tv_source_grab

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

tv_source_init:
    PROLOGUE
    ; Tattva input callback already registered in input_init
    xor rax, rax
    leave
    ret

tv_source_deinit:
    PROLOGUE
    xor rax, rax
    leave
    ret

tv_source_start:
    PROLOGUE
    xor rax, rax
    leave
    ret

tv_source_stop:
    PROLOGUE
    xor rax, rax
    leave
    ret

tv_source_get_device:
    cmp edi, 0
    je .no_device
    lea rax, [rel tv_device_info]
    mov [rax], edi
    ret
.no_device:
    xor eax, eax
    ret

tv_source_grab:
    test edi, edi
    jz .bad_grab
    mov [rel tv_grabbed_device], edi
    mov [rel tv_grab_state], sil
    xor eax, eax
    ret
.bad_grab:
    mov rax, -(EINVAL)
    ret

section .rodata
tv_source_name: db "tattva-input", 0

section .data
tv_device_info: dq 0, tv_source_name, 0
tv_grabbed_device: dd 0
tv_grab_state: db 0
global input_source_tv_version
input_source_tv_version: dq 0x010000
