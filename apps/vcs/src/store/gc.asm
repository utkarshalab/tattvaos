; =============================================================================
; File     : src/store/gc.asm
; Project  : Utkarsha VCS (vcs)
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Garbage collection for unreferenced objects.
; =============================================================================

%ifndef VCS_STORE_GC_ASM
%define VCS_STORE_GC_ASM

%include "include/vcs.inc"

bits 64

section .text

; -----------------------------------------------------------------------------
; gc_mark — Mark reachable objects starting from roots
; Input:  rdi = root object hash
; Output: none
; -----------------------------------------------------------------------------
global gc_mark
gc_mark:
    PROLOGUE_SAVE rbx
    ; TODO: traverse object graph, mark reachable
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; gc_sweep — Sweep unmarked objects, free their segments
; Output: rax = number of objects collected
; -----------------------------------------------------------------------------
global gc_sweep
gc_sweep:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

%endif ; VCS_STORE_GC_ASM