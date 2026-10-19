; =============================================================================
; File     : src/core/time.asm
; Project  : Utkarsha VCS (vcs)
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Time primitives — monotonic clock, TSC.
; =============================================================================

%ifndef VCS_CORE_TIME_ASM
%define VCS_CORE_TIME_ASM

%include "include/vcs.inc"

bits 64

section .text

; -----------------------------------------------------------------------------
; time_monotonic — Read monotonic clock (nanoseconds)
; Output: rax = nanoseconds since boot
; -----------------------------------------------------------------------------
global time_monotonic
time_monotonic:
    PROLOGUE_SAVE rbx
    ; TODO: read TSC or kernel monotonic source
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; time_wallclock — Read wall-clock time (nanoseconds since epoch)
; Output: rax = nanoseconds
; -----------------------------------------------------------------------------
global time_wallclock
time_wallclock:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

%endif ; VCS_CORE_TIME_ASM