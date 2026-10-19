; ============================================================================
; Stroke Definitions — Caps, Joins, Dashes
; ============================================================================

%ifndef __STROKES_INC__
%define __STROKES_INC__

%include "inc/fixed.inc"

; Cap styles
%define CAP_BUTT            0
%define CAP_ROUND           1
%define CAP_SQUARE          2

; Join styles
%define JOIN_MITER          0
%define JOIN_ROUND          1
%define JOIN_BEVEL          2

; Dash pattern
%define DashArray_OFFSET    0       ; pointer to float array
%define DashArray_COUNT     8       ; number of elements
%define DashArray_PHASE     12      ; phase offset (fixed-point)
%define DashArray_SIZE      16

; Stroke style
%define Stroke_WIDTH        0       ; line width (fixed-point)
%define Stroke_CAP          4       ; cap style
%define Stroke_JOIN         8       ; join style
%define Stroke_MITER_LIMIT  12      ; miter limit (fixed-point)
%define Stroke_DASH         16      ; DashArray
%define Stroke_DASH_ENABLED 24      ; boolean
%define Stroke_SIZE         28

; Stroke context (for path stroking)
%define StrCtx_PATH         0
%define StrCtx_STYLE        8
%define StrCtx_MATRIX       16      ; 3x3 transform
%define StrCtx_FLATNESS     52      ; curve flatness
%define StrCtx_SIZE         56

%endif ; __STROKES_INC__