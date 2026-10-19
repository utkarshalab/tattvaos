; ============================================================================
; Geometric Primitives — Core 2D Primitives
; Line, Rectangle, Rounded Rect, Ellipse, Arc, Polygon, Triangle, Path
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/struct_offsets.inc"
%include "inc/fixed.inc"

%ifndef __GEOMETRY_INC__
%define __GEOMETRY_INC__

; ============================================================================
; Constants
; ============================================================================
%define GEOM_EPSILON        0x00010000        ; 1/65536 in fixed-point
%define GEOM_MAX_POINTS     1024
%define PATH_MAX_VERBS      2048
%define PATH_MAX_POINTS     (PATH_MAX_VERBS * 4)

; Path verb types
%define PATH_VERB_MOVE      0
%define PATH_VERB_LINE      1
%define PATH_VERB_QUAD      2
%define PATH_VERB_CUBIC     3
%define PATH_VERB_ARC       4
%define PATH_VERB_CLOSE     5
%define PATH_VERB_END       255

; Cap styles
%define CAP_BUTT            0
%define CAP_ROUND           1
%define CAP_SQUARE          2

; Join styles
%define JOIN_MITER          0
%define JOIN_ROUND          1
%define JOIN_BEVEL          2

; Fill rules
%define FILL_WINDING        0
%define FILL_EVEN_ODD       1

; Path struct offsets
%define Path_VERBS          0
%define Path_POINTS         8
%define Path_COUNT          16
%define Path_POINT_COUNT    24
%define Path_CAP            32
%define Path_ARENA          40
%define Path_SIZE           48

; Tessellated path struct
%define TessPath_VERBS      0
%define TessPath_POINTS     8
%define TessPath_COUNT      16
%define TessPath_CAP        20
%define TessPath_SIZE       24

; Glyph outline struct
%define GlyphOut_VERBS      0
%define GlyphOut_COORDS     8
%define GlyphOut_COUNT      16
%define GlyphOut_CAP        20
%define GlyphOut_XMIN       24
%define GlyphOut_YMIN       28
%define GlyphOut_XMAX       32
%define GlyphOut_YMAX       36
%define GlyphOut_SIZE       40

; Rect struct
%define Rect_x              0
%define Rect_y              4
%define Rect_width          8
%define Rect_height         12
%define Rect_SIZE           16

%endif ; __GEOMETRY_INC__
