; ============================================================================
; Protocol Log — Full Message Log for Replay and Debugging
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/struct_offsets.inc"
%include "inc/canvas_client.inc"

extern arena_alloc

; struct offsets (hoisted above use)
%define ProtoLog_SIZE    56
%define ProtoLogEntry_SIZE    40
%define PROTOLOG_DEFAULT_CAPACITY 2048
%define PROTOLOG_DIR_C2S      0
%define PROTOLOG_DIR_S2C      1

section .text

; ProtoLog struct layout (manual offsets)\n; Offsets defined in inc/struct_offsets.inc\n\n; ----------\n

; ProtoLogEntry struct layout (manual offsets)\n; Offsets defined in inc/struct_offsets.inc\n\n; ----------\n


; ---------------------------------------------------------------------------
; protolog_init
; ---------------------------------------------------------------------------
global protolog_init
protolog_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov rdi, [rbx + Server.arena]
    mov rsi, ProtoLog_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax
    mov qword [rbx + ProtoLog.server], rdi
    mov rdi, [rbx + ProtoLog.server]
    mov rdi, [rdi + Server.arena]
    mov rsi, PROTOLOG_DEFAULT_CAPACITY
    imul rsi, ProtoLogEntry_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov qword [rbx + ProtoLog.buf], rax
    mov qword [rbx + ProtoLog.capacity], PROTOLOG_DEFAULT_CAPACITY
    mov qword [rbx + ProtoLog.write_pos], 0
    mov qword [rbx + ProtoLog.count], 0
    mov byte [rbx + ProtoLog.enabled], 1
    mov qword [rbx + ProtoLog.dropped], 0
    mov qword [rdi + Server.protolog], rbx
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret
.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; protolog_log
;   IN: rdi=server*, rsi=client_id, rdx=dir, rcx=obj, r8=opcode,
;       r9=flags, stack len
; ---------------------------------------------------------------------------
global protolog_log
protolog_log:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    mov rax, [rbx + Server.protolog]
    test rax, rax
    jz .disabled
    mov rbx, rax
    cmp byte [rbx + ProtoLog.enabled], 0
    je .disabled
    mov rax, [rbx + ProtoLog.write_pos]
    mov rdi, [rbx + ProtoLog.buf]
    imul rax, ProtoLogEntry_size
    add rdi, rax
    call ut_time_now_ns
    mov [rdi + ProtoLogEntry.time_ns], rax
    mov [rdi + ProtoLogEntry.client_id], r12
    mov [rdi + ProtoLogEntry.dir], dl
    mov [rdi + ProtoLogEntry.obj], ecx
    mov [rdi + ProtoLogEntry.opcode], r8w
    mov [rdi + ProtoLogEntry.flags], r9w
    mov rax, [rsp + 56]
    mov [rdi + ProtoLogEntry.len], eax
    mov qword [rdi + ProtoLogEntry.payload_off], 0
    mov rax, [rbx + ProtoLog.write_pos]
    inc rax
    cmp rax, [rbx + ProtoLog.capacity]
    jb .no_wrap
    xor rax, rax
.no_wrap:
    mov [rbx + ProtoLog.write_pos], rax
    mov rax, [rbx + ProtoLog.count]
    cmp rax, [rbx + ProtoLog.capacity]
    jae .full
    inc qword [rbx + ProtoLog.count]
    EPILOGUE_RESTORE rbx, r12
    ret
.full:
    inc qword [rbx + ProtoLog.dropped]
    EPILOGUE_RESTORE rbx, r12
    ret
.disabled:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; protolog_set_enabled
; ---------------------------------------------------------------------------
global protolog_set_enabled
protolog_set_enabled:
    PROLOGUE
    ASSERT_PTR rdi
    mov rax, [rdi + Server.protolog]
    test rax, rax
    jz .none
    mov [rax + ProtoLog.enabled], sil
    xor rax, rax
    leave
    ret
.none:
    mov rax, -(ENOMEM)
    leave
    ret

section .data
global protolog_version
protolog_version: dq 0x010000
