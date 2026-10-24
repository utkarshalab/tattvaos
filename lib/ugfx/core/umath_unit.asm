; =============================================================================
; Utkarsha OS — lib/ugfx/core/umath_unit.asm
; =============================================================================
; The lib/umath code ugfx calls, as one object. umath files %include what they
; depend on behind guards, so they are assembled together (assemble with the
; repo root on the include path); separate objects would duplicate shared
; functions such as umath_sin_f64.
; =============================================================================

%include "lib/umath/geom/affine2.asm"
%include "lib/umath/geom/bezier.asm"
%include "lib/umath/geom/arc.asm"
