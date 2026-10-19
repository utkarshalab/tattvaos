; ============================================================================
; CRP Session — Per-Viewer Session Lifecycle
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/struct_offsets.inc"
%include "inc/externs.inc"

section .text

global crp_session_create
crp_session_create:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13b, dl
    ASSERT_PTR rbx
    mov rdi, [rbx + Server.arena]
    mov rsi, CrpSession_SIZE
    call arena_alloc
    test rax, rax
    jz .oom
    mov qword [rax + CrpSession_server], rbx
    mov qword [rax + CrpSession_conn], r12
    mov byte [rax + CrpSession_view_only], r13b
    mov qword [rax + CrpSession_seq], 0
    mov rdx, [rbx + CrpServer_sessions]
    mov [rax + CrpSession_next], rdx
    mov [rbx + CrpServer_sessions], rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

global crp_session_destroy
crp_session_destroy:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov rax, [rbx + CrpServer_sessions]
    test rax, rax
    jz .not_found
    cmp rax, r12
    je .remove_head
    mov rbx, rax
.find:
    mov rax, [rax + CrpSession_next]
    test rax, rax
    jz .not_found
    cmp rax, r12
    je .remove_mid
    mov rbx, rax
    jmp .find
.remove_head:
    mov rax, [r12 + CrpSession_next]
    mov [rbx + CrpServer_sessions], rax
    jmp .close
.remove_mid:
    mov rax, [r12 + CrpSession_next]
    mov [rbx + CrpSession_next], rax
.close:
    mov rdi, [r12 + CrpSession_conn]
    call tv_tls_close
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret
.not_found:
    mov rax, -(ENOENT)
    EPILOGUE_RESTORE rbx, r12
    ret

section .data
global crp_session_version
crp_session_version: dq 0x010000
