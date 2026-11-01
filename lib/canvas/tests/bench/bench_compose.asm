; ============================================================================
; Benchmark — Compose Performance
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/test.inc"
%include "inc/externs.inc"

section .text

; ============================================================================
; bench_compose_main
; ============================================================================
global bench_compose_main
bench_compose_main:
    xor eax, eax
    ret

section .data
global bench_compose_version
bench_compose_version: dq 0x010000