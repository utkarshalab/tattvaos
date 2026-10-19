; ============================================================================
; Audit — Append-Only Audit Log
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/struct_offsets.inc"
%include "inc/externs.inc"
%include "inc/ring.inc"

; struct offsets (hoisted above use)
%define AuditEntry_SIZE    48
%define AUDIT_ACTION_CAP_GRANT      1
%define AUDIT_ACTION_CAP_REVOKE     2
%define AUDIT_ACTION_CAP_CHECK      3
%define AUDIT_ACTION_PRIVILEGED     4
%define AUDIT_ACTION_CLIENT_CONNECT 5
%define AUDIT_ACTION_CLIENT_DISCONNECT 6
%define AUDIT_ACTION_POLICY_CHANGE  7
%define AUDIT_ACTION_PROFILE_CHANGE 8
%define AUDIT_ACTION_GRANT_DENIED   9
%define AUDIT_RESULT_GRANTED        1
%define AUDIT_RESULT_DENIED         2
%define AUDIT_RESULT_ERROR          3
%define AUDIT_LOG_SIZE    (64 * 1024)  ; 64KB ring buffer

section .text

struc AuditEntry
    .timestamp:    resq 1
    .client_id:    resq 1
    .action:       resd 1
    .capability:   resq 1
    .result:       resd 1
    .details_len:  resq 1
    .details:      resq 1
endstruc




; ---------------------------------------------------------------------------
; audit_init
; ---------------------------------------------------------------------------
global audit_init
audit_init:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Allocate the log header and backing entries separately.
    mov rdi, r12
    mov rsi, AuditLog_SIZE
    call arena_alloc
    test rax, rax
    jz .oom
    mov r13, rax

    mov rdi, r12
    mov rsi, AUDIT_LOG_SIZE
    call arena_alloc
    test rax, rax
    jz .oom

    mov qword [r13 + AuditLog.buffer], rax
    mov qword [r13 + AuditLog.capacity], AUDIT_LOG_SIZE / AuditEntry_SIZE
    mov qword [r13 + AuditLog.head], 0
    mov qword [r13 + AuditLog.tail], 0
    mov qword [r13 + AuditLog.element_size], AuditEntry_SIZE
    mov qword [r13 + AuditLog.count], 0

    mov qword [rbx + Server.audit_log], r13
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; audit_log
;   Log audit entry
;   IN: rdi = server*, rsi = action, rdx = client_id, rcx = capability, r8 = result, r9 = details, r10 = details_len
; ---------------------------------------------------------------------------
global audit_log
audit_log:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 32
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    mov [rsp], r9
    mov [rsp + 8], r10
    ASSERT_PTR rbx

    mov rbx, [rbx + Server.audit_log]
    test rbx, rbx
    jz .no_log

    mov rax, [rbx + AuditLog.head]
    imul rax, AuditEntry_SIZE
    mov rdi, [rbx + AuditLog.buffer]
    add rdi, rax
    mov [rsp + 16], rdi

    call tv_time_now_ns
    mov rdi, [rsp + 16]
    mov [rdi + AuditEntry_timestamp], rax
    mov [rdi + AuditEntry_client_id], r13
    mov [rdi + AuditEntry_action], r12d
    mov [rdi + AuditEntry_capability], r14
    mov [rdi + AuditEntry_result], r15d
    mov rax, [rsp + 8]
    mov [rdi + AuditEntry_details_len], rax
    mov rax, [rsp]
    mov [rdi + AuditEntry_details], rax

    mov rax, [rbx + AuditLog.head]
    inc rax
    cmp rax, [rbx + AuditLog.capacity]
    jb .head_ready
    xor rax, rax
.head_ready:
    mov [rbx + AuditLog.head], rax

    mov rcx, [rbx + AuditLog.count]
    cmp rcx, [rbx + AuditLog.capacity]
    jae .full
    inc qword [rbx + AuditLog.count]
    jmp .done

.full:
    mov rcx, [rbx + AuditLog.tail]
    inc rcx
    cmp rcx, [rbx + AuditLog.capacity]
    jb .tail_ready
    xor rcx, rcx
.tail_ready:
    mov [rbx + AuditLog.tail], rcx

.done:
    xor rax, rax
.no_log:
    add rsp, 32
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; audit_query
;   Copy oldest-first entries into a caller buffer.
;   IN: rdi = server*, rsi = AuditEntry output[], rdx = output capacity
;   OUT: rax = number of entries copied
; ---------------------------------------------------------------------------
global audit_query
audit_query:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    ASSERT_PTR rdi
    mov rbx, [rdi + Server.audit_log]
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR r12
    test rbx, rbx
    jz .query_empty
    mov r15, [rbx + AuditLog.count]
    cmp r15, r13
    cmova r15, r13
    mov r14, [rbx + AuditLog.tail]
    xor r13, r13
.query_loop:
    cmp r13, r15
    jae .query_done
    mov rax, r14
    imul rax, AuditEntry_SIZE
    mov rsi, [rbx + AuditLog.buffer]
    add rsi, rax
    mov rdi, r12
    mov rax, r13
    imul rax, AuditEntry_SIZE
    add rdi, rax
    mov rdx, AuditEntry_SIZE
    call memcopy
    inc r14
    cmp r14, [rbx + AuditLog.capacity]
    jb .query_next
    xor r14, r14
.query_next:
    inc r13
    jmp .query_loop
.query_done:
    mov rax, r15
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.query_empty:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

section .data
global audit_version
audit_version: dq 0x010000
