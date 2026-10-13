; ============================================================================
; Record — Deterministic Protocol Session Recorder (.cwprec)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

; struct offsets (hoisted above use)
%define Recorder_size    56
%define CWPREC_MAGIC     0x52505743  ; "CWPR"
%define CWPREC_VERSION   1
%define CwprecHeader_size    40
%define CwprecFrame_size    16

section .text

struc Recorder
    .server:         resq 1
    .active:         resb 1
    .path:           resq 1
    .path_len:       resq 1
    .frames:         resq 1
    .msg_count:      resq 1
    .bytes:          resq 1
    .start_time:     resq 1
endstruc


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
    mov rbx, rax
    mov qword [rbx + Recorder.server], rdi
    mov byte [rbx + Recorder.active], 0
    mov qword [rbx + Recorder.path], 0
    mov qword [rbx + Recorder.path_len], 0
    mov qword [rbx + Recorder.frames], 0
    mov qword [rbx + Recorder.msg_count], 0
    mov qword [rbx + Recorder.bytes], 0
    mov qword [rbx + Recorder.start_time], 0
    mov qword [rdi + Server.recorder], rbx
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
    ; write header
    sub rsp, CwprecHeader_size
    mov dword [rsp + 0], CWPREC_MAGIC
    mov dword [rsp + 4], CWPREC_VERSION
    mov qword [rsp + 8], 0
    mov rax, [rbx + Recorder.start_time]
    mov [rsp + 16], rax
    mov qword [rsp + 24], 0
    mov qword [rsp + 32], 0
    ; TODO: write header to TVFS path (append mode)
    add rsp, CwprecHeader_size
    xor rax, rax
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
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    ASSERT_PTR rbx
    mov rax, [rbx + Server.recorder]
    test rax, rax
    jz .done
    mov rbx, rax
    cmp byte [rbx + Recorder.active], 0
    je .done
    ; TODO: append CwprecFrame + blob to TVFS path
    inc qword [rbx + Recorder.frames]
    add [rbx + Recorder.msg_count], rdx
    add [rbx + Recorder.bytes], rcx
.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
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
    ; TODO: patch header frame_count
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
