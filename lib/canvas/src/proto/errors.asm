; ============================================================================
; Protocol Errors — Error Objects for CWP
; ============================================================================

%include "inc/abi.inc"
%include "inc/externs.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/cwp.inc"
%include "inc/channel.inc"
%include "inc/struct_offsets.inc"

%define CWP_DISPLAY_EVENT_ERROR 1
%define ERROR_MESSAGE_MAX       244

section .text

; ---------------------------------------------------------------------------
; errors_create
;   Create protocol error object
;   IN:  rdi = arena, rsi = error_code, rdx = message
;   OUT: rax = error_object_ptr, 0 on OOM
; ---------------------------------------------------------------------------
global errors_create
errors_create:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r13

    ; Allocate error object
    ; struct Error { code, message_ptr, message_len }
    mov rdi, rbx
    mov rsi, 24
    call arena_alloc
    test rax, rax
    jz .oom
    mov r14, rax

    mov [r14 + 0], r12d      ; error code
    mov dword [r14 + 4], 0   ; reserved
    mov [r14 + 8], r13       ; message ptr
    mov rdi, r13
    call str_len
    mov [r14 + 16], rax      ; message len
    mov rax, r14
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; errors_send
;   Send error to client via channel
;   IN:  rdi = client*, rsi = error_object*
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global errors_send
errors_send:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 288
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rdi, rsp
    xor rsi, rsi
    mov rdx, 288
    call memset

    mov r13, [r12 + 16]
    cmp r13, ERROR_MESSAGE_MAX
    jbe .length_ok
    mov r13, ERROR_MESSAGE_MAX
.length_ok:
    mov dword [rsp + 16], 0
    mov eax, [r12]
    mov [rsp + 20], eax
    mov [rsp + 24], r13d
    lea rdi, [rsp + 28]
    mov rsi, [r12 + 8]
    mov rdx, r13
    call memcopy

    lea eax, [r13 + 15]
    and eax, -4
    mov dword [rsp], CWP_OBJ_DISPLAY
    mov word [rsp + 4], CWP_DISPLAY_EVENT_ERROR
    mov word [rsp + 6], CWP_MSG_FLAG_IS_EVENT
    mov [rsp + 8], eax

    mov rdi, [rbx + Client.rx_ring]
    test rdi, rdi
    jz .no_channel
    mov rsi, rsp
    lea rdx, [rsp + 16]
    call msgbuf_write
    add rsp, 288
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.no_channel:
    mov rax, -(ENOTCONN)
    add rsp, 288
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; errors_from_errno
;   Convert errno to CWP error code
;   IN:  rdi = errno (positive)
;   OUT: rax = CWP error code
; ---------------------------------------------------------------------------
global errors_from_errno
errors_from_errno:
    PROLOGUE
    ; Map standard errors to CWP errors
    cmp rdi, EINVAL
    je .einval
    cmp rdi, ENOMEM
    je .enomem
    cmp rdi, EACCES
    je .eacces
    cmp rdi, ENOSPC
    je .enospc
    cmp rdi, ENOSYS
    je .enosys
    cmp rdi, EPERM
    je .eperm
    cmp rdi, ENOENT
    je .enoent
    cmp rdi, EBUSY
    je .ebusy
    cmp rdi, ETIMEDOUT
    je .etimedout
    cmp rdi, EINTR
    je .eintr
    cmp rdi, EIO
    je .eio

    ; Default to implementation error
    mov rax, ECWP_PARSE
    leave
    ret

.einval:    mov rax, ECWP_PAYLOAD; jmp .mapped
.enomem:    mov rax, ECWP_PARSE; jmp .mapped
.eacces:    mov rax, ECWP_CAP; jmp .mapped
.enospc:    mov rax, ECWP_FULL; jmp .mapped
.enosys:    mov rax, ECWP_OPCODE; jmp .mapped
.eperm:     mov rax, ECWP_CAP; jmp .mapped
.enoent:    mov rax, ECWP_OBJECT; jmp .mapped
.ebusy:     mov rax, ECWP_PARSE; jmp .mapped
.etimedout: mov rax, ECWP_PARSE; jmp .mapped
.eintr:     mov rax, ECWP_PARSE; jmp .mapped
.eio:       mov rax, ECWP_PARSE
.mapped:
    leave
    ret

; ---------------------------------------------------------------------------
; errors_standard
;   Standard error codes
; ---------------------------------------------------------------------------
section .rodata

global errors_version
errors_version: dq 0x010000
