; ============================================================================
; Path Tessellation — Bézier Flattening, Path Operations
; ============================================================================

%ifndef __PATH_TESS_INC__
%define __PATH_TESS_INC__

%include "inc/fixed.inc"
%include "inc/geometry.inc"

; Path verb types (from geometry.inc)
; PATH_VERB_MOVE = 0
; PATH_VERB_LINE = 1
; PATH_VERB_QUAD = 2
; PATH_VERB_CUBIC = 3
; PATH_VERB_ARC = 4
; PATH_VERB_CLOSE = 5

; Tessellation parameters
%define TESS_FLATNESS       0.25       ; max deviation in pixels
%define TESS_FLATNESS_FIXED 0x00004000 ; 0.25 in 16.16
%define TESS_MAX_RECURSION  10
%define TESS_MAX_SEGMENTS   256

; Tessellated path output
%define TessPath_VERBS      0
%define TessPath_POINTS     8
%define TessPath_COUNT      16
%define TessPath_CAP        20
%define TessPath_SIZE       24

; Quadratic Bézier flattening (De Casteljau)
; Cubic Bézier flattening (De Casteljau)
; Arc to cubic Bézier conversion

%endif ; __PATH_TESS_INC__