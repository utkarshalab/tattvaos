; ============================================================================
; CRP Share — Multi-Viewer Broadcast
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

extern crp_send_frame

; Struct definitions (from crp_server.asm and crp_session.asm)
struc CrpServer
    .server:         resq 1
    .listener:       resq 1
    .port:           resd 1
    .sessions:       resq 1
    .voutput:        resq 1
    .running:        resb 1
endstruc

struc CrpSession
    .server:         resq 1
    .conn:           resq 1
    .view_only:      resb 1
    .seq:            resq 1
    .next:           resq 1
endstruc

; External function
extern crp_send_frame

section .text

global crp_share_broadcast
crp_share_broadcast:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    ASSERT_PTR rbx
    mov r12, [rbx + CrpServer.sessions]
    test r12, r12
    jz .done
.loop:
    mov rdi, rbx
    mov rsi, r12
    call crp_send_frame
    mov r12, [r12 + CrpSession.next]
    test r12, r12
    jnz .loop
.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

global crp_share_count
crp_share_count:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
    xor eax, eax
    mov rdx, [rbx + CrpServer.sessions]
.loop:
    test rdx, rdx
    jz .done
    inc eax
    mov rdx, [rdx + CrpSession.next]
    jmp .loop
.done:
    EPILOGUE_RESTORE rbx
    ret

section .data
global crp_share_version
crp_share_version: dq 0x010000
