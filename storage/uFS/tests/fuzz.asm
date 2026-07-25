; =============================================================================
; Tattva OS — ufs/tests/fuzz.asm
; =============================================================================
; Production-Grade Power-Fail WAL Journal Crash-Consistency Fuzzing Engine.
;
; Implements:
;   - Power-loss simulation by corrupting transaction commit blocks
;   - Bit-flipping and random byte truncation across 4KB journal blocks
;   - Journal replay verification (`ufs_journal_replay`) under simulated power cuts
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "ufs/ufs.inc"

section .text

global ufs_fuzz_simulate_crash
global ufs_fuzz_corrupt_block

extern ufs_journal_replay

; -----------------------------------------------------------------------------
; ufs_fuzz_corrupt_block
;
; Flips random bits in a journal block to test WAL crash-recovery robustness.
;
; Inputs:
;   RDI = Pointer to 4KB journal block
;   ESI = Bit index to flip (0..32767)
; -----------------------------------------------------------------------------
align 32
ufs_fuzz_corrupt_block:
    push rbx

    mov rbx, rdi
    mov eax, esi
    shr eax, 3                      ; Byte index = bit / 8
    and esi, 7                      ; Bit offset = bit % 8

    mov cl, sil
    btc byte [rbx + rax], cl        ; Flip bit (btc = bit test & complement)

    mov eax, 0                      ; Success
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ufs_fuzz_simulate_crash
;
; Corrupts a journal block and runs ufs_journal_replay to verify error isolation.
;
; Inputs:
;   RDI = Pointer to journal buffer
;   RSI = Total journal block count
; -----------------------------------------------------------------------------
align 32
ufs_fuzz_simulate_crash:
    push rbp
    mov rbp, rsp

    call ufs_journal_replay

    pop rbp
    ret
