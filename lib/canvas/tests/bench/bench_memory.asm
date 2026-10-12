; ============================================================================
; bench_memory — Resident KB (server arenas + buffers)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

section .text

global bench_memory_run
bench_memory_run:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
    xor eax, eax
    ret

section .data
global bench_memory_version
bench_memory_version: dq 0x010000
