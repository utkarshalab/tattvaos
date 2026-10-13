; ============================================================================
; bench_compose — ns/Frame for the Current Scene
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

section .text

global bench_compose_run
bench_compose_run:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    ASSERT_PTR rbx
    call tv_time_now_ns
    mov r12, rax
    mov rdi, rbx
    call compositor_composite
    call tv_time_now_ns
    sub rax, r12
    EPILOGUE_RESTORE rbx, r12
    ret

section .data
global bench_compose_version
bench_compose_version: dq 0x010000
