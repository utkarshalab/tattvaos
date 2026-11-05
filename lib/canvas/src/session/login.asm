; ============================================================================
; Login — Checking the Greeter's Password
; ============================================================================
; login_verify is the greeter's verify hook. It asks the kernel, which keeps
; the accounts (ut_auth_verify, docs/KERNEL_NEEDS.md), whether the password
; is the machine's user's; canvasd reads no account itself. A kernel without
; the export refuses everything, so nobody is let in by accident. After
; LOGIN_TRIES wrong passwords in a row every password is refused for
; LOGIN_LOCK_NS, so guessing is slow. The greeter wipes the text after each
; check; nothing here keeps it.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"

extern ut_auth_verify

%define LOGIN_TRIES     3
%define LOGIN_LOCK_NS   5000000000      ; five seconds

section .text

; ---------------------------------------------------------------------------
; login_verify
;   IN:  rdi = password (UTF-8), esi = its length
;   OUT: rax = 0 if it is right, 1 if not (wrong, locked out, or no kernel
;        check)
; ---------------------------------------------------------------------------
global login_verify
login_verify:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12d, esi
    call ut_time_now_ns
    cmp rax, [rel locked_until]
    jb .refused                         ; still locked out
    xor edi, edi                        ; the machine's user: no name yet
    xor esi, esi
    mov rdx, rbx
    mov ecx, r12d
    call ut_auth_verify
    test rax, rax
    jz .right
    inc dword [rel failures]
    cmp dword [rel failures], LOGIN_TRIES
    jb .refused
    mov dword [rel failures], 0         ; too many: a pause before the next
    call ut_time_now_ns
    mov rcx, LOGIN_LOCK_NS
    add rax, rcx
    mov [rel locked_until], rax
.refused:
    mov eax, 1
    jmp .out
.right:
    mov dword [rel failures], 0
    xor eax, eax
.out:
    EPILOGUE_RESTORE rbx, r12

; ---------------------------------------------------------------------------
; login_reset
;   No failures counted, no lockout
; ---------------------------------------------------------------------------
global login_reset
login_reset:
    mov dword [rel failures], 0
    mov qword [rel locked_until], 0
    xor eax, eax
    ret

section .bss
alignb 8
locked_until:   resq 1                  ; monotonic ns; before it all is refused
failures:       resd 1                  ; wrong in a row
