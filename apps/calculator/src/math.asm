; Reuse umath, built as one unit so its guarded transitive includes are shared.
bits 64
default rel
%include "lib/umath/math_fn/sqrt_f64.asm"
%include "lib/umath/math_fn/cbrt_f64.asm"
%include "lib/umath/math_fn/tan_f64.asm"
%include "lib/umath/math_fn/asin_f64.asm"
%include "lib/umath/math_fn/acos_f64.asm"
%include "lib/umath/math_fn/log10_f64.asm"
%include "lib/umath/math_fn/log2_f64.asm"
%include "lib/umath/math_fn/pow_f64.asm"
%include "lib/umath/math_fn/hypot_f64.asm"
%include "lib/umath/math_fn/atan2_f64.asm"
%include "lib/umath/scalar/floor_f64.asm"
%include "lib/umath/scalar/ceil_f64.asm"
%include "lib/umath/scalar/round_f64.asm"
%include "lib/umath/scalar/trunc_f64.asm"
section .note.GNU-stack noalloc noexec nowrite progbits
