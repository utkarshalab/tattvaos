; ============================================================================
; Fault Dump — Crash/Fault State Capture (registers, recent trace)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/canvas_client.inc"

; struct offsets (hoisted above use)
%define FaultDump_SIZE    104

section .text

; FaultDump struct layout (manual offsets)\n; Offsets defined in inc/struct_offsets.inc\n\n; ----------\n

; ---------------------------------------------------------------------------
; faultdump_init
; ---------------------------------------------------------------------------
global faultdump_init
faultdump_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov rdi, [rbx + Server.arena]
    mov rsi, FaultDump_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov qword [rdi + Server.faultdump], rax
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret
.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; faultdump_capture
;   IN: rdi=server*, rsi=fault_code, rdx=client_id, rcx=object, r8=opcode
; ---------------------------------------------------------------------------
global faultdump_capture
faultdump_capture:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    mov rax, [rbx + Server.faultdump]
    test rax, rax
    jz .none
    mov rbx, rax
    push r8
    push rcx
    push rdx
    call tv_time_now_ns
    mov [rbx + FaultDump.time_ns], rax
    pop rdx
    pop rcx
    pop r8
    mov [rbx + FaultDump.fault_code], r12d
    mov [rbx + FaultDump.client_id], rdx
    mov [rbx + FaultDump.object], ecx
    mov [rbx + FaultDump.opcode], r8w
    ; capture general registers of caller frame (best effort)
    mov [rbx + FaultDump.rax], rax
    mov [rbx + FaultDump.rbx], rbx
    mov [rbx + FaultDump.rcx], rcx
    mov [rbx + FaultDump.rdx], rdx
    mov [rbx + FaultDump.rsi], rsi
    mov [rbx + FaultDump.rdi], rdi
    mov [rbx + FaultDump.rbp], rbp
    mov [rbx + FaultDump.rsp], rsp
    mov rax, [rsp]
    mov [rbx + FaultDump.rip], rax
    ; emit to serial + trace
    mov rdi, faultdump_msg
    mov rsi, faultdump_msg_len
    call tv_log_write
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret
.none:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; faultdump_get
; ---------------------------------------------------------------------------
global faultdump_get
faultdump_get:
    PROLOGUE
    ASSERT_PTR rdi
    mov rax, [rdi + Server.faultdump]
    leave
    ret

section .rodata
faultdump_msg: db "FAULTDUMP: captured", 10, 0
faultdump_msg_len: equ $ - faultdump_msg

section .data
global faultdump_version
faultdump_version: dq 0x010000
