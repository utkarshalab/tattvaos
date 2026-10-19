; =============================================================================
; File     : src/arch/x86_64/barriers.asm
; Project  : Utkarsha VCS (vcs)
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Memory barriers — load/store/full.
; =============================================================================

%ifndef VCS_ARCH_X86_64_BARRIERS_ASM
%define VCS_ARCH_X86_64_BARRIERS_ASM

%include "include/vcs.inc"

bits 64

section .text

; -----------------------------------------------------------------------------
; barrier_load — Load barrier (LFENCE)
; -----------------------------------------------------------------------------
global barrier_load
barrier_load:
    lfence
    ret

; -----------------------------------------------------------------------------
; barrier_store — Store barrier (SFENCE)
; -----------------------------------------------------------------------------
global barrier_store
barrier_store:
    sfence
    ret

; -----------------------------------------------------------------------------
; barrier_full — Full memory barrier (MFENCE)
; -----------------------------------------------------------------------------
global barrier_full
barrier_full:
    mfence
    ret

%endif ; VCS_ARCH_X86_64_BARRIERS_ASM