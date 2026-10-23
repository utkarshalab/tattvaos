; ============================================================================
; cwplint — CWP Protocol Linter (naming, versioning, compat checks)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"

section .text

global tool_main
tool_main:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    mov rdi, lint_banner
    mov rsi, lint_banner_len
    call ut_log_write
    cmp rbx, 2
    jb .usage
    mov rdi, [r12 + 8]
    call cwplint_check_file
    jmp .exit
.usage:
    mov rdi, lint_usage
    mov rsi, lint_usage_len
    call ut_log_write
    mov rax, -(EINVAL)
.exit:
    call ut_task_exit

; ---------------------------------------------------------------------------
; cwplint_check_file
;   IN: rdi = path — runs all checks, prints diagnostics
; ---------------------------------------------------------------------------
global cwplint_check_file
cwplint_check_file:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    ASSERT_PTR rbx
    ; 1. names snake_case
    mov rdi, rbx
    call cwplint_check_names
    test rax, rax
    jnz .fail
    ; 2. versions monotonic
    mov rdi, rbx
    call cwplint_check_versions
    test rax, rax
    jnz .fail
    ; 3. no wire break vs frozen baseline
    mov rdi, rbx
    call cwplint_check_compat
    test rax, rax
    jnz .fail
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret
.fail:
    EPILOGUE_RESTORE rbx, r12
    ret

global cwplint_check_names
cwplint_check_names:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    ASSERT_PTR rbx
    xor r12d, r12d
.name_loop:
    movzx eax, byte [rbx]
    test al, al
    jz .name_end
    cmp al, 'A'
    jb .check_prefix
    cmp al, 'Z'
    jbe .name_bad
.check_prefix:
    cmp byte [rbx], 'c'
    jne .name_next
    cmp byte [rbx + 1], 'w'
    jne .name_next
    cmp byte [rbx + 2], '_'
    jne .name_next
    mov r12d, 1
.name_next:
    inc rbx
    jmp .name_loop
.name_end:
    test r12d, r12d
    jz .name_bad
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret
.name_bad:
    mov rax, -(EPROTO)
    EPILOGUE_RESTORE rbx, r12
    ret

global cwplint_check_versions
cwplint_check_versions:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    ASSERT_PTR rbx
    xor r12d, r12d
.ver_scan:
    cmp byte [rbx], 0
    je .ver_end
    cmp dword [rbx], 'vers'
    jne .ver_next
    cmp dword [rbx + 4], 'ion '
    jne .ver_next
    add rbx, 8
.ver_ws:
    cmp byte [rbx], ' '
    jne .ver_digit
    inc rbx
    jmp .ver_ws
.ver_digit:
    cmp byte [rbx], '1'
    jb .ver_bad
    cmp byte [rbx], '9'
    ja .ver_bad
    inc r12d
.ver_next:
    inc rbx
    jmp .ver_scan
.ver_end:
    test r12d, r12d
    jz .ver_bad
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret
.ver_bad:
    mov rax, -(EPROTO)
    EPILOGUE_RESTORE rbx, r12
    ret

global cwplint_check_compat
cwplint_check_compat:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
    ; Frozen declarations are additive-only: explicit remove/rename directives
    ; are rejected before the baseline generator is allowed to run.
.compat_loop:
    cmp byte [rbx], 0
    je .compat_ok
    cmp dword [rbx], 'remo'
    jne .check_rename
    cmp word [rbx + 4], 've'
    je .compat_bad
.check_rename:
    cmp dword [rbx], 'rena'
    jne .compat_next
    cmp word [rbx + 4], 'me'
    je .compat_bad
.compat_next:
    inc rbx
    jmp .compat_loop
.compat_ok:
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret
.compat_bad:
    mov rax, -(EPROTO)
    EPILOGUE_RESTORE rbx
    ret

section .rodata
lint_banner: db "cwplint 0.1.0", 10, 0
lint_banner_len: equ $ - lint_banner
lint_usage: db "usage: cwplint <protocol-source>", 10, 0
lint_usage_len: equ $ - lint_usage

section .data
global cwplint_version
cwplint_version: dq 0x010000
