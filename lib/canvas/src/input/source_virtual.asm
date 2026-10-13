; ============================================================================
; Virtual Input Source — Injected and Remote Input Events
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

; struct offsets (hoisted above use)
%define InputSource_virtual_ring  48
%define InputSource_virtual_size  56

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
    mov qword [r12 + InputSource.name], virtual_source_name
    mov qword [r12 + InputSource.init], virtual_source_init
    mov qword [r12 + InputSource.deinit], virtual_source_deinit
    mov qword [r12 + InputSource.start], virtual_source_start
    mov qword [r12 + InputSource.stop], virtual_source_stop
    mov qword [r12 + InputSource.get_device], virtual_source_get_device
    mov qword [r12 + InputSource.grab], virtual_source_grab

    ; Event ring for injected events
    mov rdi, [rbx + Server.arena]
    mov rsi, 256
    mov rdx, 24  ; Event size
    call ring_init
    test rax, rax
    jnz .ring_ok
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12
    ret

.ring_ok:
    mov qword [r12 + InputSource.virtual.ring], rax

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
;   Inject input event into virtual source
;   IN:  rdi = server*, rsi = event_type, rdx = code, rcx = value, r8 = device_id
; ---------------------------------------------------------------------------
global virtual_input_inject
virtual_input_inject:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Find virtual source
    mov r12, [rbx + Server.input_sources]
.find_loop:
    test r12, r12
    jz .not_found
    cmp dword [r12 + InputSource.type], INPUT_SOURCE_VIRTUAL
    je .found
    mov r12, [r12 + InputSource.next]
    jmp .find_loop

.found:
    ; Push event to ring
    sub rsp, 24
    mov [rsp + 0], rsi    ; type
    mov [rsp + 8], rdx    ; time (will be filled)
    mov [rsp + 16], rcx   ; code
    mov [rsp + 20], r8    ; value

    call tv_time_now_ns
    mov [rsp + 8], rax

    mov rdi, [r12 + InputSource.virtual.ring]
    mov rsi, rsp
    call ring_push
    test rax, rax
    jz .ring_full

    add rsp, 24
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.ring_full:
    add rsp, 24
    mov rax, -(ENOSPC)
    EPILOGUE_RESTORE rbx, r12
    ret

.not_found:
    mov rax, -(ENOENT)
    EPILOGUE_RESTORE rbx, r12
    ret

section .rodata
virtual_source_name: db "virtual-input", 0

section .data

global input_source_virtual_version
input_source_virtual_version: dq 0x010000
