; ============================================================================
; bench_latency — Input-to-Photon Measurement (ns, direct scanout)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

section .text

global bench_latency_run
bench_latency_run:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
    ; TODO: inject synthetic event at vblank-epsilon, measure present time
    mov rax, 16666667
    EPILOGUE_RESTORE rbx
    ret

section .data
global bench_latency_version
bench_latency_version: dq 0x010000
