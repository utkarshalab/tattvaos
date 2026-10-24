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
%define UgfxState_SIZE          560

; Drawing context (caller-allocated, UgfxContext_SIZE bytes; ugfx_ctx_init)
%define UgfxContext_arena       0
%define UgfxContext_root        8       ; PixBuf* the context draws into
%define UgfxContext_raster      16      ; UgfxRaster
%define UgfxContext_path_a      104     ; scratch UgfxPaths (dashes, strokes, rects)
%define UgfxContext_path_b      160
%define UgfxContext_path_c      216
%define UgfxContext_stack       272     ; UgfxState[UGFX_CTX_MAX_DEPTH]
%define UgfxContext_masks       280     ; UgfxMask[UGFX_CTX_MAX_DEPTH + 2]: per depth + scratch
%define UgfxContext_layers      288     ; PixBuf*[UGFX_CTX_MAX_DEPTH + 1]
%define UgfxContext_depth       296     ; u32 saved states
%define UgfxContext_tmp_paint   304     ; UgfxPaint
%define UgfxContext_tmp_m       464     ; f64[6]
%define UgfxContext_tmp_m2      512     ; f64[6]
%define UgfxContext_state       560     ; UgfxState (the current one)
%define UgfxContext_SIZE        1120
%define UGFX_CTX_MAX_DEPTH      32

; Display list (caller-allocated, UgfxList_SIZE bytes; 2d/list.asm)
%define UgfxList_arena          0
%define UgfxList_data           8       ; records: u32 opcode, u32 bytes, payload (8-aligned)
%define UgfxList_size           16      ; u64 bytes used
%define UgfxList_cap            24      ; u64 bytes allocated
%define UgfxList_error          32      ; i32 sticky recording error
%define UgfxList_count          36      ; u32 records
%define UgfxList_SIZE           40

; Gradient colour stop (UgfxStop_SIZE bytes, an array of them per gradient)
%define UgfxStop_offset         0       ; f64 position, clamped to [0, 1] and to the previous stop
%define UgfxStop_color          8       ; u32 straight (not premultiplied) BGRA, 0xAARRGGBB
%define UgfxStop_SIZE           16

%endif ; __UGFX_INC__
