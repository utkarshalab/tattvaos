; =============================================================================
; lib/io/arch/x86_64/barrier.asm
; Architecture-specific memory barrier wrappers for x86_64.
;
; Defines read, write, and full fence instructions to abstract pipeline
; ordering boundaries from system driver modules.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_ARCH_X86_64_BARRIER_ASM
%define IO_ARCH_X86_64_BARRIER_ASM

%include "lib/io/macro/func.asm"

section .text

global io_wmb
global io_rmb
global io_mb

; =============================================================================
; io_wmb — Write Memory Barrier (sfence)
; Enforces ordering of store instructions.
; =============================================================================
IO_FUNC io_wmb
    sfence
IO_ENDFUNC io_wmb

; =============================================================================
; io_rmb — Read Memory Barrier (lfence)
; Enforces ordering of load instructions.
; =============================================================================
IO_FUNC io_rmb
    lfence
IO_ENDFUNC io_rmb

; =============================================================================
; io_mb — Full Memory Barrier (mfence)
; Enforces ordering of both store and load instructions.
; =============================================================================
IO_FUNC io_mb
    mfence
IO_ENDFUNC io_mb

%endif ; IO_ARCH_X86_64_BARRIER_ASM
