; ============================================================================
; Containment — Fault Containment (kill one client, never stall server)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/canvas_client.inc"

; struct offsets (hoisted above use)
%define Containment_SIZE    24
%define FAULT_PROTO_VIOLATION   1
%define FAULT_OOM               2
%define FAULT_TIMEOUT           3
%define FAULT_TRAP              4
%define FAULT_RATE_EXCEEDED     5

section .text

struc Containment
    .server:         resq 1
    .faults:         resq 1
    .contained:      resq 1
endstruc


; ---------------------------------------------------------------------------
; containment_init
; ---------------------------------------------------------------------------
global containment_init
containment_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov rdi, [rbx + Server.arena]
    mov rsi, Containment_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax
    mov qword [rbx + Containment.server], rdi
    mov qword [rbx + Containment.faults], 0
    mov qword [rbx + Containment.contained], 0
    mov qword [rdi + Server.containment], rbx
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret
.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; containment_fault
;   Contain a faulty client: audit, free quota, destroy client
;   IN: rdi = server*, rsi = client*, rdx = fault_code
; ---------------------------------------------------------------------------
global containment_fault
containment_fault:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov rax, [rbx + Server.containment]
    test rax, rax
    jz .no_ct
    inc qword [rax + Containment.faults]
    inc qword [rax + Containment.contained]
.no_ct:
    ; audit the fault
    mov rdi, rbx
    mov rsi, 9  ; AUDIT_ACTION_GRANT_DENIED reused as fault
    mov rdx, [r12 + Client.id]
    mov rcx, r13
    mov r8, 3
    xor r9, r9
    xor r10, r10
    call audit_log
    ; tear down only this client
    mov rdi, rbx
    mov rsi, [r12 + Client.id]
    call client_disconnect
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; containment_proto_violation
; ---------------------------------------------------------------------------
global containment_proto_violation
containment_proto_violation:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov rdx, FAULT_PROTO_VIOLATION
    call containment_fault
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; containment_trap
; ---------------------------------------------------------------------------
global containment_trap
containment_trap:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov rdx, FAULT_TRAP
    call containment_fault
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; containment_stats
; ---------------------------------------------------------------------------
global containment_stats
containment_stats:
    PROLOGUE
    ASSERT_PTR rdi
    ASSERT_PTR rsi
    ASSERT_PTR rdx
    mov rax, [rdi + Server.containment]
    test rax, rax
    jz .none
    mov rcx, [rax + Containment.faults]
    mov [rsi], rcx
    mov rcx, [rax + Containment.contained]
    mov [rdx], rcx
    xor rax, rax
    leave
    ret
.none:
    mov qword [rsi], 0
    mov qword [rdx], 0
    xor rax, rax
    leave
    ret

section .data
global containment_version
containment_version: dq 0x010000
