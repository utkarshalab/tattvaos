; ============================================================================
; bench_idle — Idle Wakeup Measurement
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

section .text

global bench_idle_run
bench_idle_run:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ; TODO: arm waitset with 100ms deadline, count wakeups
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

section .data
global bench_idle_version
bench_idle_version: dq 0x010000
