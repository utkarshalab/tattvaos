; ============================================================================
; Fixed-Point Math Definitions — Q16.16 Format
; ============================================================================

%ifndef __FIXED_INC__
%define __FIXED_INC__

%define FIX_SHIFT    16
%define FIX_ONE      (1 << FIX_SHIFT)
%define FIX_HALF     (FIX_ONE >> 1)
%define FIX_MASK     (FIX_ONE - 1)

; Convert integer constant to fixed (assembly-time)
%define FIX(x) ((x) << FIX_SHIFT)

%endif ; __FIXED_INC__
