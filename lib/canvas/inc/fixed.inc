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

; The functions are in src/core/fixed.asm, once
%ifndef FIXED_IMPL
extern fix_sqrt
extern fixed_pow
extern fixed_cos
extern fixed_sin
%endif

%endif ; __FIXED_INC__
