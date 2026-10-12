; ============================================================================
; CRP Session — Per-Viewer Session Lifecycle
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

section .text

struc CrpSession {
    .server:         resq 1
    .conn:           resq 1
    .view_only:      resb 1
    .seq:            resq 1
    .next:           resq 1
}
%define CrpSession_size    40

global crp_session_create
crp_session_create:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13b, dl
    ASSERT_PTR rbx
    mov rdi, [rbx + Server.arena]
    mov rsi, CrpSession_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov qword [rax + CrpSession.server], rbx
    mov qword [rax + CrpSession.conn], r12
    mov byte [rax + CrpSession.view_only], r13b
    mov qword [rax + CrpSession.seq], 0
    mov rdx, [rbx + CrpServer.sessions]
    mov [rax + CrpSession.next], rdx
    mov [rbx + CrpServer.sessions], rax
    ret
.oom:
    RETURN_ERROR ENOMEM

global crp_session_destroy
crp_session_destroy:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov rax, [rbx + CrpServer.sessions]
    test rax, rax
    jz .not_found
    cmp rax, r12
    je .remove_head
    mov rbx, rax
.find:
    mov rax, [rax + CrpSession.next]
    test rax, rax
    jz .not_found
    cmp rax, r12
    je .remove_mid
    mov rbx, rax
    jmp .find
.remove_head:
    mov rax, [r12 + CrpSession.next]
    mov [rbx + CrpServer.sessions], rax
    jmp .close
.remove_mid:
    mov rax, [r12 + CrpSession.next]
    mov [rbx + CrpSession.next], rax
.close:
    mov rdi, [r12 + CrpSession.conn]
    call tv_tls_close
    xor rax, rax
    ret
.not_found:
    RETURN_ERROR ENOENT

section .data
global crp_session_version
crp_session_version: dq 0x010000
