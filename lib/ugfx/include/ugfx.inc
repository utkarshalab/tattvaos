; =============================================================================
; Utkarsha OS — lib/ugfx/include/ugfx.inc
; =============================================================================
; Public definitions for the ugfx graphics library: calling-convention macros,
; error codes, and the layouts of the objects ugfx functions take and return.
; This header is the single source for these layouts; other libraries include
; it instead of redefining them.
;
; ugfx owns no math: geometry and fixed-point arithmetic belong to lib/umath.
; Memory comes from the caller's arena through `arena_alloc` (rdi = arena,
; rsi = size -> rax = pointer or 0), treated as an opaque handle.
; =============================================================================

%ifndef __UGFX_INC__
%define __UGFX_INC__

; -----------------------------------------------------------------------------
; Calling convention (System V register order, callee-saved rbx/rbp/r12-r15).
; Defined only if the including program has not defined them already.
; -----------------------------------------------------------------------------
%ifnmacro PROLOGUE 0
%macro PROLOGUE 0
    push rbp
    mov  rbp, rsp
%endmacro
%endif

%ifnmacro EPILOGUE 0
%macro EPILOGUE 0
    leave
    ret
%endmacro
%endif

%ifnmacro PROLOGUE_SAVE 1-*
%macro PROLOGUE_SAVE 1-*
    push rbp
    mov  rbp, rsp
    %rep %0
        push %1
        %rotate 1
    %endrep
%endmacro
%endif

%ifnmacro EPILOGUE_RESTORE 1-*
%macro EPILOGUE_RESTORE 1-*
    %rep %0
        %rotate -1
        pop %1
    %endrep
    leave
    ret
%endmacro
%endif

; Debug-build pointer check; the program provides panic_null_ptr.
%ifndef DEBUG_BUILD
    %define DEBUG_BUILD 0
%endif
%ifnmacro ASSERT_PTR 1
%macro ASSERT_PTR 1
    %if DEBUG_BUILD
        test %1, %1
        jnz %%ok
        call panic_null_ptr
    %%ok:
    %endif
%endmacro
%endif
%if DEBUG_BUILD
%ifndef UGFX_PANIC_IMPL                 ; defined by the file that implements it
extern panic_null_ptr
%endif
%endif

; -----------------------------------------------------------------------------
; Error codes (returned negated)
; -----------------------------------------------------------------------------
%ifndef ENOMEM
    %define ENOMEM      12
%endif
%ifndef EINVAL
    %define EINVAL      22
%endif
%ifndef ENOSPC
    %define ENOSPC      28
%endif
%ifndef ENOTSUP
    %define ENOTSUP     95
%endif

; -----------------------------------------------------------------------------
; PixBuf — pixel buffer, 32-bit premultiplied BGRA unless format says otherwise
; -----------------------------------------------------------------------------
%define PixBuf_width        0           ; u64 pixels
%define PixBuf_height       8           ; u64 pixels
%define PixBuf_stride       16          ; u64 bytes per row
%define PixBuf_format       24          ; u64 pixel format code
%define PixBuf_data         32          ; u64 pointer to the first row
%define PixBuf_size         40          ; u64 bytes of pixel data
%define PixBuf_refcount     48          ; u64
%define PixBuf_arena        56          ; u64 arena the buffer came from
%define PixBuf_size_total   64          ; size of the object

; -----------------------------------------------------------------------------
; Rect — half-open integer rectangle [x1, x2) x [y1, y2)
; -----------------------------------------------------------------------------
%define Rect_x1             0           ; i32
%define Rect_y1             4           ; i32
%define Rect_x2             8           ; i32
%define Rect_y2             12          ; i32
%define Rect_size           16

; -----------------------------------------------------------------------------
; Region — set of non-overlapping rectangles
; -----------------------------------------------------------------------------
%define Region.rects        0           ; Rect*
%define Region.count        8           ; u64
%define Region.capacity     16          ; u64
%define Region.arena        24          ; arena for growth
%define Region_SIZE         32

; -----------------------------------------------------------------------------
; Buffer transforms (transform_*)
; -----------------------------------------------------------------------------
%define TRANSFORM_NORMAL    0
%define TRANSFORM_90        1
%define TRANSFORM_180       2
%define TRANSFORM_270       3
%define TRANSFORM_FLIP_H    4
%define TRANSFORM_FLIP_V    8

; -----------------------------------------------------------------------------
; Rasterizer — anti-aliased area coverage (core/raster.asm)
;   Coordinates are 24.8 fixed point in device pixels. Coverage is exact area
;   per pixel, 0..255. Spans go to the span compositor (core/span.asm).
; -----------------------------------------------------------------------------
%define UGFX_SUBPIXEL_SHIFT 8
%define UGFX_SUBPIXEL_SCALE 256
%define UGFX_FILL_NONZERO   0
%define UGFX_FILL_EVENODD   1

; Raster object (caller-allocated, UgfxRaster_SIZE bytes)
%define UgfxRaster_arena    0           ; arena for cell storage
%define UgfxRaster_cells    8           ; cell array: x, y, cover, area (i32 each)
%define UgfxRaster_count    16          ; u32 cells stored
%define UgfxRaster_cap      20          ; u32 cell capacity
%define UgfxRaster_cur_x    24          ; i32 current cell
%define UgfxRaster_cur_y    28
%define UgfxRaster_cover    32          ; i32 current cell accumulators
%define UgfxRaster_area     36
%define UgfxRaster_move_x   40          ; i32 start of the open contour
%define UgfxRaster_move_y   44
%define UgfxRaster_last_x   48          ; i32 current point
%define UgfxRaster_last_y   52
%define UgfxRaster_width    56          ; u32 clip width in pixels
%define UgfxRaster_height   60          ; u32 clip height in pixels
%define UgfxRaster_open     64          ; u32 a contour is open
%define UgfxRaster_error    68          ; u32 sticky -ENOMEM from cell growth
%define UgfxRaster_clip     72          ; const UgfxMask* applied to every fill, or 0
%define UgfxRaster_alpha    80          ; u32 0..255 multiplies every fill's coverage (255 at init)
%define UgfxRaster_SIZE     88

; Coverage mask (caller-allocated, UgfxMask_SIZE bytes; ugfx_mask_init)
%define UgfxMask_width      0           ; u64 pixels
%define UgfxMask_height     8           ; u64 pixels
%define UgfxMask_stride     16          ; u64 bytes per row
%define UgfxMask_data       24          ; u8[] 0 = outside .. 255 = inside
%define UgfxMask_SIZE       32
%define UgfxCell_SIZE       16

; -----------------------------------------------------------------------------
; 2D paths
; -----------------------------------------------------------------------------
%define PATH_MAX_VERBS      2048
%define PATH_MAX_POINTS     (PATH_MAX_VERBS * 4)
%define PATH_VERB_MOVE      0
%define PATH_VERB_LINE      1
%define PATH_VERB_QUAD      2
%define PATH_VERB_CUBIC     3
%define PATH_VERB_ARC       4
%define PATH_VERB_CLOSE     5
%define PATH_VERB_END       255

; Path object (caller-allocated, UgfxPath_SIZE bytes). Verbs are bytes;
; points are f64 (x, y) pairs: MOVE and LINE use one, QUAD two, CUBIC three,
; CLOSE none. Arcs and shapes are stored as cubics.
%define UgfxPath_arena      0
%define UgfxPath_verbs      8           ; u8[]
%define UgfxPath_points     16          ; f64[2][]
%define UgfxPath_verb_count 24          ; u32
%define UgfxPath_verb_cap   28          ; u32
%define UgfxPath_point_count 32         ; u32
%define UgfxPath_point_cap  36          ; u32
%define UgfxPath_start      40          ; u32 point index of the open contour's MOVE
%define UgfxPath_open       44          ; u32 a contour is open
%define UgfxPath_error      48          ; u32 sticky -ENOMEM
%define UgfxPath_SIZE       56

; Default flattening tolerance, in device pixels
%define UGFX_PATH_TOLERANCE 0.1

; Stroke style (caller-filled, UgfxStroke_SIZE bytes)
%define UgfxStroke_width        0       ; f64 > 0, user units
%define UgfxStroke_miter_limit  8       ; f64, ratio of miter length to width (>= 1)
%define UgfxStroke_join         16      ; u32 UGFX_JOIN_*
%define UgfxStroke_cap          20      ; u32 UGFX_CAP_*
%define UgfxStroke_SIZE         24

%define UGFX_JOIN_MITER     0
%define UGFX_JOIN_ROUND     1
%define UGFX_JOIN_BEVEL     2
%define UGFX_CAP_BUTT       0
%define UGFX_CAP_ROUND      1
%define UGFX_CAP_SQUARE     2

; Dash pattern (caller-filled, UgfxDash_SIZE bytes): alternating on and off
; lengths, starting with on; an odd count repeats the list (SVG).
%define UgfxDash_intervals      0       ; const f64*, each >= 0, sum > 0
%define UgfxDash_count          8       ; u32 >= 1
%define UgfxDash_offset         16      ; f64 distance into the pattern at each contour start
%define UgfxDash_SIZE           24

; Paint (caller-allocated, UgfxPaint_SIZE bytes): what a fill puts under its
; coverage. Built by ugfx_paint_solid / _linear / _radial / _conic; the
; transform maps paint space to device space (identity by default).
%define UgfxPaint_span          0       ; span function for ugfx_raster_fill_paint
%define UgfxPaint_type          8       ; u32 UGFX_PAINT_*
%define UgfxPaint_spread        12      ; u32 UGFX_SPREAD_*
%define UgfxPaint_color         16      ; u32 premultiplied BGRA (solid)
%define UgfxPaint_lut           24      ; u32[UGFX_GRADIENT_LUT] premultiplied BGRA
%define UgfxPaint_inverse       32      ; f64[6] device -> paint space
%define UgfxPaint_geom          80      ; f64[8] gradient geometry (see 2d/paint.asm)
%define UgfxPaint_image         144     ; const PixBuf* (image paints)
%define UgfxPaint_filter        152     ; u32 UGFX_FILTER_* (image paints)
%define UgfxPaint_extend_y      156     ; u32 UGFX_SPREAD_* down the image (spread is across)
%define UgfxPaint_SIZE          160

%define UGFX_PAINT_SOLID        0
%define UGFX_PAINT_LINEAR       1
%define UGFX_PAINT_RADIAL       2
%define UGFX_PAINT_CONIC        3
%define UGFX_PAINT_RADIAL2      4       ; two circles (focal, two-point conical)
%define UGFX_PAINT_IMAGE        5       ; image pattern
%define UGFX_SPREAD_PAD         0
%define UGFX_SPREAD_REPEAT      1
%define UGFX_SPREAD_REFLECT     2
%define UGFX_SPREAD_NONE        3       ; images only: transparent outside
%define UGFX_FILTER_NEAREST     0
%define UGFX_FILTER_BILINEAR    1
%define UGFX_GRADIENT_LUT       1024

; Drawing context state (2d/context.asm; saved and restored as a whole)
%define UgfxState_transform     0       ; f64[6] user -> device
%define UgfxState_tolerance     48      ; f64 device pixels
%define UgfxState_clip          56      ; const UgfxMask* or 0
%define UgfxState_clip_owned    64      ; u32 the clip mask belongs to this depth
%define UgfxState_rule          68      ; u32 UGFX_FILL_*
%define UgfxState_alpha         72      ; u32 global alpha 0..255
%define UgfxState_is_layer      76      ; u32 this depth was opened by begin_layer
%define UgfxState_layer_alpha   80      ; u32 the layer's opacity
%define UgfxState_target        88      ; PixBuf* drawn into
%define UgfxState_fill_paint    96      ; UgfxPaint
%define UgfxState_fill_matrix   256     ; f64[6] paint -> user (follows the paint)
%define UgfxState_stroke_paint  304     ; UgfxPaint
%define UgfxState_stroke_matrix 464     ; f64[6]
%define UgfxState_stroke        512     ; UgfxStroke
%define UgfxState_dash          536     ; UgfxDash (intervals 0: no dash)
%define UgfxState_mask          560     ; const UgfxMask* a layer composites through (end_mask)
%define UgfxState_SIZE          568

; Drawing context (caller-allocated, UgfxContext_SIZE bytes; ugfx_ctx_init)
%define UgfxContext_arena       0
%define UgfxContext_root        8       ; PixBuf* the context draws into
%define UgfxContext_raster      16      ; UgfxRaster
%define UgfxContext_path_a      104     ; scratch UgfxPaths (dashes, strokes, rects)
%define UgfxContext_path_b      160
%define UgfxContext_path_c      216
%define UgfxContext_stack       272     ; UgfxState[UGFX_CTX_MAX_DEPTH]
%define UgfxContext_masks       280     ; UgfxMask[UGFX_CTX_MAX_DEPTH + 3]: per depth, scratch, union
%define UgfxContext_layers      288     ; PixBuf*[UGFX_CTX_MAX_DEPTH + 1]
%define UgfxContext_depth       296     ; u32 saved states
%define UgfxContext_tmp_paint   304     ; UgfxPaint
%define UgfxContext_tmp_m       464     ; f64[6]
%define UgfxContext_tmp_m2      512     ; f64[6]
%define UgfxContext_state       560     ; UgfxState (the current one)
%define UgfxContext_union       1128    ; u32 a union clip is being built (clip_begin .. clip_end)
%define UgfxContext_lmasks      1136    ; UgfxMask[UGFX_CTX_MAX_DEPTH + 1]: layer masks, per depth
%define UgfxContext_SIZE        1144
; ugfx_ctx_end_mask modes
%define UGFX_MASK_LUMINANCE     0
%define UGFX_MASK_ALPHA         1
%define UGFX_CTX_MAX_DEPTH      32

; Display list (caller-allocated, UgfxList_SIZE bytes; 2d/list.asm)
%define UgfxList_arena          0
%define UgfxList_data           8       ; records: u32 opcode, u32 bytes, payload (8-aligned)
%define UgfxList_size           16      ; u64 bytes used
%define UgfxList_cap            24      ; u64 bytes allocated
%define UgfxList_error          32      ; i32 sticky recording error
%define UgfxList_count          36      ; u32 records
%define UgfxList_SIZE           40

; UIC icon pack (caller-allocated, UgfxUic_SIZE bytes; 2d/uic.asm, docs/UIC.md)
%define UgfxUic_data            0       ; the pack's bytes (used in place)
%define UgfxUic_size            8       ; u64
%define UgfxUic_count           16      ; u32 icons
%define UgfxUic_index           24      ; 16-byte entries
%define UgfxUic_strings         32
%define UgfxUic_bodies          40
%define UgfxUic_arena           48
%define UgfxUic_path            56      ; UgfxPath used while drawing
%define UgfxUic_SIZE            112

; SVG document (caller-allocated, UgfxSvg_SIZE bytes; 2d/svg.asm)
%define UgfxSvg_arena           0
%define UgfxSvg_items           8       ; UgfxSvgItem[]
%define UgfxSvg_count           16      ; u32
%define UgfxSvg_cap             20      ; u32
%define UgfxSvg_viewbox         24      ; f64 x, y, width, height
%define UgfxSvg_width           56      ; f64 (the root's width attribute)
%define UgfxSvg_height          64
%define UgfxSvg_has             72      ; u32 bit 0 viewBox, 1 width, 2 height
%define UgfxSvg_par             76      ; u32 the root's preserveAspectRatio: align 0 none,
                                        ; 1..9 xMinYMin .. xMaxYMax (x fastest); bit 8 slice
%define UgfxSvg_SIZE            80

%define UgfxSvgItem_matrix      0       ; f64[6] element -> viewBox space
%define UgfxSvgItem_path        48      ; UgfxPath
%define UgfxSvgItem_fill_kind   104     ; u32 0 none, 1 colour, 2 currentColor, 3 paint, 4 pattern
%define UgfxSvgItem_fill        108     ; u32 straight BGRA (alpha with opacities; paints: alpha only)
%define UgfxSvgItem_stroke_kind 112
%define UgfxSvgItem_stroke      116
%define UgfxSvgItem_rule        120     ; u32
%define UgfxSvgItem_join        124
%define UgfxSvgItem_cap         128
%define UgfxSvgItem_width       136     ; f64 stroke width
%define UgfxSvgItem_miter       144
%define UgfxSvgItem_fill_paint  152     ; UgfxPaint* (kind 3), UgfxSvgPattern* (kind 4)
%define UgfxSvgItem_fill_pm     160     ; f64[6] paint -> element space
%define UgfxSvgItem_stroke_paint 208
%define UgfxSvgItem_stroke_pm   216
%define UgfxSvgItem_order       264     ; u32 1: stroke before fill (paint-order)
%define UgfxSvgItem_dash        272     ; const f64* (even count), 0 = solid
%define UgfxSvgItem_dash_n      280     ; u32
%define UgfxSvgItem_dash_off    288     ; f64
%define UgfxSvgItem_kind        296     ; u32 UGFX_SVG_*
%define UgfxSvgItem_alpha       300     ; u32 group opacity 0..255 (UGFX_SVG_BEGIN / END)
%define UgfxSvgItem_clip        304     ; const UgfxSvgClip* (BEGIN / END), 0 = none
%define UgfxSvgItem_bbox        312     ; f64 x0, y0, x1, y1: BEGIN's content in its space,
                                        ; a shape's own bounds when a paint is a pattern
%define UgfxSvgItem_mask        344     ; const UgfxSvgMask* (BEGIN / END), 0 = none
%define UgfxSvgItem_marker      352     ; const UgfxSvgMarker* (UGFX_SVG_MARKER)
%define UgfxSvgItem_SIZE        360
; a clipPath's content, compiled for one element (items are shapes; next:
; the clipPath's own clip-path, intersected)
%define UgfxSvgClip_items       0       ; UgfxSvgItem[]
%define UgfxSvgClip_count       8       ; u32
%define UgfxSvgClip_units       12      ; u32 1 = objectBoundingBox
%define UgfxSvgClip_next        16      ; const UgfxSvgClip*
%define UgfxSvgClip_SIZE        24
; a mask's content, compiled for one element: drawn into a mask layer,
; clipped to the region, as luminance or alpha
%define UgfxSvgMask_items       0       ; UgfxSvgItem[]
%define UgfxSvgMask_count       8       ; u32
%define UgfxSvgMask_units       12      ; u32 maskUnits: 1 = objectBoundingBox (the default)
%define UgfxSvgMask_content     16      ; u32 maskContentUnits: 1 = objectBoundingBox
%define UgfxSvgMask_mode        20      ; u32 UGFX_MASK_LUMINANCE / _ALPHA (mask-type)
%define UgfxSvgMask_region      24      ; f64 x, y, w, h in those units
%define UgfxSvgMask_path        56      ; UgfxPath: the unit square
%define UgfxSvgMask_SIZE        112
; a pattern's tile and content, compiled for one element (href followed)
%define UgfxSvgPattern_items    0       ; UgfxSvgItem[]
%define UgfxSvgPattern_count    8       ; u32
%define UgfxSvgPattern_units    12      ; u32 patternUnits: 1 = objectBoundingBox (the default)
%define UgfxSvgPattern_content  16      ; u32 patternContentUnits: 1 = objectBoundingBox
%define UgfxSvgPattern_has_vb   20      ; u32 a viewBox was given
%define UgfxSvgPattern_rect     24      ; f64 x, y, w, h of the tile, in those units
%define UgfxSvgPattern_matrix   56      ; f64[6] patternTransform
%define UgfxSvgPattern_viewbox  104     ; f64[4]
%define UgfxSvgPattern_par      136     ; u32 preserveAspectRatio
%define UgfxSvgPattern_given    140     ; u32 attributes given (href inherits the rest)
%define UgfxSvgPattern_path     144     ; UgfxPath: the unit square
%define UgfxSvgPattern_SIZE     200
; a marker's content, compiled for one shape
%define UgfxSvgMarker_items     0       ; UgfxSvgItem[]
%define UgfxSvgMarker_count     8       ; u32
%define UgfxSvgMarker_units     12      ; u32 markerUnits: 1 = userSpaceOnUse, 0 = strokeWidth
%define UgfxSvgMarker_orient    16      ; u32 0 an angle, 1 auto, 2 auto-start-reverse
%define UgfxSvgMarker_clip      20      ; u32 overflow hidden (the default)
%define UgfxSvgMarker_angle     24      ; f64 radians (orient as an angle)
%define UgfxSvgMarker_ref       32      ; f64 x, y: refX / refY through the viewBox
%define UgfxSvgMarker_size      48      ; f64 markerWidth, markerHeight
%define UgfxSvgMarker_vbm       64      ; f64[6] viewBox -> marker viewport (identity without)
%define UgfxSvgMarker_has_vb    112     ; u32
%define UgfxSvgMarker_path      120     ; UgfxPath: the unit square
%define UgfxSvgMarker_SIZE      176
; item kinds: a shape, or the start / end of a group drawn as one layer
%define UGFX_SVG_SHAPE          0
%define UGFX_SVG_BEGIN          1
%define UGFX_SVG_END            2
%define UGFX_SVG_MARKER         3       ; a marker's content at matrix (marker space -> doc)

; SVG reading state (2d/svg_xml.asm)
%define UgfxSvgXml_cur          0       ; next byte to read
%define UgfxSvgXml_end          8
%define UgfxSvgXml_name         16      ; the tag's name
%define UgfxSvgXml_name_end     24
%define UgfxSvgXml_attrs        32      ; start tags: attributes from here ...
%define UgfxSvgXml_tag_end      40      ; ... to here ('>' or the '/' of '/>')
%define UgfxSvgXml_self         48      ; u32 self-closing
%define UgfxSvgXml_SIZE         56
%define UgfxSvgAttr_cur         0       ; 0 = the first attribute
%define UgfxSvgAttr_name        8
%define UgfxSvgAttr_name_end    16
%define UgfxSvgAttr_val         24
%define UgfxSvgAttr_val_end     32
%define UgfxSvgAttr_SIZE        40

; SVG definitions gathered before drawing (2d/svg_defs.asm)
%define UgfxSvgDefs_arena       0
%define UgfxSvgDefs_grads       8       ; gradient records
%define UgfxSvgDefs_count       16      ; u32
%define UgfxSvgDefs_cap         20      ; u32
%define UgfxSvgDefs_rules       24      ; CSS rules from <style>, in cascade order
%define UgfxSvgDefs_nrules      32      ; u32
%define UgfxSvgDefs_rulecap     36      ; u32
%define UgfxSvgDefs_ids         40      ; (id, id end, tag start) of every element with an id
%define UgfxSvgDefs_nids        48      ; u32
%define UgfxSvgDefs_idcap       52      ; u32
%define UgfxSvgDefs_SIZE        56

; An element as CSS selectors see it (2d/svg_defs.asm, ugfx_svg_defs_rule)
%define UgfxSvgSel_name         0       ; element name
%define UgfxSvgSel_name_end     8
%define UgfxSvgSel_id           16      ; its id attribute (0 = none)
%define UgfxSvgSel_id_end       24
%define UgfxSvgSel_class        32      ; its class attribute (0 = none)
%define UgfxSvgSel_class_end    40
%define UgfxSvgSel_SIZE         48

; Gradient colour stop (UgfxStop_SIZE bytes, an array of them per gradient)
%define UgfxStop_offset         0       ; f64 position, clamped to [0, 1] and to the previous stop
%define UgfxStop_color          8       ; u32 straight (not premultiplied) BGRA, 0xAARRGGBB
%define UgfxStop_SIZE           16

%endif ; __UGFX_INC__
