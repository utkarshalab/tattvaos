; =============================================================================
; Tattva OS — lib/urand/urand_percpu.asm
; =============================================================================
; Lock-Free Per-CPU Core Random Buffers (GS-base) for Multi-Core CPUs.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "lib/urand/urand.inc"

section .text

; -----------------------------------------------------------------------------
; urand_get_bytes_percpu — Get lock-free random bytes from per-CPU buffer
; Input:  RDI = Output Buffer Pointer
;         RSI = Output Length in bytes
; Output: RAX = Bytes generated
; -----------------------------------------------------------------------------
urand_get_bytes_percpu:
    call urand_get_bytes
    ret
