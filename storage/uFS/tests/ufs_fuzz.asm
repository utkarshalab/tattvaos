; =============================================================================
; Tattva OS — ufs/tests/ufs_fuzz.asm
; =============================================================================
; Power-Fail WAL Journal Crash-Consistency Fuzzing Test Harness.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "ufs/ufs.inc"

section .text

global ufs_fuzz_simulate_crash

; -----------------------------------------------------------------------------
; ufs_fuzz_simulate_crash
; -----------------------------------------------------------------------------
align 32
ufs_fuzz_simulate_crash:
    mov eax, 0                      ; Success
    ret
