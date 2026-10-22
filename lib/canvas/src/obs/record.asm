; ============================================================================
; Record — Deterministic Protocol Session Recorder (.cwprec)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/struct_offsets.inc"
%include "inc/canvas_client.inc"

extern arena_alloc
extern memcopy

; struct offsets (hoisted above use)
%define Recorder_file    64
%define Recorder.file    64
%define Recorder_SIZE    72
%define CWPREC_MAGIC     0x52505743  ; "CWPR"
%define CWPREC_VERSION   1
%define CwprecHeader_SIZE    40
%define CwprecFrame_SIZE    16

section .text

; Recorder struct layout (manual offsets)
; Offsets defined in inc/struct_offsets.inc
; ----------


struc CwprecHeader
    .magic:          resd 1
    .version:        resd 1
    .frame_count:    resq 1
    .start_time:     resq 1
    .reserved:       resq 2
endstruc

struc CwprecFrame
    .timestamp:      resq 1
    .msg_count:      resd 1
    .msg_bytes:      resd 1
endstruc

; ---------------------------------------------------------------------------
; record_init
; ---------------------------------------------------------------------------
global record_init
record_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov rdi, [rbx + Server.arena]
    mov rsi, Recorder_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov r12, rax
    mov qword [r12 + Recorder.server], rbx
    mov byte [r12 + Recorder.active], 0
    mov qword [r12 + Recorder.path], 0
    mov qword [r12 + Recorder.path_len], 0
    mov qword [r12 + Recorder.frames], 0
    mov qword [r12 + Recorder.msg_count], 0
    mov qword [r12 + Recorder.bytes], 0
    mov qword [r12 + Recorder.start_time], 0
    mov qword [r12 + Recorder.file], 0
    mov qword [rbx + Server.recorder], r12
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret
.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; record_start
;   IN: rdi = server*, rsi = path, rdx = path_len
; ---------------------------------------------------------------------------
global record_start
record_start:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov rax, [rbx + Server.recorder]
    test rax, rax
    jz .none
    mov rbx, rax
    cmp byte [rbx + Recorder.active], 1
    je .busy
    ; copy path
    mov rdi, [rbx + Recorder.server]
    mov rdi, [rdi + Server.arena]
    mov rsi, r13
    inc rsi
    call arena_alloc
    test rax, rax
    jz .oom
    mov rdi, rax
    mov rsi, r12
    mov rdx, r13
    call memcopy
    mov byte [rax + r13], 0
    mov [rbx + Recorder.path], rax
    mov [rbx + Recorder.path_len], r13
    mov qword [rbx + Recorder.frames], 0
    mov qword [rbx + Recorder.msg_count], 0
    mov qword [rbx + Recorder.bytes], 0
    call tv_time_now_ns
    mov [rbx + Recorder.start_time], rax
    mov byte [rbx + Recorder.active], 1
    mov rdi, [rbx + Recorder.path]
    SYSCALL SYS_FS_OPEN
    test rax, rax
    js .oom
    mov [rbx + Recorder.file], rax
    ; write header
    sub rsp, CwprecHeader_size
    mov dword [rsp + 0], CWPREC_MAGIC
    mov dword [rsp + 4], CWPREC_VERSION
    mov qword [rsp + 8], 0
    mov rax, [rbx + Recorder.start_time]
    mov [rsp + 16], rax
    mov qword [rsp + 24], 0
    mov qword [rsp + 32], 0
    mov rdi, [rbx + Recorder.file]
    mov rsi, rsp
    mov rdx, CwprecHeader_size
    xor rcx, rcx
    SYSCALL SYS_FS_PWRITE
    cmp rax, CwprecHeader_size
    jne .write_fail
    add rsp, CwprecHeader_size
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.write_fail:
    add rsp, CwprecHeader_size
    mov rdi, [rbx + Recorder.file]
    SYSCALL SYS_FS_CLOSE
    mov byte [rbx + Recorder.active], 0
    mov rax, -(EIO)
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.busy:
    mov rax, -(EBUSY)
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.none:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; record_frame
;   Record one frame batch: messages already validated
;   IN: rdi = server*, rsi = msg_blob, rdx = msg_count, rcx = msg_bytes
; ---------------------------------------------------------------------------
global record_frame
record_frame:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    ASSERT_PTR rbx
    mov rax, [rbx + Server.recorder]
    test rax, rax
    jz .done
    mov rbx, rax
    cmp byte [rbx + Recorder.active], 0
    je .done
    sub rsp, CwprecFrame_size
    call tv_time_now_ns
    mov [rsp], rax
    mov [rsp + 8], r13d
    mov [rsp + 12], r14d
    mov rdi, [rbx + Recorder.file]
    mov rsi, rsp
    mov rdx, CwprecFrame_size
    mov rcx, [rbx + Recorder.frames]
    imul rcx, CwprecFrame_size
    add rcx, [rbx + Recorder.bytes]
    add rcx, CwprecHeader_size
    SYSCALL SYS_FS_PWRITE
    cmp rax, CwprecFrame_size
    jne .frame_fail
    mov rdi, [rbx + Recorder.file]
    mov rsi, r12
    mov rdx, r14
    mov rcx, [rbx + Recorder.frames]
    inc rcx
    imul rcx, CwprecFrame_size
    add rcx, [rbx + Recorder.bytes]
    add rcx, CwprecHeader_size
    SYSCALL SYS_FS_PWRITE
    cmp rax, r14
    jne .frame_fail
    add rsp, CwprecFrame_size
    inc qword [rbx + Recorder.frames]
    add [rbx + Recorder.msg_count], r13
    add [rbx + Recorder.bytes], r14
.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.frame_fail:
    add rsp, CwprecFrame_size
    mov rax, -(EIO)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; record_stop
; ---------------------------------------------------------------------------
global record_stop
record_stop:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
    mov rax, [rbx + Server.recorder]
    test rax, rax
    jz .none
    mov rbx, rax
    cmp byte [rbx + Recorder.active], 0
    je .done
    mov byte [rbx + Recorder.active], 0
    sub rsp, 8
    mov rax, [rbx + Recorder.frames]
    mov [rsp], rax
    mov rdi, [rbx + Recorder.file]
    mov rsi, rsp
    mov rdx, 8
    mov rcx, 8
    SYSCALL SYS_FS_PWRITE
    add rsp, 8
    mov rdi, [rbx + Recorder.file]
    SYSCALL SYS_FS_CLOSE
    mov qword [rbx + Recorder.file], 0
.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret
.none:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; record_is_active
; ---------------------------------------------------------------------------
global record_is_active
record_is_active:
    PROLOGUE
    ASSERT_PTR rdi
    mov rax, [rdi + Server.recorder]
    test rax, rax
    jz .no
    movzx rax, byte [rax + Recorder.active]
    leave
    ret
.no:
    xor rax, rax
    leave
    ret

section .data
global record_version
record_version: dq 0x010000
