; ============================================================================
; cwplint — CWP Protocol Linter (naming, versioning, compat checks)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

section .text

global tool_main
tool_main:
    PROLOGUE_SAVE rbx
    mov rdi, lint_banner
    mov rsi, lint_banner_len
    call tv_log_write
    ; TODO: argv = .cwp path; run checks below
    xor rax, rax
    call tv_task_exit

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
    ret
.fail:
    ret

global cwplint_check_names
cwplint_check_names:
    PROLOGUE
    ; TODO: parse identifiers, enforce snake_case + cw_ prefix
    xor rax, rax
    ret

global cwplint_check_versions
cwplint_check_versions:
    PROLOGUE
    ; TODO: every interface version >= 1, bumps only additive
    xor rax, rax
    ret

global cwplint_check_compat
cwplint_check_compat:
    PROLOGUE
    ; TODO: compare against proto/VERSION baseline
    xor rax, rax
    ret

section .rodata
lint_banner: db "cwplint 0.1.0", 10, 0
lint_banner_len: equ $ - lint_banner

section .data
global cwplint_version
cwplint_version: dq 0x010000
