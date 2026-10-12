; ============================================================================
; Audit — Append-Only Audit Log
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/ring.asm"

section .text

struc AuditEntry {
    .timestamp:    resq 1
    .client_id:    resq 1
    .action:       resd 1
    .capability:   resq 1
    .result:       resd 1
    .details_len:  resq 1
    .details:      resq 1
}
%define AuditEntry_size    48

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

; ---------------------------------------------------------------------------
; audit_init
; ---------------------------------------------------------------------------
global audit_init
audit_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Allocate audit log ring buffer
    mov rdi, r12
    mov rsi, AUDIT_LOG_SIZE
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax

    ; Initialize ring buffer
    mov qword [rbx + AuditLog.buffer], rbx
    mov qword [rbx + AuditLog.capacity], AUDIT_LOG_SIZE
    mov qword [rbx + AuditLog.head], 0
    mov qword [rbx + AuditLog.tail], 0
    mov qword [rbx + AuditLog.element_size], AuditEntry_size
    mov qword [rbx + AuditLog.count], 0

    mov qword [rdi + Server.audit_log], rbx
    xor rax, rax
    ret

.oom:
    RETURN_ERROR ENOMEM

; ---------------------------------------------------------------------------
; audit_log
;   Log audit entry
;   IN: rdi = server*, rsi = action, rdx = client_id, rcx = capability, r8 = result, r9 = details, r10 = details_len
; ---------------------------------------------------------------------------
global audit_log
audit_log:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    ASSERT_PTR rbx

    ; Get audit log
    mov rax, [rbx + Server.audit_log]
    test rax, rax
    jz .no_log

    ; Allocate details buffer
    test r10, r10
    jz .no_details

    mov rdi, [rbx + Server.arena]
    mov rsi, r10
    call arena_alloc
    test rax, rax
    jz .oom
    mov r12, rax

    mov rdi, r12
    mov rsi, r9
    mov rdx, r10
    call memcopy

.no_details:
    xor r12, r12

    ; Write entry
    mov rdi, rax
    mov rsi, r12  ; action
    mov rdx, r13  ; client_id
    mov rcx, r14  ; capability
    mov r8, r15   ; result
    mov r9, r12   ; details
    mov r10, r10  ; details_len

    ; Write to ring buffer
    call audit_write_entry

    ret

.no_log:
    xor rax, rax
    ret

.oom:
    RETURN_ERROR ENOMEM

; ---------------------------------------------------------------------------
; audit_write_entry
; ---------------------------------------------------------------------------
audit_write_entry:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    ; Get current head
    mov rax, [rbx + AuditLog.head]
    mov rcx, [rbx + AuditLog.capacity]

    ; Write entry
    mov rdi, [rbx + AuditLog.buffer]
    add rdi, rax

    ; Fill entry
    call tv_time_now_ns
    mov [rdi + AuditEntry.timestamp], rax
    mov [rdi + AuditEntry.client_id], r12
    mov [rdi + AuditEntry.action], r13d
    mov [rdi + AuditEntry.capability], r14
    mov [rdi + AuditEntry.result], r15d
    mov [rdi + AuditEntry.details_len], r10
    mov [rdi + AuditEntry.details], r9

    ; Advance head
    add rax, AuditEntry_size
    cmp rax, rcx
    jb .no_wrap
    xor rax, rax
.no_wrap:
    mov [rbx + AuditLog.head], rax

    ; Update count
    mov rax, [rbx + AuditLog.count]
    cmp rax, rcx
    jae .full
    inc qword [rbx + AuditLog.count]
    ret

.full:
    ; Overwrite oldest
    add qword [rbx + AuditLog.tail], AuditEntry_size
    cmp qword [rbx + AuditLog.tail], rcx
    jb .no_wrap_tail
    mov qword [rbx + AuditLog.tail], 0
.no_wrap_tail:
    ret

; ---------------------------------------------------------------------------
; audit_query
;   Query audit log
; ---------------------------------------------------------------------------
global audit_query
audit_query:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx

    ; TODO: Implement query with filters
    xor rax, rax
    ret

section .data
global audit_version
audit_version: dq 0x010000