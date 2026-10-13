; ============================================================================
; Protocol Errors — Error Objects for CWP
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

section .text

; ---------------------------------------------------------------------------
; errors_create
;   Create protocol error object
;   IN:  rdi = arena, rsi = error_code, rdx = message
;   OUT: rax = error_object_ptr, 0 on OOM
; ---------------------------------------------------------------------------
global errors_create
errors_create:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx

    ; Allocate error object
    ; struct Error { code, message_ptr, message_len }
    mov rdi, rbx
    mov rsi, 24
    call arena_alloc
    test rax, rax
    jz .oom

    mov [rax + 0], r12d      ; error code
    mov [rax + 4], 0         ; reserved
    mov [rax + 8], r13       ; message ptr
    call str_len
    mov [rax + 16], rax      ; message len
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; errors_send
;   Send error to client via channel
;   IN:  rdi = client*, rsi = error_object*
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global errors_send
errors_send:
    PROLOGUE
    ; TODO: Encode error event into client's RX ring
    xor rax, rax
    leave
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

.einval:    mov rax, ECWP_PAYLOAD; ret
.enomem:    mov rax, ECWP_PARSE; ret
.eacces:    mov rax, ECWP_CAP; ret
.enospc:    mov rax, ECWP_FULL; ret
.enosys:    mov rax, ECWP_OPCODE; ret
.eperm:     mov rax, ECWP_CAP; ret
.enoent:    mov rax, ECWP_OBJECT; ret
.ebusy:     mov rax, ECWP_PARSE; ret
.etimedout: mov rax, ECWP_PARSE; ret
.eintr:     mov rax, ECWP_PARSE; ret
.eio:       mov rax, ECWP_PARSE; ret

; ---------------------------------------------------------------------------
; errors_standard
;   Standard error codes
; ---------------------------------------------------------------------------
section .rodata

global errors_version
errors_version: dq 0x010000
