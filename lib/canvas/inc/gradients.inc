; ============================================================================
; Gradient Definitions — Linear, Radial, Conical Gradients
; ============================================================================

%ifndef __GRADIENTS_INC__
%define __GRADIENTS_INC__

%include "inc/fixed.inc"

; Gradient types
%define GRADIENT_LINEAR     0
%define GRADIENT_RADIAL     1
%define GRADIENT_CONICAL    2

; Spread methods
%define SPREAD_PAD          0
%define SPREAD_REPEAT       1
%define SPREAD_REFLECT      2

; Color stop
%define ColorStop_OFFSET    0       ; offset (fixed-point 0.0-1.0)
%define ColorStop_COLOR     4       ; color (ARGB)
%define ColorStop_SIZE      8

; Gradient struct
%define Gradient_TYPE       0
%define Gradient_SPREAD     4
%define Gradient_X0         8       ; x0 (fixed-point)
%define Gradient_Y0         12      ; y0 (fixed-point)
%define Gradient_X1         16      ; x1 (fixed-point)
%define Gradient_Y1         20      ; y1 (fixed-point)
%define Gradient_R0         24      ; r0 (fixed-point) - for radial
%define Gradient_R1         28      ; r1 (fixed-point) - for radial
%define Gradient_CX         32      ; center x (fixed-point) - for conical
%define Gradient_CY         36      ; center y (fixed-point) - for conical
%define Gradient_ANGLE      40      ; start angle (fixed-point radians)
%define Gradient_STOPS      44      ; pointer to ColorStop array
%define Gradient_STOP_COUNT 48      ; number of stops
%define Gradient_STOP_CAP   52      ; capacity
%define Gradient_MATRIX     56      ; 3x3 transform matrix (9 * 4 bytes)
%define Gradient_SIZE       92

; Gradient cache entry (for GPU)
%define GradCache_GRADIENT  0
%define GradCache_TEXTURE   8
%define GradCache_DIRTY     16
%define GradCache_SIZE      24

%endif ; __GRADIENTS_INC__