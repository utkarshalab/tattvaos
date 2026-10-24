; =============================================================================
; Utkarsha OS — kernel/exec/exec.asm
; =============================================================================
; Running programs: the UBF loader, the kernel's exports to programs, and
; the loader's boot self-test. One include for kernel/entry.asm.
; =============================================================================

%ifndef KERNEL_EXEC_EXEC_ASM
%define KERNEL_EXEC_EXEC_ASM

%include "kernel/exec/ubf.inc"
%include "kernel/exec/exports.asm"
%include "kernel/exec/ubf_load.asm"
%include "kernel/exec/selftest.asm"

%endif ; KERNEL_EXEC_EXEC_ASM
