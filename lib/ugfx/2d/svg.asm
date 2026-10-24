; =============================================================================
; Utkarsha OS — lib/ugfx/2d/svg.asm
; =============================================================================
; SVG documents: parsed once into a flat list of drawing items, drawn any
; number of times through a context.
;
;   ugfx_svg_parse(svg, arena, data, size)
;   ugfx_svg_parse_ex(svg, arena, data, size, image_fn, user)
;   ugfx_svg_draw(svg, ctx, current_colour, x, y, size)
;
; The subset is what icon sets use: svg, g, path, rect (rx / ry), circle,
; ellipse, line, polyline, polygon; the presentation attributes, CSS rules
; from <style> (2d/svg_defs.asm) and style declarations - in that order of
; precedence, !important not distinguished - for fill, stroke,
; stroke-width, stroke-linecap, stroke-linejoin, stroke-miterlimit,
; fill-rule, fill-opacity, stroke-opacity, opacity and display; and the
; transform attribute. defs, clipPath, mask, symbol,
; gradients, patterns, markers, text, style, script, title, desc, metadata
; and foreignObject are skipped with everything inside them; other
; elements act as groups. Comments, processing instructions, DOCTYPE and
; CDATA are skipped.
;
; Viewports: the root, a nested svg (x, y, width, height, default 100%)
; and a symbol instanced by use map their viewBox into their size with
; preserveAspectRatio (align or none, meet or slice). Conditional
; processing: requiredExtensions is never met (none are supported),
; systemLanguage matches "en" and "en-*", requiredFeatures is ignored;
; switch draws only its first child element that passes (descriptive
; and definition elements take no part).
;
; Each item keeps the element's transform (user space -> viewBox space),
; its path, and fill / stroke as none, a colour or currentColor, with the
; alpha already multiplied by fill-opacity / stroke-opacity and baked
; opacities. Opacity below 1 on a container (g, svg, use, switch, ...),
; or on a shape with both a fill and a stroke, makes a group: BEGIN and
; END items around its content, drawn as one context layer at that
; alpha; on a shape with one paint it is baked into that paint.
;
; clip-path="url(#id)" on a container or a shape compiles that clipPath's
; content (its shapes and uses, with their transforms and clip-rule;
; display none and visibility hidden left out) for the element, and a
; group clips to their union (ugfx_ctx_clip_begin .. _end), in the
; element's user space or, for clipPathUnits="objectBoundingBox", its
; bounding box (the union of its shapes' bounds, corners transformed). A
; clip-path on the clipPath element intersects; up to 4 nest.
;
; mask="url(#id)" compiles that mask's content (everything that draws)
; the same way; the group draws into a layer, the mask's content into a
; mask layer (its region - x, y, width, height, -10% / 120% by default -
; in maskUnits, objectBoundingBox by default; the content in
; maskContentUnits), and the layer is composited through its luminance,
; or its alpha for mask-type="alpha".
;
; fill / stroke "url(#id)" naming a pattern compiles it too (its href
; chain supplies attributes and content it lacks): the shape is clipped
; to its fill (or stroke outline) and the pattern's content drawn once
; per tile that covers it - tile x, y, width, height in patternUnits
; (objectBoundingBox by default), patternTransform, the content in
; patternContentUnits or fitted by viewBox / preserveAspectRatio, each
; tile clipped to itself; at most 4096 tiles, else nothing.
;
; marker-start / -mid / -end (and the marker shorthand) on path, line,
; polyline and polygon put a compiled marker at each vertex: the first,
; the last, the others. Its direction is the bisector of the incoming and
; outgoing tangents (one of them at an open end; a closed subpath's start
; takes the closing segment's), orient auto / auto-start-reverse / an
; angle; markerUnits strokeWidth scales by stroke-width; refX / refY
; (through the viewBox) sit on the vertex; the content is clipped to
; markerWidth x markerHeight unless overflow is visible or auto. Markers
; draw after the shape, inside its group, even when it has no paint.
;
; image: with ugfx_svg_parse_ex's image_fn, a data: URI (base64 or
; percent-encoded) is decoded and its bytes handed over (kind 0), any
; other href as it is (kind 1); the PixBuf it returns is placed in x, y,
; width, height (default: its own size) by preserveAspectRatio, clipped
; to that box for slice, at the element's opacity (a group, like a
; container's). Without image_fn images are left out.
;
; A nested svg and an instanced symbol clip to their viewport (overflow
; hidden); the root only with slice, the one mapping that overflows by
; itself (its viewport, in viewBox units, is a group's rect clip). Drawing maps the document into the square (x, y, size, size): its
; viewBox through preserveAspectRatio into width x height when both are
; given, that box centred in the square; with only a viewBox, the viewBox
; straight into the square; with none, (0, 0, width or 300, height or
; 150) centred in it.
; =============================================================================

%include "ugfx.inc"

extern arena_alloc
extern ugfx_svg_xml_next
extern ugfx_svg_xml_attr
extern ugfx_svg_lookup
extern ugfx_svg_trim
extern ugfx_svg_defs_scan
extern ugfx_svg_defs_paint
extern ugfx_svg_defs_rule
extern ugfx_svg_defs_id
extern umath_affine2_multiply
extern umath_affine2_translate
extern umath_affine2_invert
extern umath_affine2_rotate
extern umath_affine2_scale
extern umath_atan2_f64
extern ugfx_path_bounds_tight
extern ugfx_ctx_set_transform
extern ugfx_ctx_clip_begin
extern ugfx_ctx_clip_add
extern ugfx_ctx_clip_end
extern ugfx_ctx_clip
extern ugfx_ctx_clip_stroke
extern ugfx_ctx_begin_mask
extern ugfx_ctx_end_mask
extern ugfx_ctx_set_fill_paint
extern ugfx_ctx_set_stroke_paint
extern ugfx_ctx_set_alpha
extern ugfx_path_init
extern ugfx_path_move_to
extern ugfx_path_line_to
extern ugfx_path_cubic_to
extern ugfx_path_close
extern ugfx_path_add_rect
extern ugfx_path_add_circle
extern ugfx_path_add_ellipse
extern ugfx_svg_number
extern ugfx_svg_colour
extern ugfx_svg_transform
extern ugfx_svg_path_data
extern ugfx_svg_points
extern umath_affine2_identity
extern umath_arc_to_cubics
extern ugfx_ctx_save
extern ugfx_ctx_restore
extern ugfx_ctx_translate
extern ugfx_ctx_scale
extern ugfx_ctx_transform
extern ugfx_ctx_set_fill_color
extern ugfx_ctx_set_stroke_color
extern ugfx_ctx_set_fill_rule
extern ugfx_ctx_set_stroke_style
extern ugfx_ctx_set_dash
extern ugfx_ctx_fill
extern ugfx_ctx_stroke
extern ugfx_ctx_begin_layer
extern ugfx_ctx_end_layer
extern ugfx_ctx_draw_image

%define SVG_MAX_DEPTH   64

; inherited state, one per open element
%define S_M             0               ; f64[6]
%define S_FILL_KIND     48              ; u32 0 none, 1 colour, 2 currentColor
%define S_FILL          52              ; u32 straight BGRA
%define S_STROKE_KIND   56
%define S_STROKE        60
%define S_FILL_OP       64              ; f64
%define S_STROKE_OP     72
%define S_OP            80              ; f64 product of opacity up the tree
%define S_SW            88              ; f64 stroke width
%define S_MITER         96
%define S_JOIN          104             ; u32
%define S_CAP           108
%define S_RULE          112
%define S_SKIP          116             ; u32 not drawn (display none, skipped subtree)
%define S_FILL_ID       120             ; url(#id) of a kind 3 fill
%define S_FILL_ID_END   128
%define S_STROKE_ID     136
%define S_STROKE_ID_END 144
%define S_FILL_FB       152             ; u32 the fallback's kind (its colour in S_FILL)
%define S_STROKE_FB     156
%define S_FONT          160             ; f64 font-size (user units) for em / ex
%define S_VW            168             ; f64 the viewport, for percentages
%define S_VH            176
%define S_COLOR_SET     184             ; u32 the color property was given
%define S_COLOR         188             ; u32 straight BGRA, for currentColor
%define S_HIDDEN        192             ; u32 visibility hidden / collapse
%define S_ORDER         196             ; u32 1: stroke before fill
%define S_DASH          200             ; f64* (even count) or 0
%define S_DASH_N        208             ; u32, 0 = solid
%define S_DASH_OFF      216             ; f64
%define S_SWITCH        224             ; u32 1: a switch still choosing, 2: it chose
%define S_GROUP         228             ; u32 the BEGIN it opened + 1 (not inherited)
%define S_CLIPRULE      232             ; u32 clip-rule
%define S_VPGROUP       236             ; u32 the viewport clip's BEGIN + 1 (not inherited)
%define S_MARKERS       240             ; (url, end)[3]: marker-start, -mid, -end (0: none)
%define S_SIZE          288

; elements
%define E_GROUP         0
%define E_SVG           1
%define E_PATH          2
%define E_RECT          3
%define E_CIRCLE        4
%define E_ELLIPSE       5
%define E_LINE          6
%define E_POLYLINE      7
%define E_POLYGON       8
%define E_SKIP          9
%define E_USE           10
%define E_SYMBOL        11              ; drawn only as a <use> instance
%define E_SWITCH        12
%define E_TEXT          13              ; not drawn yet, but takes part in switch
%define E_FOREIGN       14              ; foreignObject: the same
%define E_CLIPPATH      15              ; drawn only as a clip's content
%define E_MASK          16              ; drawn only as a mask's content
%define E_PATTERN       17              ; drawn only as a pattern's tiles
%define E_MARKER        18              ; drawn only at a shape's vertices
%define E_IMAGE         19
%define SVG_MAX_CLIPS   4               ; clipPaths / masks compiling inside each other
%define K_CLIP          2               ; compile kinds (and P_INST for their roots)
%define K_MASK          3
%define K_PATTERN       4
%define K_MARKER        5
%define SVG_MAX_TILES   4096
%define SVG_MAX_USES    8               ; <use> instances inside instances

; geometry slots (f64), with a bit each in P_HAVE
%define G_X             0
%define G_Y             1
%define G_W             2
%define G_H             3
%define G_RX            4
%define G_RY            5
%define G_CX            6
%define G_CY            7
%define G_R             8
%define G_X1            9
%define G_Y1            10
%define G_X2            11
%define G_Y2            12
%define G_COUNT         13

; attribute / property ids
%define A_FILL          1
%define A_STROKE        2
%define A_SW            3
%define A_CAP           4
%define A_JOIN          5
%define A_MITER         6
%define A_RULE          7
%define A_FILL_OP       8
%define A_STROKE_OP     9
%define A_OPACITY       10
%define A_DISPLAY       11
%define A_FONT_SIZE     12
%define A_COLOR         13
%define A_VISIBILITY    14
%define A_DASHARRAY     15
%define A_DASHOFFSET    16
%define A_PAINT_ORDER   17
%define A_CLIP_PATH     18
%define A_CLIP_RULE     19
%define A_MASK          20
%define A_MARKER_START  21
%define A_MARKER_MID    22
%define A_MARKER_END    23
%define A_MARKER        24              ; all three
%define A_LAST_PROP     24              ; ids up to here are style properties too
%define A_TRANSFORM     40
%define A_STYLE         41
%define A_D             42
%define A_POINTS        43
%define A_VIEWBOX       44
%define A_ID            45
%define A_CLASS         46
%define A_HREF          47
%define A_PAR           48              ; preserveAspectRatio
%define A_GEOM          64              ; + G_* slot

; lengths: what a percentage is of
%define AX_X            0               ; the viewport width
%define AX_Y            1               ; its height
%define AX_D            2               ; its normalised diagonal, sqrt((w^2 + h^2) / 2)
%define AX_FONT         3               ; the parent's font-size

; parser frame (r15)
%define P_SVG           0
%define P_STACK         24
%define P_DEPTH         32              ; u32
%define P_ELEM          36              ; u32
%define P_TAGEND        40              ; the tag's '>' (or '/' of '/>')
%define P_SELF          48              ; u32 self-closing
%define P_ROOT          52              ; u32 the root svg was seen
%define P_HAVE          56              ; u32 geometry bits
%define P_ERR           60              ; i32
%define P_G             64              ; f64[G_COUNT]
%define P_D             168             ; path data / points / viewBox / style ranges
%define P_D_END         176
%define P_STYLE         184
%define P_STYLE_END     192
%define P_VB            200
%define P_VB_END        208
%define P_OPACITY       216             ; f64 the element's own opacity
%define P_ARC           256             ; f64[24]
%define P_XML           456             ; UgfxSvgXml
%define P_ATTR          (P_XML + UgfxSvgXml_SIZE)       ; UgfxSvgAttr
%define P_DEFS          (P_ATTR + UgfxSvgAttr_SIZE)     ; UgfxSvgDefs
%define P_VIEW          (P_DEFS + UgfxSvgDefs_SIZE)     ; f64 viewport w, h
%define P_SEL           (P_VIEW + 16)                   ; UgfxSvgSel: the element for CSS
%define P_HREF          (P_SEL + UgfxSvgSel_SIZE)       ; <use>: the id named
%define P_HREF_END      (P_HREF + 8)
%define P_USE_W         (P_HREF + 16)                   ; <use> width, height for a symbol
%define P_USE_H         (P_HREF + 24)
%define P_USES          (P_HREF + 32)                   ; u32 instances open
%define P_INST          (P_HREF + 36)                   ; u32 the next start tag is an instance's root
%define P_SYMROOT       (P_HREF + 40)                   ; u32 this element is an instanced symbol
%define P_USE_HAVE      (P_HREF + 44)                   ; u32 width and height given
%define P_GV            (P_HREF + 48)                   ; geometry values as written: (p, end)[G_COUNT]
%define P_GRAW          (P_GV + G_COUNT * 16)           ; u32 bits: P_GV slots given
%define P_FONT_RAW      (P_GRAW + 8)                    ; font-size as written (0: none)
%define P_FONT_RAW_END  (P_FONT_RAW + 8)
%define P_SW_RAW        (P_FONT_RAW + 16)               ; stroke-width as written
%define P_SW_RAW_END    (P_FONT_RAW + 24)
%define P_DASH_RAW      (P_FONT_RAW + 32)               ; stroke-dasharray as written
%define P_DASH_RAW_END  (P_FONT_RAW + 40)
%define P_DOFF_RAW      (P_FONT_RAW + 48)               ; stroke-dashoffset as written
%define P_DOFF_RAW_END  (P_FONT_RAW + 56)
%define P_PAR           (P_FONT_RAW + 64)               ; u32 preserveAspectRatio (as UgfxSvg_par)
%define P_CLIPMODE      (P_FONT_RAW + 68)               ; u32 clipPaths being compiled
%define P_CLIP          (P_FONT_RAW + 72)               ; clip-path as written (0: none)
%define P_CLIP_END      (P_FONT_RAW + 80)
%define P_CLIPREC       (P_FONT_RAW + 88)               ; the compiled clip for a group
%define P_MASK          (P_FONT_RAW + 96)               ; mask as written (0: none)
%define P_MASK_END      (P_FONT_RAW + 104)
%define P_MASKREC       (P_FONT_RAW + 112)              ; the compiled mask for a group
%define P_COMPILE       (P_FONT_RAW + 120)              ; u32 clipPaths / masks being compiled
%define P_CROOT         (P_FONT_RAW + 124)              ; u32 this element is a compile's root
%define P_VERTS         (P_FONT_RAW + 128)              ; a shape's vertices (V_*), for markers
%define P_NVERTS        (P_FONT_RAW + 136)              ; u32
%define P_HREF_RAW      (P_FONT_RAW + 144)              ; an href as written, trimmed (0: none)
%define P_HREF_RAW_END  (P_FONT_RAW + 152)
%define P_SIZE          (((P_FONT_RAW + 160 + 15) & ~15) + 8)

; a vertex, for markers
%define VX_X            0               ; f64
%define VX_Y            8
%define VX_IN           16              ; f64 incoming direction (radians)
%define VX_OUT          24              ; outgoing
%define VX_FLAGS        32              ; u32 1 has in, 2 has out
%define VX_SIZE         40

%define PAR_DEFAULT     5               ; xMidYMid meet

; svg_compile's frame (svg_pattern_attrs reads its tag through it)
%define CC_FRAME    0                               ; the frame, P_SIZE bytes
%define CC_ITEMS    (((P_SIZE + 15) & ~15))         ; the main item list
%define CC_COUNT    (CC_ITEMS + 8)
%define CC_CAP      (CC_ITEMS + 12)
%define CC_XML      (CC_ITEMS + 16)                 ; the element's tag, read again
%define CC_ATTR     (CC_XML + UgfxSvgXml_SIZE)
%define CC_RAW      (CC_ATTR + UgfxSvgAttr_SIZE)    ; a mask's x, y, width, height as written
%define CC_KIND     (CC_RAW + 64)                   ; u32
%define CC_SIZE     (((CC_KIND + 4 + 15) & ~15) + 8)

section .rodata
align 8
svg_one:            dq 1.0
svg_half:           dq 0.5
svg_four:           dq 4.0
svg_255:            dq 255.0
svg_default_w:      dq 300.0
svg_default_h:      dq 150.0
svg_neg_half_pi:    dq -1.5707963267948966
svg_half_pi:        dq 1.5707963267948966
svg_pi:             dq 3.141592653589793
svg_16:             dq 16.0
svg_pt:             dq 0x3FF5555555555555   ; 96 / 72
svg_pc:             dq 16.0
svg_mm:             dq 0x400E3C78F1E3C790   ; 96 / 25.4
svg_cm:             dq 0x4042E5CB972E5CB9   ; 96 / 2.54
svg_in:             dq 96.0
svg_1_2:            dq 0x3FF3333333333333   ; 1.2: larger / smaller
; font-size keywords, by id - 1
svg_font_sizes:     dq 9.0, 10.0, 13.0, 16.0, 18.0, 24.0, 32.0
; what a percentage of each geometry slot is of
svg_slot_axis:      db AX_X, AX_Y, AX_X, AX_Y, AX_X, AX_Y, AX_X, AX_Y, AX_D
                    db AX_X, AX_Y, AX_X, AX_Y

; names: length, text, id
%macro NAME 2
    db %strlen(%1), %1, %2
%endmacro
svg_elements:
    NAME "svg", E_SVG
    NAME "g", E_GROUP
    NAME "path", E_PATH
    NAME "rect", E_RECT
    NAME "circle", E_CIRCLE
    NAME "ellipse", E_ELLIPSE
    NAME "line", E_LINE
    NAME "polyline", E_POLYLINE
    NAME "polygon", E_POLYGON
    NAME "defs", E_SKIP
    NAME "clipPath", E_CLIPPATH
    NAME "mask", E_MASK
    NAME "symbol", E_SYMBOL
    NAME "use", E_USE
    NAME "linearGradient", E_SKIP
    NAME "radialGradient", E_SKIP
    NAME "pattern", E_PATTERN
    NAME "marker", E_MARKER
    NAME "image", E_IMAGE
    NAME "marker", E_SKIP
    NAME "text", E_TEXT
    NAME "switch", E_SWITCH
    NAME "style", E_SKIP
    NAME "script", E_SKIP
    NAME "title", E_SKIP
    NAME "desc", E_SKIP
    NAME "metadata", E_SKIP
    NAME "foreignObject", E_FOREIGN
    NAME "filter", E_SKIP
    db 0
svg_attributes:
    NAME "fill", A_FILL
    NAME "stroke", A_STROKE
    NAME "stroke-width", A_SW
    NAME "stroke-linecap", A_CAP
    NAME "stroke-linejoin", A_JOIN
    NAME "stroke-miterlimit", A_MITER
    NAME "fill-rule", A_RULE
    NAME "fill-opacity", A_FILL_OP
    NAME "stroke-opacity", A_STROKE_OP
    NAME "opacity", A_OPACITY
    NAME "display", A_DISPLAY
    NAME "font-size", A_FONT_SIZE
    NAME "color", A_COLOR
    NAME "visibility", A_VISIBILITY
    NAME "stroke-dasharray", A_DASHARRAY
    NAME "stroke-dashoffset", A_DASHOFFSET
    NAME "paint-order", A_PAINT_ORDER
    NAME "clip-path", A_CLIP_PATH
    NAME "clip-rule", A_CLIP_RULE
    NAME "mask", A_MASK
    NAME "marker-start", A_MARKER_START
    NAME "marker-mid", A_MARKER_MID
    NAME "marker-end", A_MARKER_END
    NAME "marker", A_MARKER
    NAME "transform", A_TRANSFORM
    NAME "style", A_STYLE
    NAME "d", A_D
    NAME "points", A_POINTS
    NAME "viewBox", A_VIEWBOX
    NAME "id", A_ID
    NAME "class", A_CLASS
    NAME "href", A_HREF
    NAME "xlink:href", A_HREF
    NAME "preserveAspectRatio", A_PAR
    NAME "x", A_GEOM + G_X
    NAME "y", A_GEOM + G_Y
    NAME "width", A_GEOM + G_W
    NAME "height", A_GEOM + G_H
    NAME "rx", A_GEOM + G_RX
    NAME "ry", A_GEOM + G_RY
    NAME "cx", A_GEOM + G_CX
    NAME "cy", A_GEOM + G_CY
    NAME "r", A_GEOM + G_R
    NAME "x1", A_GEOM + G_X1
    NAME "y1", A_GEOM + G_Y1
    NAME "x2", A_GEOM + G_X2
    NAME "y2", A_GEOM + G_Y2
    db 0
svg_font_words:
    NAME "xx-small", 1
    NAME "x-small", 2
    NAME "small", 3
    NAME "medium", 4
    NAME "large", 5
    NAME "x-large", 6
    NAME "xx-large", 7
    NAME "larger", 8
    NAME "smaller", 9
    db 0
; what inherit copies from the parent: id, state offset (u16), bytes
%macro INHERITS 3
    db %1
    dw %2
    db %3
%endmacro
svg_inherit_fields:
    INHERITS A_FILL, S_FILL_KIND, 8
    INHERITS A_FILL, S_FILL_ID, 16
    INHERITS A_FILL, S_FILL_FB, 4
    INHERITS A_STROKE, S_STROKE_KIND, 8
    INHERITS A_STROKE, S_STROKE_ID, 16
    INHERITS A_STROKE, S_STROKE_FB, 4
    INHERITS A_SW, S_SW, 8
    INHERITS A_CAP, S_CAP, 4
    INHERITS A_JOIN, S_JOIN, 4
    INHERITS A_MITER, S_MITER, 8
    INHERITS A_RULE, S_RULE, 4
    INHERITS A_FILL_OP, S_FILL_OP, 8
    INHERITS A_STROKE_OP, S_STROKE_OP, 8
    INHERITS A_FONT_SIZE, S_FONT, 8
    INHERITS A_COLOR, S_COLOR_SET, 8
    INHERITS A_VISIBILITY, S_HIDDEN, 4
    INHERITS A_DASHARRAY, S_DASH, 16
    INHERITS A_DASHOFFSET, S_DASH_OFF, 8
    INHERITS A_PAINT_ORDER, S_ORDER, 4
    INHERITS A_CLIP_RULE, S_CLIPRULE, 4
    INHERITS A_MARKER_START, S_MARKERS, 16
    INHERITS A_MARKER_MID, S_MARKERS + 16, 16
    INHERITS A_MARKER_END, S_MARKERS + 32, 16
    INHERITS A_MARKER, S_MARKERS, 48
    db 0
svg_marker_words:
    NAME "markerUnits", 1
    NAME "refX", 2
    NAME "refY", 3
    NAME "markerWidth", 4
    NAME "markerHeight", 5
    NAME "orient", 6
    NAME "viewBox", 7
    NAME "preserveAspectRatio", 8
    NAME "overflow", 9
    db 0
svg_orient_words:
    NAME "auto", 1
    NAME "auto-start-reverse", 2
    db 0
svg_overflow_words:
    NAME "visible", 1
    NAME "auto", 1
    db 0
svg_three_text:     db "3"
svg_word_user:      db "userSpaceOnUse"
align 8
svg_deg:            dq 0x3F91DF46A2529D39   ; pi / 180
svg_two_pi:         dq 6.283185307179586
svg_clip_attrs:
    NAME "clipPathUnits", 1
    NAME "clip-path", 2
    db 0
svg_mask_attrs:
    NAME "maskUnits", 1
    NAME "maskContentUnits", 2
    NAME "x", 3
    NAME "y", 4
    NAME "width", 5
    NAME "height", 6
    NAME "mask-type", 7
    db 0
svg_pattern_words:
    NAME "patternUnits", 1
    NAME "patternContentUnits", 2
    NAME "x", 3
    NAME "y", 4
    NAME "width", 5
    NAME "height", 6
    NAME "patternTransform", 7
    NAME "viewBox", 8
    NAME "preserveAspectRatio", 9
    NAME "href", 10
    NAME "xlink:href", 10
    db 0
svg_zero_text:      db "0"
align 8
svg_1_5:            dq 1.5
svg_word_alpha:     db "alpha"
svg_m10:            db "-10%"
svg_120:            db "120%"
svg_word_obb:       db "objectBoundingBox"
svg_cond_words:
    NAME "requiredExtensions", 1
    NAME "systemLanguage", 2
    db 0
svg_par_words:
    NAME "xMinYMin", 1
    NAME "xMidYMin", 2
    NAME "xMaxYMin", 3
    NAME "xMinYMid", 4
    NAME "xMidYMid", 5
    NAME "xMaxYMid", 6
    NAME "xMinYMax", 7
    NAME "xMidYMax", 8
    NAME "xMaxYMax", 9
    NAME "none", 10
    NAME "meet", 20
    NAME "slice", 21
    NAME "defer", 30
    db 0
align 8
svg_align_f:        dq 0.0, 0.5, 1.0
svg_word_inherit:   db "inherit"
svg_word_visible:   db "visible"
svg_word_hidden:    db "hidden"
svg_word_collapse:  db "collapse"
svg_word_normal:    db "normal"
svg_word_fill:      db "fill"
svg_word_stroke:    db "stroke"
svg_word_markers:   db "markers"
svg_word_none:      db "none"
svg_word_butt:      db "butt"
svg_word_round:     db "round"
svg_word_square:    db "square"
svg_word_miter:     db "miter"
svg_word_bevel:     db "bevel"
svg_word_evenodd:   db "evenodd"
svg_word_nonzero:   db "nonzero"

section .text

; rdi = text, rsi = end (trimmed), rdx = word, ecx = length -> ZF = equal
svg_word:
    mov rax, rsi
    sub rax, rdi
    cmp rax, rcx
    jne .done
    xor r8d, r8d
.byte:
    cmp r8d, ecx
    jae .done                           ; ZF from cmp below / xor: equal
    movzx eax, byte [rdi + r8]
    cmp al, [rdx + r8]
    jne .done
    inc r8d
    jmp .byte
.done:
    ret

%macro IS_WORD 1
    lea rdx, [rel svg_word_%1]
    mov ecx, %strlen(%1)
    call svg_word_trimmed
%endmacro

; rdi / rsi = value: trimmed of whitespace, then compared -> ZF = equal
svg_word_trimmed:
    push rdi
    push rsi
    call ugfx_svg_trim
    call svg_word
    pop rsi
    pop rdi
    ret

; -----------------------------------------------------------------------------
; ugfx_svg_parse — rdi = UgfxSvg*, rsi = arena, rdx = data, rcx = bytes
;   -> rax = 0, -EINVAL (no svg element, or nesting deeper than 64),
;   -ENOMEM. Malformed markup ends the document where it breaks.
; -----------------------------------------------------------------------------
global ugfx_svg_parse
ugfx_svg_parse:
    xor r8d, r8d                        ; no images
    xor r9d, r9d

; -----------------------------------------------------------------------------
; ugfx_svg_parse_ex — as ugfx_svg_parse, r8 = image_fn (0: none), r9 = its
;   user pointer (see UgfxSvg_image_fn)
; -----------------------------------------------------------------------------
global ugfx_svg_parse_ex
ugfx_svg_parse_ex:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, P_SIZE
    mov r15, rsp
    mov rax, -(EINVAL)
    test rdi, rdi
    jz .out
    test rsi, rsi
    jz .out
    test rdx, rdx
    jz .out
    mov [r15 + P_SVG], rdi
    mov [rdi + UgfxSvg_arena], rsi
    mov [rdi + UgfxSvg_image_fn], r8
    mov [rdi + UgfxSvg_image_user], r9
    mov qword [rdi + UgfxSvg_items], 0
    mov dword [rdi + UgfxSvg_count], 0
    mov dword [rdi + UgfxSvg_cap], 0
    mov dword [rdi + UgfxSvg_has], 0
    mov dword [rdi + UgfxSvg_par], PAR_DEFAULT
    mov [r15 + P_XML + UgfxSvgXml_cur], rdx
    add rdx, rcx
    mov [r15 + P_XML + UgfxSvgXml_end], rdx
    mov dword [r15 + P_DEPTH], 0
    mov dword [r15 + P_ROOT], 0
    mov dword [r15 + P_ERR], 0
    ; the state stack, with the defaults at depth 0
    mov rdi, rsi
    mov esi, (SVG_MAX_DEPTH + 1) * S_SIZE
    call arena_alloc
    test rax, rax
    jz .nomem
    mov [r15 + P_STACK], rax
    mov rbx, rax
    mov rdi, rbx
    call umath_affine2_identity
    mov dword [rbx + S_FILL_KIND], 1
    mov dword [rbx + S_FILL], 0xFF000000
    mov dword [rbx + S_STROKE_KIND], 0
    mov dword [rbx + S_STROKE], 0xFF000000
    movsd xmm0, [rel svg_one]
    movsd [rbx + S_FILL_OP], xmm0
    movsd [rbx + S_STROKE_OP], xmm0
    movsd [rbx + S_OP], xmm0
    movsd [rbx + S_SW], xmm0
    movsd xmm0, [rel svg_four]
    movsd [rbx + S_MITER], xmm0
    mov dword [rbx + S_JOIN], UGFX_JOIN_MITER
    mov dword [rbx + S_CAP], UGFX_CAP_BUTT
    mov dword [rbx + S_RULE], UGFX_FILL_NONZERO
    mov dword [rbx + S_SKIP], 0
    movsd xmm0, [rel svg_16]
    movsd [rbx + S_FONT], xmm0
    movsd xmm0, [rel svg_default_w]
    movsd [rbx + S_VW], xmm0
    movsd xmm0, [rel svg_default_h]
    movsd [rbx + S_VH], xmm0
    xor eax, eax
    mov [rbx + S_COLOR_SET], eax
    mov [rbx + S_HIDDEN], eax
    mov [rbx + S_ORDER], eax
    mov [rbx + S_DASH], rax
    mov [rbx + S_DASH_N], eax
    mov [rbx + S_DASH_OFF], rax
    mov [rbx + S_SWITCH], eax
    mov [rbx + S_CLIPRULE], eax
    mov [rbx + S_MARKERS], rax
    mov [rbx + S_MARKERS + 16], rax
    mov [rbx + S_MARKERS + 32], rax
    ; gradients first: url(#id) may name one defined further on
    lea rdi, [r15 + P_DEFS]
    mov rax, [r15 + P_SVG]
    mov rsi, [rax + UgfxSvg_arena]
    mov rdx, [r15 + P_XML + UgfxSvgXml_cur]
    mov rcx, [r15 + P_XML + UgfxSvgXml_end]
    sub rcx, rdx
    call ugfx_svg_defs_scan
    test rax, rax
    jnz .nomem
    mov dword [r15 + P_USES], 0
    mov dword [r15 + P_CLIPMODE], 0
    mov dword [r15 + P_COMPILE], 0
    mov dword [r15 + P_INST], 0
    mov dword [r15 + P_SYMROOT], 0
    mov edi, -1
    call svg_walk                       ; the whole document
    jmp .finish

.finish:
    ; groups an unterminated document left open
    mov eax, [r15 + P_DEPTH]
    imul rdi, rax, S_SIZE
    add rdi, [r15 + P_STACK]
    cmp dword [r15 + P_DEPTH], 0
    je .closed
    call svg_group_close
    dec dword [r15 + P_DEPTH]
    jmp .finish
.closed:
    movsxd rax, dword [r15 + P_ERR]
    test rax, rax
    jnz .out
    cmp dword [r15 + P_ROOT], 0
    jne .out
    mov rax, -(EINVAL)
    jmp .out
.nomem:
    mov rax, -(ENOMEM)
.out:
    add rsp, P_SIZE
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15

; -----------------------------------------------------------------------------
; svg_walk — edi = depth to stop at (-1: the end of the document), r15 =
;   frame: tags, from the XML cursor, until an end tag (or a self-closing
;   tag) brings the depth back to it
; -----------------------------------------------------------------------------
svg_walk:
    push rbx
    push r12
    sub rsp, 8
    mov r12d, edi
.token:
    cmp dword [r15 + P_ERR], 0
    jne .return
    lea rdi, [r15 + P_XML]
    call ugfx_svg_xml_next
    test eax, eax
    jz .return
    cmp eax, 2
    jne .start_tag
    cmp dword [r15 + P_DEPTH], 0        ; an end tag
    je .token
    mov eax, [r15 + P_DEPTH]
    imul rdi, rax, S_SIZE
    add rdi, [r15 + P_STACK]            ; the element it closes
    call svg_group_close
    dec dword [r15 + P_DEPTH]
    cmp [r15 + P_DEPTH], r12d
    je .return
    jmp .token
.start_tag:
    mov rax, [r15 + P_XML + UgfxSvgXml_tag_end]
    mov [r15 + P_TAGEND], rax
    mov eax, [r15 + P_XML + UgfxSvgXml_self]
    mov [r15 + P_SELF], eax
    ; push the state
    mov eax, [r15 + P_DEPTH]
    cmp eax, SVG_MAX_DEPTH
    jae .too_deep
    imul rsi, rax, S_SIZE
    add rsi, [r15 + P_STACK]            ; parent
    lea rdi, [rsi + S_SIZE]             ; child
    mov rbx, rdi
    mov ecx, S_SIZE
    rep movsb
    mov dword [rbx + S_GROUP], 0
    mov dword [rbx + S_VPGROUP], 0
    inc dword [r15 + P_DEPTH]
    ; the element
    mov rdi, [r15 + P_XML + UgfxSvgXml_name]
    mov rsi, [r15 + P_XML + UgfxSvgXml_name_end]
    lea rdx, [rel svg_elements]
    call ugfx_svg_lookup
    cmp eax, -1
    jne .known
    xor eax, eax                        ; unknown: a group
.known:
    ; a symbol is drawn only as the root of a <use> instance, as a group
    ; (a clipPath likewise, as the root of its compiled content)
    mov ecx, [r15 + P_INST]
    mov dword [r15 + P_INST], 0
    mov dword [r15 + P_SYMROOT], 0
    mov dword [r15 + P_CROOT], 0
    cmp eax, E_CLIPPATH
    je .clip_root
    cmp eax, E_MASK
    je .mask_root
    cmp eax, E_PATTERN
    je .pattern_root
    cmp eax, E_MARKER
    je .marker_root
    cmp eax, E_SYMBOL
    jne .kind
    mov eax, E_SKIP
    cmp ecx, 1
    jne .kind
    mov eax, E_GROUP
    mov dword [r15 + P_SYMROOT], 1
    jmp .kind
.clip_root:
    mov eax, E_SKIP
    cmp ecx, K_CLIP
    jne .kind
    mov eax, E_GROUP
    mov dword [r15 + P_CROOT], 1
    jmp .kind
.mask_root:
    mov eax, E_SKIP
    cmp ecx, K_MASK
    jne .kind
    mov eax, E_GROUP
    mov dword [r15 + P_CROOT], 1
    jmp .kind
.pattern_root:
    mov eax, E_SKIP
    cmp ecx, K_PATTERN
    jne .kind
    mov eax, E_GROUP
    mov dword [r15 + P_CROOT], 1
    jmp .kind
.marker_root:
    mov eax, E_SKIP
    cmp ecx, K_MARKER
    jne .kind
    mov eax, E_GROUP
    mov dword [r15 + P_CROOT], 1
.kind:
    ; conditional processing; a switch keeps only its first child that passes
    cmp eax, E_SKIP
    je .decided                         ; not rendered, takes no part
    cmp dword [rbx - S_SIZE + S_SWITCH], 2
    je .not_chosen
    mov [rsp], eax
    call svg_conditions
    test eax, eax
    jz .not_chosen
    mov eax, [rsp]
    cmp dword [rbx - S_SIZE + S_SWITCH], 1
    jne .decided
    mov dword [rbx - S_SIZE + S_SWITCH], 2
    jmp .decided
.not_chosen:
    mov eax, E_SKIP
.decided:
    xor ecx, ecx
    cmp eax, E_SWITCH
    sete cl
    mov [rbx + S_SWITCH], ecx
    cmp eax, E_TEXT
    je .no_drawing
    cmp eax, E_FOREIGN
    jne .chosen
.no_drawing:
    mov eax, E_SKIP
.chosen:
    mov [r15 + P_ELEM], eax
    cmp eax, E_SKIP
    jne .not_skipped
    mov dword [rbx + S_SKIP], 1
.not_skipped:
    cmp dword [rbx + S_SKIP], 0
    jne .element_done
    call svg_element                    ; attributes, style, shape
.element_done:
    cmp dword [r15 + P_SELF], 0
    je .token
    mov rdi, rbx
    call svg_group_close
    dec dword [r15 + P_DEPTH]
    cmp [r15 + P_DEPTH], r12d
    je .return
    jmp .token
.too_deep:
    mov dword [r15 + P_ERR], -(EINVAL)
.return:
    add rsp, 8
    pop r12
    pop rbx
    ret


; -----------------------------------------------------------------------------
; svg_element — r15 = frame, rbx = the element's state,
;   P_XML = its tag: reads attributes and style, then builds the shape
; -----------------------------------------------------------------------------
svg_element:
    push r12
    push r13
    push r14
    xor eax, eax
    mov [r15 + P_HAVE], eax
    mov [r15 + P_D], rax
    mov [r15 + P_STYLE], rax
    mov [r15 + P_VB], rax
    movsd xmm0, [rel svg_one]
    movsd [r15 + P_OPACITY], xmm0
    xorpd xmm0, xmm0
    xor ecx, ecx
.zero_geom:
    movsd [r15 + P_G + rcx * 8], xmm0
    inc ecx
    cmp ecx, G_COUNT
    jb .zero_geom
    mov rax, [r15 + P_XML + UgfxSvgXml_name]
    mov [r15 + P_SEL + UgfxSvgSel_name], rax
    mov rax, [r15 + P_XML + UgfxSvgXml_name_end]
    mov [r15 + P_SEL + UgfxSvgSel_name_end], rax
    mov qword [r15 + P_SEL + UgfxSvgSel_id], 0
    mov qword [r15 + P_SEL + UgfxSvgSel_class], 0
    mov qword [r15 + P_HREF], 0
    mov qword [r15 + P_HREF_RAW], 0
    mov dword [r15 + P_GRAW], 0
    mov qword [r15 + P_FONT_RAW], 0
    mov qword [r15 + P_SW_RAW], 0
    mov qword [r15 + P_DASH_RAW], 0
    mov qword [r15 + P_DOFF_RAW], 0
    mov dword [r15 + P_PAR], PAR_DEFAULT
    mov qword [r15 + P_CLIP], 0
    mov qword [r15 + P_MASK], 0
    mov qword [r15 + P_ATTR + UgfxSvgAttr_cur], 0
.attr:
    lea rdi, [r15 + P_XML]
    lea rsi, [r15 + P_ATTR]
    call ugfx_svg_xml_attr
    test eax, eax
    jz .attrs_done
    ; dispatch
    mov rdi, [r15 + P_ATTR + UgfxSvgAttr_name]
    mov rsi, [r15 + P_ATTR + UgfxSvgAttr_name_end]
    lea rdx, [rel svg_attributes]
    call ugfx_svg_lookup
    cmp eax, -1
    je .attr
    mov rdi, [r15 + P_ATTR + UgfxSvgAttr_val]
    mov rsi, [r15 + P_ATTR + UgfxSvgAttr_val_end]
    cmp eax, A_STYLE
    je .attr_style
    cmp eax, A_D
    je .attr_d
    cmp eax, A_POINTS
    je .attr_d
    cmp eax, A_VIEWBOX
    je .attr_viewbox
    cmp eax, A_TRANSFORM
    je .attr_transform
    cmp eax, A_ID
    je .attr_id
    cmp eax, A_CLASS
    je .attr_class
    cmp eax, A_HREF
    je .attr_href
    cmp eax, A_PAR
    je .attr_par
    cmp eax, A_GEOM
    jae .attr_geom
    call svg_property
    jmp .attr
.attr_style:
    mov [r15 + P_STYLE], rdi
    mov [r15 + P_STYLE_END], rsi
    jmp .attr
.attr_d:
    mov [r15 + P_D], rdi
    mov [r15 + P_D_END], rsi
    jmp .attr
.attr_viewbox:
    mov [r15 + P_VB], rdi
    mov [r15 + P_VB_END], rsi
    jmp .attr
.attr_id:
    call ugfx_svg_trim
    mov [r15 + P_SEL + UgfxSvgSel_id], rdi
    mov [r15 + P_SEL + UgfxSvgSel_id_end], rsi
    jmp .attr
.attr_href:
    call ugfx_svg_trim
    mov [r15 + P_HREF_RAW], rdi
    mov [r15 + P_HREF_RAW_END], rsi
    cmp rdi, rsi
    jae .attr
    cmp byte [rdi], '#'
    jne .attr
    inc rdi
    mov [r15 + P_HREF], rdi
    mov [r15 + P_HREF_END], rsi
    jmp .attr
.attr_par:
    call svg_par
    mov [r15 + P_PAR], eax
    jmp .attr
.attr_class:
    mov [r15 + P_SEL + UgfxSvgSel_class], rdi
    mov [r15 + P_SEL + UgfxSvgSel_class_end], rsi
    jmp .attr
.attr_transform:
    lea rdx, [rbx + S_M]
    call ugfx_svg_transform             ; an invalid list changes nothing
    jmp .attr
.attr_geom:
    sub eax, A_GEOM                     ; resolved once font-size is known
    mov ecx, eax
    shl ecx, 4
    mov [r15 + P_GV + rcx], rdi
    mov [r15 + P_GV + rcx + 8], rsi
    bts dword [r15 + P_GRAW], eax
    jmp .attr
.attrs_done:
    ; CSS rules (cascade order), then the style attribute, over the attributes
    xor r12d, r12d
.css:
    cmp r12d, [r15 + P_DEFS + UgfxSvgDefs_nrules]
    jae .style
    lea rdi, [r15 + P_DEFS]
    mov esi, r12d
    lea rdx, [r15 + P_SEL]
    call ugfx_svg_defs_rule
    inc r12d
    test rax, rax
    jz .css
    mov rdi, rax
    mov rsi, rdx
    call svg_decls
    jmp .css
.style:
    mov rdi, [r15 + P_STYLE]
    test rdi, rdi
    jz .styled
    mov rsi, [r15 + P_STYLE_END]
    call svg_decls
.styled:
    call svg_lengths
    cmp dword [rbx + S_SKIP], 0
    jne .element_out
    ; a container's own opacity: a group (a shape's: svg_shape)
    mov eax, [r15 + P_ELEM]
    cmp eax, E_PATH
    jb .container
    cmp eax, E_POLYGON
    jbe .not_container
.container:
    cmp dword [r15 + P_CLIPMODE], 0
    jne .not_container                  ; a clip's content: geometry only
    cmp dword [r15 + P_CROOT], 0
    jne .not_container                  ; a clipPath / mask itself
    call svg_clip_ref
    mov [r15 + P_CLIPREC], rax
    call svg_mask_ref
    mov [r15 + P_MASKREC], rax
    test rax, rax
    jnz .open
    cmp qword [r15 + P_CLIPREC], 0
    jne .open
    movsd xmm0, [r15 + P_OPACITY]
    ucomisd xmm0, [rel svg_one]
    jae .not_container
.open:
    call svg_group_open
.not_container:
    cmp dword [r15 + P_SYMROOT], 0
    je .not_symbol
    call svg_symbol_map
.not_symbol:
    mov eax, [r15 + P_ELEM]
    cmp eax, E_USE
    je .use
    cmp eax, E_IMAGE
    je .image
    cmp eax, E_SVG
    je .root
    cmp eax, E_PATH
    jb .element_out                     ; groups
    cmp eax, E_POLYGON
    ja .element_out
    call svg_shape
    jmp .element_out
.use:
    call svg_use
    jmp .element_out
.image:
    call svg_image
    jmp .element_out
.root:
    cmp dword [r15 + P_ROOT], 0
    jne .nested
    mov dword [r15 + P_ROOT], 1
    mov rcx, [r15 + P_SVG]
    mov eax, [r15 + P_PAR]
    mov [rcx + UgfxSvg_par], eax
    test dword [r15 + P_HAVE], 1 << G_W
    jz .root_h
    movsd xmm0, [r15 + P_G + G_W * 8]
    movsd [rcx + UgfxSvg_width], xmm0
    or dword [rcx + UgfxSvg_has], 2
.root_h:
    test dword [r15 + P_HAVE], 1 << G_H
    jz .root_vb
    movsd xmm0, [r15 + P_G + G_H * 8]
    movsd [rcx + UgfxSvg_height], xmm0
    or dword [rcx + UgfxSvg_has], 4
.root_vb:
    mov r12, [r15 + P_VB]
    test r12, r12
    jz .root_view
    ; four numbers, width and height > 0
    xor r13d, r13d
.vb_number:
    cmp r13d, 4
    jae .vb_check
    mov rdi, r12
    mov rsi, [r15 + P_VB_END]
    call ugfx_svg_number
    test rax, rax
    jz .root_view
    mov r12, rax
    movsd [r15 + P_ARC + r13 * 8], xmm0
    inc r13d
    jmp .vb_number
.vb_check:
    xorpd xmm1, xmm1
    movsd xmm0, [r15 + P_ARC + 16]
    ucomisd xmm0, xmm1
    jbe .root_view
    movsd xmm0, [r15 + P_ARC + 24]
    ucomisd xmm0, xmm1
    jbe .root_view
    mov rcx, [r15 + P_SVG]
    xor eax, eax
.vb_copy:
    movsd xmm0, [r15 + P_ARC + rax * 8]
    movsd [rcx + UgfxSvg_viewbox + rax * 8], xmm0
    inc eax
    cmp eax, 4
    jb .vb_copy
    or dword [rcx + UgfxSvg_has], 1
    call svg_root_slice
.root_view:
    call svg_viewport                   ; what percentages inside are of
    movsd xmm0, [r15 + P_VIEW]
    movsd [rbx + S_VW], xmm0
    movsd xmm0, [r15 + P_VIEW + 8]
    movsd [rbx + S_VH], xmm0
    jmp .element_out
.nested:
    call svg_nested
.element_out:
    pop r14
    pop r13
    pop r12
    ret

; -----------------------------------------------------------------------------
; svg_use — r15 = frame, rbx = the <use>'s state (attributes applied): the
;   element its href names is walked again as its child, after
;   translate(x, y); width / height size an instanced symbol. Nothing for
;   an unknown id or past SVG_MAX_USES instances inside instances.
; -----------------------------------------------------------------------------
%define U_XML       0                   ; the XML state to come back to
%define U_SELF      UgfxSvgXml_SIZE
%define U_ELEM      (U_SELF + 4)
%define U_TAGEND    (U_SELF + 8)
%define U_M         (U_SELF + 16)       ; f64[6]
%define U_SIZE      (U_M + 48 + 16)       ; calls at rsp = 0 (mod 16)

svg_use:
    push r12
    push r13
    sub rsp, U_SIZE
    mov rsi, [r15 + P_HREF]
    test rsi, rsi
    jz .out
    cmp dword [r15 + P_USES], SVG_MAX_USES
    jae .out
    lea rdi, [r15 + P_DEFS]
    mov rdx, [r15 + P_HREF_END]
    call ugfx_svg_defs_id
    test rax, rax
    jz .out
    mov r12, rax                        ; the target's '<'
    ; translate(x, y) after the use's own transform
    lea rdi, [rsp + U_M]
    movsd xmm0, [r15 + P_G + G_X * 8]
    movsd xmm1, [r15 + P_G + G_Y * 8]
    call umath_affine2_translate
    lea rdi, [rbx + S_M]
    mov rsi, rdi
    lea rdx, [rsp + U_M]
    call umath_affine2_multiply
    ; width and height (default 100%), for a symbol
    movsd xmm0, [rbx + S_VW]
    test dword [r15 + P_HAVE], 1 << G_W
    jz .use_w
    movsd xmm0, [r15 + P_G + G_W * 8]
.use_w:
    movsd [r15 + P_USE_W], xmm0
    movsd xmm0, [rbx + S_VH]
    test dword [r15 + P_HAVE], 1 << G_H
    jz .use_h
    movsd xmm0, [r15 + P_G + G_H * 8]
.use_h:
    movsd [r15 + P_USE_H], xmm0
    ; keep where reading is, walk the target, come back
    lea rdi, [rsp + U_XML]
    lea rsi, [r15 + P_XML]
    mov ecx, UgfxSvgXml_SIZE
    rep movsb
    mov eax, [r15 + P_SELF]
    mov [rsp + U_SELF], eax
    mov eax, [r15 + P_ELEM]
    mov [rsp + U_ELEM], eax
    mov rax, [r15 + P_TAGEND]
    mov [rsp + U_TAGEND], rax
    mov [r15 + P_XML + UgfxSvgXml_cur], r12
    mov dword [r15 + P_INST], 1
    inc dword [r15 + P_USES]
    mov edi, [r15 + P_DEPTH]
    call svg_walk
    dec dword [r15 + P_USES]
    mov dword [r15 + P_INST], 0
    lea rdi, [r15 + P_XML]
    lea rsi, [rsp + U_XML]
    mov ecx, UgfxSvgXml_SIZE
    rep movsb
    mov eax, [rsp + U_SELF]
    mov [r15 + P_SELF], eax
    mov eax, [rsp + U_ELEM]
    mov [r15 + P_ELEM], eax
    mov rax, [rsp + U_TAGEND]
    mov [r15 + P_TAGEND], rax
.out:
    add rsp, U_SIZE
    pop r13
    pop r12
    ret

; r15 = frame, rbx = an instanced symbol's state: its viewport is the
;   <use>'s width x height
svg_symbol_map:
    sub rsp, 8
    xorpd xmm0, xmm0
    xorpd xmm1, xmm1
    movsd xmm2, [r15 + P_USE_W]
    movsd xmm3, [r15 + P_USE_H]
    call svg_view_clip
    add rsp, 8
    movsd xmm0, [r15 + P_USE_W]
    movsd xmm1, [r15 + P_USE_H]
    jmp svg_view_map

; r15 = frame, rbx = a nested svg's state: translate(x, y), then its
;   viewport width x height (default 100%); not drawn when either is <= 0
svg_nested:
    sub rsp, 8
    lea rdi, [r15 + P_ARC]
    movsd xmm0, [r15 + P_G + G_X * 8]
    movsd xmm1, [r15 + P_G + G_Y * 8]
    call umath_affine2_translate
    lea rdi, [rbx + S_M]
    mov rsi, rdi
    lea rdx, [r15 + P_ARC]
    call umath_affine2_multiply
    movsd xmm0, [rbx + S_VW]
    test dword [r15 + P_HAVE], 1 << G_W
    jz .w
    movsd xmm0, [r15 + P_G + G_W * 8]
.w:
    movsd xmm1, [rbx + S_VH]
    test dword [r15 + P_HAVE], 1 << G_H
    jz .h
    movsd xmm1, [r15 + P_G + G_H * 8]
.h:
    xorpd xmm2, xmm2
    ucomisd xmm0, xmm2
    jbe .hide
    ucomisd xmm1, xmm2
    jbe .hide
    movsd [r15 + P_USE_W], xmm0         ; (free here: a use's, consumed)
    movsd [r15 + P_USE_H], xmm1
    movapd xmm2, xmm0
    movapd xmm3, xmm1
    xorpd xmm0, xmm0
    xorpd xmm1, xmm1
    call svg_view_clip
    movsd xmm0, [r15 + P_USE_W]
    movsd xmm1, [r15 + P_USE_H]
    add rsp, 8
    jmp svg_view_map
.hide:
    mov dword [rbx + S_SKIP], 1
    add rsp, 8
    ret

; xmm0..xmm3 = x, y, w, h in the element's space (S_M), r15 = frame, rbx =
;   state: a group clipping its content to that rectangle (not in a clip's
;   content)
svg_view_clip:
    push r12
    cmp dword [r15 + P_CLIPMODE], 0
    jne .out
    call svg_rect_clip
    test rax, rax
    jz .out
    mov [r15 + P_CLIPREC], rax
    mov ecx, 1
    call svg_item_room
    test rax, rax
    jz .nomem
    mov r12, rax
    mov dword [r12 + UgfxSvgItem_kind], UGFX_SVG_BEGIN
    mov dword [r12 + UgfxSvgItem_alpha], 255
    mov rax, [r15 + P_CLIPREC]
    mov [r12 + UgfxSvgItem_clip], rax
    mov qword [r12 + UgfxSvgItem_mask], 0
    xor ecx, ecx
.m:
    mov rax, [rbx + S_M + rcx * 8]
    mov [r12 + UgfxSvgItem_matrix + rcx * 8], rax
    inc ecx
    cmp ecx, 6
    jb .m
    mov rax, [r15 + P_SVG]
    mov ecx, [rax + UgfxSvg_count]
    inc dword [rax + UgfxSvg_count]
    inc ecx
    mov [rbx + S_VPGROUP], ecx
    jmp .out
.nomem:
    mov dword [r15 + P_ERR], -(ENOMEM)
.out:
    pop r12
    ret

; xmm0..xmm3 = x, y, w, h, r15 = frame -> rax = a UgfxSvgClip of that one
;   rectangle (0: out of memory)
svg_rect_clip:
    push r12
    push r13
    sub rsp, 40
    movsd [rsp], xmm0
    movsd [rsp + 8], xmm1
    movsd [rsp + 16], xmm2
    movsd [rsp + 24], xmm3
    mov rax, [r15 + P_SVG]
    mov rdi, [rax + UgfxSvg_arena]
    mov esi, UgfxSvgClip_SIZE + UgfxSvgItem_SIZE
    call arena_alloc
    test rax, rax
    jz .nomem
    mov r12, rax
    lea r13, [r12 + UgfxSvgClip_SIZE]
    mov [r12 + UgfxSvgClip_items], r13
    mov dword [r12 + UgfxSvgClip_count], 1
    mov dword [r12 + UgfxSvgClip_units], 0
    mov qword [r12 + UgfxSvgClip_next], 0
    mov dword [r13 + UgfxSvgItem_kind], UGFX_SVG_SHAPE
    mov dword [r13 + UgfxSvgItem_rule], UGFX_FILL_NONZERO
    lea rdi, [r13 + UgfxSvgItem_matrix]
    call umath_affine2_identity
    lea rdi, [r13 + UgfxSvgItem_path]
    mov rax, [r15 + P_SVG]
    mov rsi, [rax + UgfxSvg_arena]
    call ugfx_path_init
    test rax, rax
    jnz .nomem
    lea rdi, [r13 + UgfxSvgItem_path]
    movsd xmm0, [rsp]
    movsd xmm1, [rsp + 8]
    movsd xmm2, [rsp + 16]
    movsd xmm3, [rsp + 24]
    call ugfx_path_add_rect
    test rax, rax
    jnz .nomem
    mov rax, r12
    jmp .out
.nomem:
    mov dword [r15 + P_ERR], -(ENOMEM)
    xor eax, eax
.out:
    add rsp, 40
    pop r13
    pop r12
    ret

; r15 = frame (P_ARC = the root's viewBox, just read), rbx = the root's
;   state: with slice, a viewport clip - the viewport (width x height when
;   both are given, else a square) in viewBox units
svg_root_slice:
    push r12
    sub rsp, 48
    mov eax, [r15 + P_PAR]
    test eax, 0x100
    jz .out
    test al, al
    jz .out
    movsd xmm0, [rel svg_one]
    movapd xmm1, xmm0
    mov rcx, [r15 + P_SVG]
    mov edx, [rcx + UgfxSvg_has]
    and edx, 6
    cmp edx, 6
    jne .square
    xorpd xmm2, xmm2
    movsd xmm3, [rcx + UgfxSvg_width]
    ucomisd xmm3, xmm2
    jbe .square
    movsd xmm4, [rcx + UgfxSvg_height]
    ucomisd xmm4, xmm2
    jbe .square
    movapd xmm0, xmm3
    movapd xmm1, xmm4
.square:
    movsd [rsp], xmm0                   ; Wv, Hv
    movsd [rsp + 8], xmm1
    lea rdi, [r15 + P_ARC + 64]
    lea rsi, [r15 + P_ARC]
    mov edx, [r15 + P_PAR]
    call svg_fit
    ; x0 = -tx / s, y0 = -ty / s, w = Wv / s, h = Hv / s
    movsd xmm4, [r15 + P_ARC + 64]      ; s (sx = sy: an alignment)
    xorpd xmm0, xmm0
    subsd xmm0, [r15 + P_ARC + 64 + 32]
    divsd xmm0, xmm4
    xorpd xmm1, xmm1
    subsd xmm1, [r15 + P_ARC + 64 + 40]
    divsd xmm1, xmm4
    movsd xmm2, [rsp]
    divsd xmm2, xmm4
    movsd xmm3, [rsp + 8]
    divsd xmm3, xmm4
    call svg_view_clip
.out:
    add rsp, 48
    pop r12
    ret

; -----------------------------------------------------------------------------
; svg_view_map — xmm0 = width, xmm1 = height of the element's viewport, r15
;   = frame (P_VB, P_PAR), rbx = state: a valid viewBox is fitted into it
;   (S_M x the fit) and becomes the viewport inside; without one the
;   viewport is width x height
; -----------------------------------------------------------------------------
%define VM_VB       0                   ; f64[4]
%define VM_M        32                  ; f64[6]
%define VM_W        80
%define VM_H        88
%define VM_SIZE     104

svg_view_map:
    push r12
    push r13
    sub rsp, VM_SIZE
    movsd [rsp + VM_W], xmm0
    movsd [rsp + VM_H], xmm1
    movsd [rbx + S_VW], xmm0
    movsd [rbx + S_VH], xmm1
    mov r12, [r15 + P_VB]
    test r12, r12
    jz .out
    xor r13d, r13d
.number:
    cmp r13d, 4
    jae .have
    mov rdi, r12
    mov rsi, [r15 + P_VB_END]
    call ugfx_svg_number
    test rax, rax
    jz .out
    mov r12, rax
    movsd [rsp + VM_VB + r13 * 8], xmm0
    inc r13d
    jmp .number
.have:
    xorpd xmm7, xmm7
    movsd xmm2, [rsp + VM_VB + 16]
    ucomisd xmm2, xmm7
    jbe .out
    movsd xmm3, [rsp + VM_VB + 24]
    ucomisd xmm3, xmm7
    jbe .out
    movsd [rbx + S_VW], xmm2
    movsd [rbx + S_VH], xmm3
    lea rdi, [rsp + VM_M]
    lea rsi, [rsp + VM_VB]
    movsd xmm0, [rsp + VM_W]
    movsd xmm1, [rsp + VM_H]
    mov edx, [r15 + P_PAR]
    call svg_fit
    lea rdi, [rbx + S_M]
    mov rsi, rdi
    lea rdx, [rsp + VM_M]
    call umath_affine2_multiply
.out:
    add rsp, VM_SIZE
    pop r13
    pop r12
    ret

; -----------------------------------------------------------------------------
; svg_fit — rdi = out f64[6], rsi = viewBox (x, y, w, h; w, h > 0), xmm0 =
;   width, xmm1 = height, edx = preserveAspectRatio (as UgfxSvg_par):
;   [sx 0 0 sy tx ty] with sx = W / w, sy = H / h (both min or max of the
;   two unless align is none), tx = (W - w sx) f - x sx, f = 0, 1/2, 1
;   for min, mid, max (0 for none); ty the same
; -----------------------------------------------------------------------------
svg_fit:
    movsd xmm2, [rsi + 16]
    movsd xmm3, [rsi + 24]
    movapd xmm4, xmm0
    divsd xmm4, xmm2                    ; sx
    movapd xmm5, xmm1
    divsd xmm5, xmm3                    ; sy
    movzx eax, dl
    xorpd xmm6, xmm6                    ; fx
    xorpd xmm7, xmm7                    ; fy
    test eax, eax
    jz .scaled
    test edx, 0x100
    jnz .slice
    minsd xmm4, xmm5
    jmp .uniform
.slice:
    maxsd xmm4, xmm5
.uniform:
    movapd xmm5, xmm4
    dec eax
    xor edx, edx
    mov ecx, 3
    div ecx                             ; eax = y index, edx = x index
    lea rcx, [rel svg_align_f]
    movsd xmm6, [rcx + rdx * 8]
    movsd xmm7, [rcx + rax * 8]
.scaled:
    ; tx
    movapd xmm8, xmm2
    mulsd xmm8, xmm4
    subsd xmm0, xmm8
    mulsd xmm0, xmm6
    movsd xmm8, [rsi]
    mulsd xmm8, xmm4
    subsd xmm0, xmm8
    ; ty
    movapd xmm8, xmm3
    mulsd xmm8, xmm5
    subsd xmm1, xmm8
    mulsd xmm1, xmm7
    movsd xmm8, [rsi + 8]
    mulsd xmm8, xmm5
    subsd xmm1, xmm8
    xorpd xmm8, xmm8
    movsd [rdi], xmm4
    movsd [rdi + 8], xmm8
    movsd [rdi + 16], xmm8
    movsd [rdi + 24], xmm5
    movsd [rdi + 32], xmm0
    movsd [rdi + 40], xmm1
    ret

; rdi / rsi = preserveAspectRatio -> eax = align | slice << 8; anything
;   invalid gives the default, xMidYMid meet
svg_par:
    push r12
    push r13
    push r14
    call ugfx_svg_trim
    mov r12, rdi
    mov r13, rsi
    call .token
    cmp eax, 30
    jne .align
    call .token                         ; defer: ignored
.align:
    cmp eax, 10
    je .none
    cmp eax, 1
    jb .default
    cmp eax, 9
    ja .default
    mov r14d, eax
    jmp .meet
.none:
    xor r14d, r14d
.meet:
    call .token
    test eax, eax
    jz .done                            ; nothing more: meet
    cmp eax, 20
    je .end
    cmp eax, 21
    jne .default
    or r14d, 0x100
.end:
    call .token
    test eax, eax
    jnz .default
.done:
    mov eax, r14d
    jmp .out
.default:
    mov eax, PAR_DEFAULT
.out:
    pop r14
    pop r13
    pop r12
    ret
; r12 / r13 = the rest -> eax = the next word's id (0: none left, -1:
;   unknown), r12 past it
.token:
    cmp r12, r13
    jae .no_token
    cmp byte [r12], ' '
    ja .word
    inc r12
    jmp .token
.no_token:
    xor eax, eax
    ret
.word:
    mov rdi, r12
.word_end:
    cmp r12, r13
    jae .lookup
    cmp byte [r12], ' '
    jbe .lookup
    inc r12
    jmp .word_end
.lookup:
    mov rsi, r12
    lea rdx, [rel svg_par_words]
    sub rsp, 8
    call ugfx_svg_lookup
    add rsp, 8
    ret

; r15 = frame, the start tag in P_XML -> eax = 1 when its conditional
;   attributes pass
svg_conditions:
    push r12
    push r13
    push r14
    mov r14d, 1
    mov qword [r15 + P_ATTR + UgfxSvgAttr_cur], 0
.attr:
    lea rdi, [r15 + P_XML]
    lea rsi, [r15 + P_ATTR]
    call ugfx_svg_xml_attr
    test eax, eax
    jz .done
    mov rdi, [r15 + P_ATTR + UgfxSvgAttr_name]
    mov rsi, [r15 + P_ATTR + UgfxSvgAttr_name_end]
    lea rdx, [rel svg_cond_words]
    call ugfx_svg_lookup
    cmp eax, 1
    je .fail                            ; requiredExtensions: none supported
    cmp eax, 2
    jne .attr
    mov rdi, [r15 + P_ATTR + UgfxSvgAttr_val]
    mov rsi, [r15 + P_ATTR + UgfxSvgAttr_val_end]
    call svg_language
    test eax, eax
    jnz .attr
.fail:
    xor r14d, r14d
.done:
    mov eax, r14d
    pop r14
    pop r13
    pop r12
    ret

; rdi / rsi = systemLanguage -> eax = 1 when a comma-separated tag is en or
;   en-*
svg_language:
    push r12
    push r13
    sub rsp, 8
    mov r12, rdi
    mov r13, rsi
.tag:
    mov rdi, r12
.comma:
    cmp r12, r13
    jae .have
    cmp byte [r12], ','
    je .have
    inc r12
    jmp .comma
.have:
    mov rsi, r12
    call ugfx_svg_trim
    mov rax, rsi
    sub rax, rdi
    cmp rax, 2
    jb .next
    movzx ecx, byte [rdi]
    or ecx, 0x20
    cmp ecx, 'e'
    jne .next
    movzx ecx, byte [rdi + 1]
    or ecx, 0x20
    cmp ecx, 'n'
    jne .next
    cmp rax, 2
    je .yes
    cmp byte [rdi + 2], '-'
    je .yes
.next:
    cmp r12, r13
    jae .no
    inc r12                             ; past the comma
    jmp .tag
.yes:
    mov eax, 1
    jmp .out
.no:
    xor eax, eax
.out:
    add rsp, 8
    pop r13
    pop r12
    ret

; -----------------------------------------------------------------------------
; svg_decls — rdi / rsi = "name: value; ..." declarations (a style
;   attribute or a CSS rule), rbx = state, r15 = frame: each style property
;   applied in order
; -----------------------------------------------------------------------------
svg_decls:
    push r12
    push r13
    push r14
    push rbx
    sub rsp, 8
    mov r12, rdi
    mov [rsp], rsi
.decl:
    mov rsi, [rsp]
    cmp r12, rsi
    jae .done
    ; name up to ':'
    mov rdi, r12
.colon:
    cmp rdi, rsi
    jae .done
    cmp byte [rdi], ':'
    je .named
    cmp byte [rdi], ';'
    je .skip
    inc rdi
    jmp .colon
.skip:
    lea r12, [rdi + 1]
    jmp .decl
.named:
    mov r13, rdi                        ; ':'
    ; value up to ';'
    lea r14, [rdi + 1]
.semi:
    cmp r14, rsi
    jae .value
    cmp byte [r14], ';'
    je .value
    inc r14
    jmp .semi
.value:
    mov rdi, r12
    mov rsi, r13
    call ugfx_svg_trim
    lea rdx, [rel svg_attributes]
    call ugfx_svg_lookup
    lea r12, [r14 + 1]
    cmp eax, A_LAST_PROP
    ja .decl                            ; not a style property (or unknown)
    lea rdi, [r13 + 1]
    mov rsi, r14
    call svg_property
    jmp .decl
.done:
    add rsp, 8
    pop rbx
    pop r14
    pop r13
    pop r12
    ret

; -----------------------------------------------------------------------------
; svg_property — eax = A_* (1..A_LAST_PROP), rdi / rsi = value, rbx = state,
;   r15 = frame. Values that do not parse leave the state alone.
; -----------------------------------------------------------------------------
svg_property:
    push r12
    push r13
    sub rsp, 8
    mov r12d, eax
    push rdi
    push rsi
    IS_WORD inherit
    pop rsi
    pop rdi
    je .inherit
    mov eax, r12d
    cmp eax, A_FILL
    je .paint
    cmp eax, A_STROKE
    je .paint
    cmp eax, A_SW
    je .width
    cmp eax, A_CAP
    je .cap
    cmp eax, A_JOIN
    je .join
    cmp eax, A_MITER
    je .miter
    cmp eax, A_RULE
    je .rule
    cmp eax, A_DISPLAY
    je .display
    cmp eax, A_FONT_SIZE
    je .font_size
    cmp eax, A_COLOR
    je .color
    cmp eax, A_VISIBILITY
    je .visibility
    cmp eax, A_DASHARRAY
    je .dasharray
    cmp eax, A_DASHOFFSET
    je .dashoffset
    cmp eax, A_PAINT_ORDER
    je .paint_order
    cmp eax, A_CLIP_PATH
    je .clip_path
    cmp eax, A_CLIP_RULE
    je .clip_rule
    cmp eax, A_MASK
    je .mask
    cmp eax, A_MARKER_START
    jae .marker
    ; opacities: a number (or a percentage), clamped to [0, 1]
    mov r13, rsi
    call ugfx_svg_number
    test rax, rax
    jz .out
    cmp rax, r13
    jae .opacity_clamp
    cmp byte [rax], '%'
    jne .opacity_clamp
    mulsd xmm0, [rel svg_hundredth]
.opacity_clamp:
    xorpd xmm1, xmm1
    maxsd xmm0, xmm1
    minsd xmm0, [rel svg_one]
    cmp r12d, A_FILL_OP
    je .fill_op
    cmp r12d, A_STROKE_OP
    je .stroke_op
    movsd [r15 + P_OPACITY], xmm0
    jmp .out
.fill_op:
    movsd [rbx + S_FILL_OP], xmm0
    jmp .out
.stroke_op:
    movsd [rbx + S_STROKE_OP], xmm0
    jmp .out
.paint:
    push rdi
    push rsi
    call ugfx_svg_trim
    mov rax, rsi
    sub rax, rdi
    cmp rax, 4
    jb .paint_plain
    cmp dword [rdi], 'url('
    jne .paint_plain
    add rsp, 16
    call svg_url
    test rax, rax
    jz .out                             ; malformed: ignored
    lea rcx, [rbx + S_FILL_KIND]
    lea r8, [rbx + S_FILL_ID]
    lea r9, [rbx + S_FILL_FB]
    cmp r12d, A_FILL
    je .url_set
    lea rcx, [rbx + S_STROKE_KIND]
    lea r8, [rbx + S_STROKE_ID]
    lea r9, [rbx + S_STROKE_FB]
.url_set:
    mov dword [rcx], 3
    mov [r8], rax
    mov [r8 + 8], rdx
    ; the fallback after ')': none, a colour or currentColor
    push rcx
    push r9
    call ugfx_svg_colour
    pop r9
    pop rcx
    cmp eax, 2
    jbe .url_fallback
    xor eax, eax                        ; none given / not usable: none
.url_fallback:
    mov [r9], eax
    cmp eax, 1
    je .url_colour
    mov edx, 0xFF000000
.url_colour:
    mov [rcx + 4], edx
    jmp .out
.paint_plain:
    pop rsi
    pop rdi
    call ugfx_svg_colour
    cmp eax, 3
    jae .out                            ; inherit (already) or invalid (-1)
    lea rcx, [rbx + S_FILL_KIND]
    cmp r12d, A_FILL
    je .paint_set
    lea rcx, [rbx + S_STROKE_KIND]
.paint_set:
    mov [rcx], eax
    cmp eax, 1
    je .paint_colour
    mov edx, 0xFF000000                 ; none / currentColor: no alpha of its own
.paint_colour:
    mov [rcx + 4], edx
    jmp .out
.width:
    mov [r15 + P_SW_RAW], rdi           ; resolved with the final font-size
    mov [r15 + P_SW_RAW_END], rsi
    jmp .out
.font_size:
    mov [r15 + P_FONT_RAW], rdi
    mov [r15 + P_FONT_RAW_END], rsi
    jmp .out
.dasharray:
    mov [r15 + P_DASH_RAW], rdi
    mov [r15 + P_DASH_RAW_END], rsi
    jmp .out
.dashoffset:
    mov [r15 + P_DOFF_RAW], rdi
    mov [r15 + P_DOFF_RAW_END], rsi
    jmp .out
.color:
    call ugfx_svg_colour                ; a colour; currentColor keeps the parent's
    cmp eax, 1
    jne .out
    mov dword [rbx + S_COLOR_SET], 1
    mov [rbx + S_COLOR], edx
    jmp .out
.visibility:
    IS_WORD visible
    mov eax, 0
    je .visibility_set
    IS_WORD hidden
    mov eax, 1
    je .visibility_set
    IS_WORD collapse
    mov eax, 1
    jne .out
.visibility_set:
    mov [rbx + S_HIDDEN], eax
    jmp .out
.paint_order:
    call svg_paint_order
    test eax, eax
    js .out
    mov [rbx + S_ORDER], eax
    jmp .out
.inherit:
    call svg_inherit
    jmp .out
.clip_path:
    call ugfx_svg_trim
    mov [r15 + P_CLIP], rdi
    mov [r15 + P_CLIP_END], rsi
    IS_WORD none
    jne .out
    mov qword [r15 + P_CLIP], 0
    jmp .out
.marker:
    ; url(...) or none, into one slot or all three
    call ugfx_svg_trim
    push rdi
    push rsi
    IS_WORD none
    pop rsi
    pop rdi
    jne .marker_url
    xor edi, edi
    xor esi, esi
    jmp .marker_set
.marker_url:
    mov rax, rsi
    sub rax, rdi
    cmp rax, 4
    jb .out
    mov eax, [rdi]
    or eax, 0x20202020
    cmp eax, 'url('
    jne .out
.marker_set:
    lea ecx, [r12 - A_MARKER_START]
    cmp r12d, A_MARKER
    je .marker_all
    shl ecx, 4
    mov [rbx + S_MARKERS + rcx], rdi
    mov [rbx + S_MARKERS + rcx + 8], rsi
    jmp .out
.marker_all:
    mov [rbx + S_MARKERS], rdi
    mov [rbx + S_MARKERS + 8], rsi
    mov [rbx + S_MARKERS + 16], rdi
    mov [rbx + S_MARKERS + 24], rsi
    mov [rbx + S_MARKERS + 32], rdi
    mov [rbx + S_MARKERS + 40], rsi
    jmp .out
.mask:
    call ugfx_svg_trim
    mov [r15 + P_MASK], rdi
    mov [r15 + P_MASK_END], rsi
    IS_WORD none
    jne .out
    mov qword [r15 + P_MASK], 0
    jmp .out
.clip_rule:
    IS_WORD evenodd
    mov eax, UGFX_FILL_EVENODD
    je .clip_rule_set
    IS_WORD nonzero
    mov eax, UGFX_FILL_NONZERO
    jne .out
.clip_rule_set:
    mov [rbx + S_CLIPRULE], eax
    jmp .out
.miter:
    call ugfx_svg_number
    test rax, rax
    jz .out
    ucomisd xmm0, [rel svg_one]
    jb .out
    movsd [rbx + S_MITER], xmm0
    jmp .out
.cap:
    IS_WORD butt
    mov eax, UGFX_CAP_BUTT
    je .cap_set
    IS_WORD round
    mov eax, UGFX_CAP_ROUND
    je .cap_set
    IS_WORD square
    mov eax, UGFX_CAP_SQUARE
    jne .out
.cap_set:
    mov [rbx + S_CAP], eax
    jmp .out
.join:
    IS_WORD round
    mov eax, UGFX_JOIN_ROUND
    je .join_set
    IS_WORD bevel
    mov eax, UGFX_JOIN_BEVEL
    je .join_set
    ; miter, miter-clip, arcs: miter
    lea rdx, [rel svg_word_miter]
    mov ecx, 5
    push rdi
    push rsi
    call ugfx_svg_trim
    mov rax, rsi
    sub rax, rdi
    cmp rax, 5
    jb .join_not_miter
    mov rsi, rdi
    add rsi, 5
    call svg_word
.join_not_miter:
    pop rsi
    pop rdi
    mov eax, UGFX_JOIN_MITER
    jne .out
.join_set:
    mov [rbx + S_JOIN], eax
    jmp .out
.rule:
    IS_WORD evenodd
    mov eax, UGFX_FILL_EVENODD
    je .rule_set
    IS_WORD nonzero
    mov eax, UGFX_FILL_NONZERO
    jne .out
.rule_set:
    mov [rbx + S_RULE], eax
    jmp .out
.display:
    IS_WORD none
    jne .out
    mov dword [rbx + S_SKIP], 1
.out:
    add rsp, 8
    pop r13
    pop r12
    ret

; r12d = A_* given as inherit, rbx = state (its parent just below it), r15 =
;   frame: the parent's value, and nothing pending from earlier declarations
svg_inherit:
    lea rsi, [rel svg_inherit_fields]
.field:
    movzx eax, byte [rsi]
    test eax, eax
    jz .pending
    cmp eax, r12d
    jne .next
    movzx ecx, word [rsi + 1]
    movzx edx, byte [rsi + 3]
    lea rdi, [rbx + rcx]
    lea r8, [rbx + rcx - S_SIZE]
.copy:
    mov al, [r8]
    mov [rdi], al
    inc r8
    inc rdi
    dec edx
    jnz .copy
.next:
    add rsi, 4
    jmp .field
.pending:
    cmp r12d, A_SW
    jne .not_sw
    mov qword [r15 + P_SW_RAW], 0
.not_sw:
    cmp r12d, A_FONT_SIZE
    jne .not_font
    mov qword [r15 + P_FONT_RAW], 0
.not_font:
    cmp r12d, A_DASHARRAY
    jne .not_dash
    mov qword [r15 + P_DASH_RAW], 0
.not_dash:
    cmp r12d, A_DASHOFFSET
    jne .not_doff
    mov qword [r15 + P_DOFF_RAW], 0
.not_doff:
    cmp r12d, A_CLIP_PATH
    jne .not_clip
    mov qword [r15 + P_CLIP], 0         ; not inherited: none
.not_clip:
    cmp r12d, A_MASK
    jne .not_mask
    mov qword [r15 + P_MASK], 0         ; not inherited: none
.not_mask:
    cmp r12d, A_OPACITY
    jne .done
    movsd xmm0, [rel svg_one]           ; not inherited: the initial value
    movsd [r15 + P_OPACITY], xmm0
.done:
    ret

; rdi / rsi = paint-order -> eax = 1 when stroke comes before fill, 0
;   otherwise, -1 for an invalid value (normal, or fill / stroke / markers
;   in some order)
svg_paint_order:
    push r12
    push r13
    push r14
    call ugfx_svg_trim
    mov r12, rdi
    mov r13, rsi
    lea rdx, [rel svg_word_normal]
    mov ecx, 6
    call svg_word
    mov eax, 0
    je .out
    mov r14d, -1
.token:
    cmp r12, r13
    jae .end
    cmp byte [r12], ' '
    ja .word
    inc r12
    jmp .token
.word:
    mov rdi, r12
.word_end:
    cmp rdi, r13
    jae .have_word
    cmp byte [rdi], ' '
    jbe .have_word
    inc rdi
    jmp .word_end
.have_word:
    mov rsi, rdi
    mov rdi, r12
    mov r12, rsi
    push rdi
    push rsi
    lea rdx, [rel svg_word_fill]
    mov ecx, 4
    call svg_word
    pop rsi
    pop rdi
    mov eax, 0
    je .first
    push rdi
    push rsi
    lea rdx, [rel svg_word_stroke]
    mov ecx, 6
    call svg_word
    pop rsi
    pop rdi
    mov eax, 1
    je .first
    lea rdx, [rel svg_word_markers]
    mov ecx, 7
    call svg_word
    je .token
    mov eax, -1
    jmp .out
.first:
    test r14d, r14d
    jns .token
    mov r14d, eax
    jmp .token
.end:
    xor eax, eax
    test r14d, r14d
    js .out
    mov eax, r14d
.out:
    pop r14
    pop r13
    pop r12
    ret

; rdi / rsi = a dash list, rdx = where the values go (0: only count them),
;   rbx = state -> eax = count (-1: invalid: a negative value or something
;   that is not a length), xmm0 = their sum
svg_dash_pass:
    push r12
    push r13
    push r14
    sub rsp, 16
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    mov dword [rsp], 0
    xorpd xmm0, xmm0
    movsd [rsp + 8], xmm0
.value:
    mov rdi, r12
    mov rsi, r13
    mov edx, AX_D
    call svg_length
    test rax, rax
    jz .tail
    xorpd xmm1, xmm1
    ucomisd xmm0, xmm1
    jb .invalid
    mov r12, rax
    mov ecx, [rsp]
    test r14, r14
    jz .counted
    movsd [r14 + rcx * 8], xmm0
.counted:
    inc dword [rsp]
    movsd xmm1, [rsp + 8]
    addsd xmm1, xmm0
    movsd [rsp + 8], xmm1
    jmp .value
.tail:
    cmp r12, r13                        ; only separators may follow
    jae .ok
    movzx eax, byte [r12]
    inc r12
    cmp al, ','
    je .tail
    cmp al, ' '
    je .tail
    cmp al, 9
    je .tail
    cmp al, 10
    je .tail
    cmp al, 13
    je .tail
.invalid:
    mov eax, -1
    jmp .out
.ok:
    mov eax, [rsp]
    movsd xmm0, [rsp + 8]
.out:
    add rsp, 16
    pop r14
    pop r13
    pop r12
    ret

; rdi / rsi = stroke-dasharray (trimmed, not none), rbx = state, r15 =
;   frame: S_DASH / S_DASH_N, an odd list repeated to make it even; solid
;   when it is invalid or adds up to 0
svg_dash_list:
    push r12
    push r13
    push r14
    mov r12, rdi
    mov r13, rsi
    xor edx, edx
    call svg_dash_pass
    test eax, eax
    jle .none
    xorpd xmm1, xmm1
    ucomisd xmm0, xmm1
    jbe .none
    mov r14d, eax
    mov rax, [r15 + P_SVG]
    mov rdi, [rax + UgfxSvg_arena]
    mov esi, r14d
    shl esi, 4                          ; room for the list twice
    call arena_alloc
    test rax, rax
    jz .nomem
    mov [rbx + S_DASH], rax
    mov rdi, r12
    mov rsi, r13
    mov rdx, rax
    call svg_dash_pass
    mov eax, r14d
    test eax, 1
    jz .even
    mov rsi, [rbx + S_DASH]
    lea rdi, [rsi + r14 * 8]
    mov ecx, r14d
    shl ecx, 3
    rep movsb
    lea eax, [r14 + r14]
.even:
    mov [rbx + S_DASH_N], eax
    jmp .out
.nomem:
    mov dword [r15 + P_ERR], -(ENOMEM)
.none:
    mov dword [rbx + S_DASH_N], 0
.out:
    pop r14
    pop r13
    pop r12
    ret

; ecx = items wanted (1..3), r15 = frame -> rax = the next free item, room
;   for ecx from there (0: out of memory)
svg_item_room:
    push r12
    push r13
    push r14
    mov r14, [r15 + P_SVG]
    mov eax, [r14 + UgfxSvg_count]
    add eax, ecx
    cmp eax, [r14 + UgfxSvg_cap]
    jbe .room
    mov r12d, [r14 + UgfxSvg_cap]
    add r12d, r12d
    cmp r12d, eax
    jae .size
    lea r12d, [rax + 16]
.size:
    cmp r12d, 16
    jae .grow
    mov r12d, 16
.grow:
    mov rdi, [r14 + UgfxSvg_arena]
    imul esi, r12d, UgfxSvgItem_SIZE
    call arena_alloc
    test rax, rax
    jz .out
    mov [r14 + UgfxSvg_cap], r12d
    mov rdi, rax
    mov rsi, [r14 + UgfxSvg_items]
    mov ecx, [r14 + UgfxSvg_count]
    imul ecx, ecx, UgfxSvgItem_SIZE
    mov rdx, rax
    rep movsb
    mov [r14 + UgfxSvg_items], rdx
.room:
    mov eax, [r14 + UgfxSvg_count]
    imul rax, rax, UgfxSvgItem_SIZE
    add rax, [r14 + UgfxSvg_items]
.out:
    pop r14
    pop r13
    pop r12
    ret

; r15 = frame -> eax = round(own opacity x 255)
svg_group_alpha:
    movsd xmm0, [r15 + P_OPACITY]
    mulsd xmm0, [rel svg_255]
    addsd xmm0, [rel svg_half]
    cvttsd2si eax, xmm0
    ret

; r15 = frame, rbx = a container's state: a BEGIN item at its opacity,
;   with P_CLIPREC and the container's matrix
svg_group_open:
    push r12
    mov ecx, 1
    call svg_item_room
    test rax, rax
    jz .nomem
    mov r12, rax
    mov dword [r12 + UgfxSvgItem_kind], UGFX_SVG_BEGIN
    call svg_group_alpha
    mov [r12 + UgfxSvgItem_alpha], eax
    mov rax, [r15 + P_CLIPREC]
    mov [r12 + UgfxSvgItem_clip], rax
    mov rax, [r15 + P_MASKREC]
    mov [r12 + UgfxSvgItem_mask], rax
    xor ecx, ecx
.m:
    mov rax, [rbx + S_M + rcx * 8]
    mov [r12 + UgfxSvgItem_matrix + rcx * 8], rax
    inc ecx
    cmp ecx, 6
    jb .m
    mov rax, [r15 + P_SVG]
    mov ecx, [rax + UgfxSvg_count]
    inc dword [rax + UgfxSvg_count]
    inc ecx
    mov [rbx + S_GROUP], ecx            ; its index + 1
    pop r12
    ret
.nomem:
    mov dword [r15 + P_ERR], -(ENOMEM)
    pop r12
    ret

; rdi = the state of an element that is closing, r15 = frame: END for each
;   group it opened, its viewport clip first (alpha and clip copied; a
;   clipped group's bbox measured first)
svg_group_close:
    push rdi
    mov eax, [rdi + S_VPGROUP]
    mov dword [rdi + S_VPGROUP], 0
    call svg_group_end
    pop rdi
    mov eax, [rdi + S_GROUP]
    mov dword [rdi + S_GROUP], 0

; eax = a BEGIN's index + 1 (0: none), r15 = frame: its END
svg_group_end:
    test eax, eax
    jz .done
    push r12
    lea r12d, [rax - 1]                 ; the BEGIN's index
    mov rax, [r15 + P_SVG]
    imul rcx, r12, UgfxSvgItem_SIZE
    add rcx, [rax + UgfxSvg_items]
    mov rdx, [rcx + UgfxSvgItem_clip]
    or rdx, [rcx + UgfxSvgItem_mask]
    jz .room
    mov edi, r12d
    mov esi, [rax + UgfxSvg_count]
    call svg_group_bbox
.room:
    mov ecx, 1
    call svg_item_room
    test rax, rax
    jz .nomem
    mov rdx, [r15 + P_SVG]
    imul rsi, r12, UgfxSvgItem_SIZE
    add rsi, [rdx + UgfxSvg_items]
    mov rdi, rax
    call svg_end_from
    mov rax, [r15 + P_SVG]
    inc dword [rax + UgfxSvg_count]
    pop r12
.done:
    ret
.nomem:
    mov dword [r15 + P_ERR], -(ENOMEM)
    pop r12
    ret

; -----------------------------------------------------------------------------
; svg_group_bbox — edi = a BEGIN's index, esi = the end of its content (an
;   index), r15 = frame: the BEGIN's bbox = the union of its shapes' tight
;   bounds, each with its corners taken into the BEGIN's space (all 0 when
;   there are none or the BEGIN's matrix is singular)
; -----------------------------------------------------------------------------
%define BB_INV      0                   ; f64[6] the BEGIN's matrix inverted
%define BB_R        48                  ; f64[6] item -> BEGIN space
%define BB_B        96                  ; f64[4] one item's bounds
%define BB_BOX      128                 ; f64[4] the union
%define BB_ANY      160                 ; u32
%define BB_SIZE     168

svg_group_bbox:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, BB_SIZE
    mov r12d, edi
    mov r13d, esi
    mov dword [rsp + BB_ANY], 0
    xorpd xmm0, xmm0
    movsd [rsp + BB_BOX], xmm0
    movsd [rsp + BB_BOX + 8], xmm0
    movsd [rsp + BB_BOX + 16], xmm0
    movsd [rsp + BB_BOX + 24], xmm0
    mov rax, [r15 + P_SVG]
    mov rbx, [rax + UgfxSvg_items]
    imul rsi, r12, UgfxSvgItem_SIZE
    add rsi, rbx
    lea rsi, [rsi + UgfxSvgItem_matrix]
    lea rdi, [rsp + BB_INV]
    call umath_affine2_invert
    test eax, eax
    jnz .store
    lea r14d, [r12 + 1]
.item:
    cmp r14d, r13d
    jae .store
    imul rax, r14, UgfxSvgItem_SIZE
    add rax, rbx
    cmp dword [rax + UgfxSvgItem_kind], UGFX_SVG_SHAPE
    je .bounded_kind
    cmp dword [rax + UgfxSvgItem_kind], UGFX_SVG_IMAGE
    jne .next
.bounded_kind:
    push rax
    sub rsp, 8
    lea rdi, [rax + UgfxSvgItem_path]
    lea rsi, [rsp + 16 + BB_B]
    call ugfx_path_bounds_tight
    add rsp, 8
    pop rdx
    test rax, rax
    jnz .next
    lea rdi, [rsp + BB_R]
    lea rsi, [rsp + BB_INV]
    lea rdx, [rdx + UgfxSvgItem_matrix]
    call umath_affine2_multiply
    ; corners (x0, y0), (x1, y0), (x0, y1), (x1, y1)
    movsd xmm0, [rsp + BB_B]
    movsd xmm1, [rsp + BB_B + 8]
    call .corner
    movsd xmm0, [rsp + BB_B + 16]
    movsd xmm1, [rsp + BB_B + 8]
    call .corner
    movsd xmm0, [rsp + BB_B]
    movsd xmm1, [rsp + BB_B + 24]
    call .corner
    movsd xmm0, [rsp + BB_B + 16]
    movsd xmm1, [rsp + BB_B + 24]
    call .corner
.next:
    inc r14d
    jmp .item
.store:
    imul rdi, r12, UgfxSvgItem_SIZE
    add rdi, rbx
    xor ecx, ecx
.copy:
    mov rax, [rsp + BB_BOX + rcx * 8]
    mov [rdi + UgfxSvgItem_bbox + rcx * 8], rax
    inc ecx
    cmp ecx, 4
    jb .copy
    add rsp, BB_SIZE
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
; xmm0 / xmm1 = a point: through BB_R, into the union (frame at rsp + 8)
.corner:
    movsd xmm2, [rsp + 8 + BB_R]
    mulsd xmm2, xmm0
    movsd xmm3, [rsp + 8 + BB_R + 16]
    mulsd xmm3, xmm1
    addsd xmm2, xmm3
    addsd xmm2, [rsp + 8 + BB_R + 32]   ; x' = a x + c y + e
    movsd xmm4, [rsp + 8 + BB_R + 8]
    mulsd xmm4, xmm0
    movsd xmm3, [rsp + 8 + BB_R + 24]
    mulsd xmm3, xmm1
    addsd xmm4, xmm3
    addsd xmm4, [rsp + 8 + BB_R + 40]   ; y' = b x + d y + f
    cmp dword [rsp + 8 + BB_ANY], 0
    jne .grow
    mov dword [rsp + 8 + BB_ANY], 1
    movsd [rsp + 8 + BB_BOX], xmm2
    movsd [rsp + 8 + BB_BOX + 8], xmm4
    movsd [rsp + 8 + BB_BOX + 16], xmm2
    movsd [rsp + 8 + BB_BOX + 24], xmm4
    ret
.grow:
    movsd xmm0, [rsp + 8 + BB_BOX]
    minsd xmm0, xmm2
    movsd [rsp + 8 + BB_BOX], xmm0
    movsd xmm0, [rsp + 8 + BB_BOX + 8]
    minsd xmm0, xmm4
    movsd [rsp + 8 + BB_BOX + 8], xmm0
    movsd xmm0, [rsp + 8 + BB_BOX + 16]
    maxsd xmm0, xmm2
    movsd [rsp + 8 + BB_BOX + 16], xmm0
    movsd xmm0, [rsp + 8 + BB_BOX + 24]
    maxsd xmm0, xmm4
    movsd [rsp + 8 + BB_BOX + 24], xmm0
    ret

; -----------------------------------------------------------------------------
; svg_pattern_attrs — r13 = a new UgfxSvgPattern (content compiled), the
;   pattern's tag in [rsp + 8 + CC_XML] / CC_ATTR (svg_compile's frame),
;   r15 = frame, rbx = the referencing state: its attributes; an href'd
;   pattern (compiled first) gives those not given and, without content of
;   its own, its content. The tile's x, y, width, height are resolved:
;   fractions (or percentages) of the bbox, else user lengths.
; -----------------------------------------------------------------------------
%define PA_RAW      0                   ; x, y, w, h as written
%define PA_HREF     64                  ; the id an href names (0: none)
%define PA_HREF_END 72
%define PA_SIZE     88

svg_pattern_attrs:
    push r12
    push r14
    sub rsp, PA_SIZE
    %define PA_CC (8 + PA_SIZE + 16)    ; svg_compile's frame, from here
    mov dword [r13 + UgfxSvgPattern_units], 1
    mov dword [r13 + UgfxSvgPattern_par], PAR_DEFAULT
    mov dword [r13 + UgfxSvgPattern_given], 0
    lea rdi, [r13 + UgfxSvgPattern_matrix]
    call umath_affine2_identity
    lea rax, [rel svg_zero_text]
    xor ecx, ecx
.raw_default:
    mov [rsp + PA_RAW + rcx * 8], rax
    lea rdx, [rax + 1]
    mov [rsp + PA_RAW + rcx * 8 + 8], rdx
    add ecx, 2
    cmp ecx, 8
    jb .raw_default
    mov qword [rsp + PA_HREF], 0
.attr:
    lea rdi, [rsp + PA_CC + CC_XML]
    lea rsi, [rsp + PA_CC + CC_ATTR]
    call ugfx_svg_xml_attr
    test eax, eax
    jz .inherit
    mov rdi, [rsp + PA_CC + CC_ATTR + UgfxSvgAttr_name]
    mov rsi, [rsp + PA_CC + CC_ATTR + UgfxSvgAttr_name_end]
    lea rdx, [rel svg_pattern_words]
    call ugfx_svg_lookup
    test eax, eax
    jle .attr
    mov r14d, eax
    lea ecx, [rax - 1]
    bts dword [r13 + UgfxSvgPattern_given], ecx
    mov rdi, [rsp + PA_CC + CC_ATTR + UgfxSvgAttr_val]
    mov rsi, [rsp + PA_CC + CC_ATTR + UgfxSvgAttr_val_end]
    cmp r14d, 3
    jb .units
    cmp r14d, 6
    ja .other
    lea eax, [r14 - 3]
    shl eax, 4
    mov [rsp + PA_RAW + rax], rdi
    mov [rsp + PA_RAW + rax + 8], rsi
    jmp .attr
.units:
    call ugfx_svg_trim
    lea rdx, [rel svg_word_obb]
    mov ecx, 17
    call svg_word
    sete al
    movzx eax, al
    cmp r14d, 1
    jne .content_units
    mov [r13 + UgfxSvgPattern_units], eax
    jmp .attr
.content_units:
    mov [r13 + UgfxSvgPattern_content], eax
    jmp .attr
.other:
    cmp r14d, 7
    je .transform
    cmp r14d, 8
    je .viewbox
    cmp r14d, 9
    je .par
    call ugfx_svg_trim                  ; href: "#id"
    cmp rdi, rsi
    jae .attr
    cmp byte [rdi], '#'
    jne .attr
    inc rdi
    mov [rsp + PA_HREF], rdi
    mov [rsp + PA_HREF_END], rsi
    jmp .attr
.transform:
    lea rdx, [r13 + UgfxSvgPattern_matrix]
    call ugfx_svg_transform
    jmp .attr
.par:
    call svg_par
    mov [r13 + UgfxSvgPattern_par], eax
    jmp .attr
.viewbox:
    mov r12, rdi
    mov [rsp + PA_RAW + 64 + 16], rsi   ; (past PA_HREF_END: scratch)
    xor r14d, r14d
.vb_number:
    cmp r14d, 4
    jae .vb_check
    mov rdi, r12
    mov rsi, [rsp + PA_RAW + 64 + 16]
    call ugfx_svg_number
    test rax, rax
    jz .vb_bad
    mov r12, rax
    movsd [r13 + UgfxSvgPattern_viewbox + r14 * 8], xmm0
    inc r14d
    jmp .vb_number
.vb_check:
    xorpd xmm1, xmm1
    movsd xmm0, [r13 + UgfxSvgPattern_viewbox + 16]
    ucomisd xmm0, xmm1
    jbe .vb_bad
    movsd xmm0, [r13 + UgfxSvgPattern_viewbox + 24]
    ucomisd xmm0, xmm1
    jbe .vb_bad
    mov dword [r13 + UgfxSvgPattern_has_vb], 1
    jmp .attr
.vb_bad:
    mov dword [r13 + UgfxSvgPattern_has_vb], 0
    jmp .attr
.inherit:
    ; the tile, resolved here: fractions of the bbox, else user lengths
    xor r14d, r14d
.rect_value:
    cmp r14d, 4
    jae .href
    xorpd xmm0, xmm0
    movsd [r13 + UgfxSvgPattern_rect + r14 * 8], xmm0
    mov eax, r14d
    shl eax, 4
    mov rdi, [rsp + PA_RAW + rax]
    mov rsi, [rsp + PA_RAW + rax + 8]
    cmp dword [r13 + UgfxSvgPattern_units], 0
    je .rect_user
    push rsi
    sub rsp, 8
    call ugfx_svg_number
    add rsp, 8
    pop rsi
    test rax, rax
    jz .rect_next
    cmp rax, rsi
    jae .rect_set
    cmp byte [rax], '%'
    jne .rect_set
    mulsd xmm0, [rel svg_hundredth]
    jmp .rect_set
.rect_user:
    mov edx, r14d
    and edx, 1
    call svg_length
    test rax, rax
    jz .rect_next
.rect_set:
    movsd [r13 + UgfxSvgPattern_rect + r14 * 8], xmm0
.rect_next:
    inc r14d
    jmp .rect_value
.href:
    mov rsi, [rsp + PA_HREF]
    test rsi, rsi
    jz .square
    mov rdx, [rsp + PA_HREF_END]
    mov ecx, K_PATTERN
    call svg_compile
    test rax, rax
    jz .square
    ; what this pattern did not give, from the one it names
    mov r12, rax
    mov r14d, [r13 + UgfxSvgPattern_given]
    bt r14d, 0
    jc .h_content_units
    mov eax, [r12 + UgfxSvgPattern_units]
    mov [r13 + UgfxSvgPattern_units], eax
.h_content_units:
    bt r14d, 1
    jc .h_rect
    mov eax, [r12 + UgfxSvgPattern_content]
    mov [r13 + UgfxSvgPattern_content], eax
.h_rect:
    xor ecx, ecx
.h_rect_value:
    lea edx, [rcx + 2]
    bt r14d, edx
    jc .h_rect_next
    mov rax, [r12 + UgfxSvgPattern_rect + rcx * 8]
    mov [r13 + UgfxSvgPattern_rect + rcx * 8], rax
.h_rect_next:
    inc ecx
    cmp ecx, 4
    jb .h_rect_value
    bt r14d, 6
    jc .h_viewbox
    lea rdi, [r13 + UgfxSvgPattern_matrix]
    lea rsi, [r12 + UgfxSvgPattern_matrix]
    mov ecx, 48
    rep movsb
.h_viewbox:
    bt r14d, 7
    jc .h_par
    mov eax, [r12 + UgfxSvgPattern_has_vb]
    mov [r13 + UgfxSvgPattern_has_vb], eax
    lea rdi, [r13 + UgfxSvgPattern_viewbox]
    lea rsi, [r12 + UgfxSvgPattern_viewbox]
    mov ecx, 32
    rep movsb
.h_par:
    bt r14d, 8
    jc .h_content
    mov eax, [r12 + UgfxSvgPattern_par]
    mov [r13 + UgfxSvgPattern_par], eax
.h_content:
    cmp dword [r13 + UgfxSvgPattern_count], 0
    jne .square
    mov rax, [r12 + UgfxSvgPattern_items]
    mov [r13 + UgfxSvgPattern_items], rax
    mov eax, [r12 + UgfxSvgPattern_count]
    mov [r13 + UgfxSvgPattern_count], eax
.square:
    lea rdi, [r13 + UgfxSvgPattern_path]
    mov rax, [r15 + P_SVG]
    mov rsi, [rax + UgfxSvg_arena]
    call ugfx_path_init
    test rax, rax
    jnz .nomem
    lea rdi, [r13 + UgfxSvgPattern_path]
    xorpd xmm0, xmm0
    xorpd xmm1, xmm1
    movsd xmm2, [rel svg_one]
    movapd xmm3, xmm2
    call ugfx_path_add_rect
    test rax, rax
    jz .out
.nomem:
    mov dword [r15 + P_ERR], -(ENOMEM)
.out:
    add rsp, PA_SIZE
    pop r14
    pop r12
    ret

; -----------------------------------------------------------------------------
; svg_pattern_paint — rdi = UgfxSvgPattern*, rsi = the item (its bbox), edx
;   = 0 fill / 1 stroke, ecx = the paint's alpha, r13 = the context, rbp =
;   ugfx_svg_draw's frame; the context already clipped to the fill or the stroke outline,
;   in the item's space -> rax = 0 or a context error: the tiles that cover
;   the shape (its bbox, grown for a stroke), each clipped to itself, in a
;   layer at that alpha
; -----------------------------------------------------------------------------
%define PP_TB       0                   ; f64[6] the context's transform: the item's space
%define PP_INV      48                  ; f64[6] patternTransform inverted
%define PP_M        96                  ; f64[6] one tile's translation
%define PP_S        144                 ; f64[6] the tile's size / the content's transform
%define PP_R        192                 ; f64[4] the tile in user space
%define PP_C        224                 ; f64[4] what must be covered, user space
%define PP_P        256                 ; f64[4] the same in pattern space
%define PP_I0       288                 ; i32 tile indices: columns i0 .. i1 - 1
%define PP_I1       292
%define PP_J0       296
%define PP_J1       300
%define PP_I        304
%define PP_J        308
%define PP_STROKE   312                 ; u32
%define PP_ALPHA    316                 ; u32
%define PP_ANY      320                 ; u32 a corner seen
%define PP_SIZE     336

svg_pattern_paint:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, PP_SIZE
    mov rbx, rdi
    mov r12, rsi
    mov [rsp + PP_STROKE], edx
    mov [rsp + PP_ALPHA], ecx           ; (r13: the context, as svg_draw_list has it)
    xor r15d, r15d                      ; a layer opened
    xor r14d, r14d                      ; the result
    cmp dword [rbx + UgfxSvgPattern_count], 0
    je .out
    ; the tile: in the bbox's units, or as it is
    movsd xmm4, [r12 + UgfxSvgItem_bbox + 16]
    subsd xmm4, [r12 + UgfxSvgItem_bbox]           ; bw
    movsd xmm5, [r12 + UgfxSvgItem_bbox + 24]
    subsd xmm5, [r12 + UgfxSvgItem_bbox + 8]       ; bh
    movsd xmm0, [rbx + UgfxSvgPattern_rect]
    movsd xmm1, [rbx + UgfxSvgPattern_rect + 8]
    movsd xmm2, [rbx + UgfxSvgPattern_rect + 16]
    movsd xmm3, [rbx + UgfxSvgPattern_rect + 24]
    cmp dword [rbx + UgfxSvgPattern_units], 0
    je .rect
    mulsd xmm0, xmm4
    addsd xmm0, [r12 + UgfxSvgItem_bbox]
    mulsd xmm1, xmm5
    addsd xmm1, [r12 + UgfxSvgItem_bbox + 8]
    mulsd xmm2, xmm4
    mulsd xmm3, xmm5
.rect:
    movsd [rsp + PP_R], xmm0
    movsd [rsp + PP_R + 8], xmm1
    movsd [rsp + PP_R + 16], xmm2
    movsd [rsp + PP_R + 24], xmm3
    xorpd xmm6, xmm6
    ucomisd xmm2, xmm6
    jbe .out
    ucomisd xmm3, xmm6
    jbe .out
    ; what to cover: the bbox, grown by (width x max(miter, 1.5)) / 2 for a stroke
    xor ecx, ecx
.cover:
    mov rax, [r12 + UgfxSvgItem_bbox + rcx * 8]
    mov [rsp + PP_C + rcx * 8], rax
    inc ecx
    cmp ecx, 4
    jb .cover
    cmp dword [rsp + PP_STROKE], 0
    je .covered
    movsd xmm0, [r12 + UgfxSvgItem_miter]
    maxsd xmm0, [rel svg_1_5]
    movsd xmm1, [r12 + UgfxSvgItem_width]
    mulsd xmm1, xmm0
    mulsd xmm1, [rel svg_half]
    movsd xmm0, [rsp + PP_C]
    subsd xmm0, xmm1
    movsd [rsp + PP_C], xmm0
    movsd xmm0, [rsp + PP_C + 8]
    subsd xmm0, xmm1
    movsd [rsp + PP_C + 8], xmm0
    movsd xmm0, [rsp + PP_C + 16]
    addsd xmm0, xmm1
    movsd [rsp + PP_C + 16], xmm0
    movsd xmm0, [rsp + PP_C + 24]
    addsd xmm0, xmm1
    movsd [rsp + PP_C + 24], xmm0
.covered:
    ; into pattern space: the corners through patternTransform's inverse
    lea rdi, [rsp + PP_INV]
    lea rsi, [rbx + UgfxSvgPattern_matrix]
    call umath_affine2_invert
    test eax, eax
    jnz .out
    mov dword [rsp + PP_ANY], 0
    movsd xmm0, [rsp + PP_C]
    movsd xmm1, [rsp + PP_C + 8]
    call .corner
    movsd xmm0, [rsp + PP_C + 16]
    movsd xmm1, [rsp + PP_C + 8]
    call .corner
    movsd xmm0, [rsp + PP_C]
    movsd xmm1, [rsp + PP_C + 24]
    call .corner
    movsd xmm0, [rsp + PP_C + 16]
    movsd xmm1, [rsp + PP_C + 24]
    call .corner
    ; i0 = floor((px0 - x) / w), i1 = ceil((px1 - x) / w), the same for j
    movsd xmm0, [rsp + PP_P]
    subsd xmm0, [rsp + PP_R]
    divsd xmm0, [rsp + PP_R + 16]
    call .floor
    jc .out
    mov [rsp + PP_I0], eax
    movsd xmm0, [rsp + PP_P + 16]
    subsd xmm0, [rsp + PP_R]
    divsd xmm0, [rsp + PP_R + 16]
    call .ceil
    jc .out
    mov [rsp + PP_I1], eax
    movsd xmm0, [rsp + PP_P + 8]
    subsd xmm0, [rsp + PP_R + 8]
    divsd xmm0, [rsp + PP_R + 24]
    call .floor
    jc .out
    mov [rsp + PP_J0], eax
    movsd xmm0, [rsp + PP_P + 24]
    subsd xmm0, [rsp + PP_R + 8]
    divsd xmm0, [rsp + PP_R + 24]
    call .ceil
    jc .out
    mov [rsp + PP_J1], eax
    mov eax, [rsp + PP_I1]
    sub eax, [rsp + PP_I0]
    jle .out
    mov ecx, [rsp + PP_J1]
    sub ecx, [rsp + PP_J0]
    jle .out
    cmp eax, SVG_MAX_TILES
    ja .out
    cmp ecx, SVG_MAX_TILES
    ja .out
    imul eax, ecx
    cmp eax, SVG_MAX_TILES
    ja .out
    ; a layer for the paint's alpha
    cmp dword [rsp + PP_ALPHA], 255
    jae .no_layer
    mov rdi, r13
    mov esi, [rsp + PP_ALPHA]
    call ugfx_ctx_begin_layer
    mov r14, rax
    test rax, rax
    jnz .out
    mov r15d, 1
.no_layer:
    xor ecx, ecx
.keep_tb:
    mov rax, [r13 + UgfxContext_state + UgfxState_transform + rcx * 8]
    mov [rsp + PP_TB + rcx * 8], rax
    inc ecx
    cmp ecx, 6
    jb .keep_tb
    mov eax, [rsp + PP_J0]
    mov [rsp + PP_J], eax
.row:
    mov eax, [rsp + PP_J]
    cmp eax, [rsp + PP_J1]
    jge .done
    mov eax, [rsp + PP_I0]
    mov [rsp + PP_I], eax
.tile:
    mov eax, [rsp + PP_I]
    cmp eax, [rsp + PP_I1]
    jge .next_row
    ; translate(x + i w, y + j h)
    xorpd xmm7, xmm7
    movsd xmm6, [rel svg_one]
    movsd [rsp + PP_M], xmm6
    movsd [rsp + PP_M + 8], xmm7
    movsd [rsp + PP_M + 16], xmm7
    movsd [rsp + PP_M + 24], xmm6
    cvtsi2sd xmm0, dword [rsp + PP_I]
    mulsd xmm0, [rsp + PP_R + 16]
    addsd xmm0, [rsp + PP_R]
    movsd [rsp + PP_M + 32], xmm0
    cvtsi2sd xmm0, dword [rsp + PP_J]
    mulsd xmm0, [rsp + PP_R + 24]
    addsd xmm0, [rsp + PP_R + 8]
    movsd [rsp + PP_M + 40], xmm0
    mov rdi, r13
    call ugfx_ctx_save
    test rax, rax
    jnz .fail
    ; clipped to the tile
    call .tile_space
    movsd xmm0, [rsp + PP_R + 16]
    movsd xmm1, [rsp + PP_R + 24]
    xorpd xmm2, xmm2
    movsd [rsp + PP_S], xmm0
    movsd [rsp + PP_S + 8], xmm2
    movsd [rsp + PP_S + 16], xmm2
    movsd [rsp + PP_S + 24], xmm1
    movsd [rsp + PP_S + 32], xmm2
    movsd [rsp + PP_S + 40], xmm2
    mov rdi, r13
    lea rsi, [rsp + PP_S]
    call ugfx_ctx_transform
    mov rdi, r13
    lea rsi, [rbx + UgfxSvgPattern_path]
    call ugfx_ctx_clip
    test rax, rax
    jnz .tile_fail
    ; the content: fitted by the viewBox, or in bbox units, or as it is
    call .tile_space
    cmp dword [rbx + UgfxSvgPattern_has_vb], 0
    je .no_vb
    lea rdi, [rsp + PP_S]
    lea rsi, [rbx + UgfxSvgPattern_viewbox]
    movsd xmm0, [rsp + PP_R + 16]
    movsd xmm1, [rsp + PP_R + 24]
    mov edx, [rbx + UgfxSvgPattern_par]
    call svg_fit
    jmp .content_m
.no_vb:
    cmp dword [rbx + UgfxSvgPattern_content], 0
    je .content
    movsd xmm0, [r12 + UgfxSvgItem_bbox + 16]
    subsd xmm0, [r12 + UgfxSvgItem_bbox]
    movsd xmm1, [r12 + UgfxSvgItem_bbox + 24]
    subsd xmm1, [r12 + UgfxSvgItem_bbox + 8]
    xorpd xmm2, xmm2
    movsd [rsp + PP_S], xmm0
    movsd [rsp + PP_S + 8], xmm2
    movsd [rsp + PP_S + 16], xmm2
    movsd [rsp + PP_S + 24], xmm1
    movsd [rsp + PP_S + 32], xmm2
    movsd [rsp + PP_S + 40], xmm2
.content_m:
    mov rdi, r13
    lea rsi, [rsp + PP_S]
    call ugfx_ctx_transform
.content:
    mov rdi, [rbx + UgfxSvgPattern_items]
    mov esi, [rbx + UgfxSvgPattern_count]
    call svg_draw_list
    test rax, rax
    jnz .tile_fail
    mov rdi, r13
    call ugfx_ctx_restore
    inc dword [rsp + PP_I]
    jmp .tile
.next_row:
    inc dword [rsp + PP_J]
    jmp .row
.tile_fail:
    mov r14, rax
    mov rdi, r13
    call ugfx_ctx_restore
    jmp .done
.fail:
    mov r14, rax
.done:
    test r15d, r15d
    jz .out
    mov rdi, r13
    call ugfx_ctx_end_layer
    test r14, r14
    jnz .out
    mov r14, rax
.out:
    mov rax, r14
    add rsp, PP_SIZE
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
; the item's space x patternTransform x the tile's translation (frame at
;   rsp + 8)
.tile_space:
    sub rsp, 8
    mov rdi, r13
    lea rsi, [rsp + 16 + PP_TB]
    call ugfx_ctx_set_transform
    mov rdi, r13
    lea rsi, [rbx + UgfxSvgPattern_matrix]
    call ugfx_ctx_transform
    mov rdi, r13
    lea rsi, [rsp + 16 + PP_M]
    call ugfx_ctx_transform
    add rsp, 8
    ret
; xmm0 / xmm1 = a point: through PP_INV into PP_P's union (frame at rsp + 8)
.corner:
    movsd xmm2, [rsp + 8 + PP_INV]
    mulsd xmm2, xmm0
    movsd xmm3, [rsp + 8 + PP_INV + 16]
    mulsd xmm3, xmm1
    addsd xmm2, xmm3
    addsd xmm2, [rsp + 8 + PP_INV + 32]
    movsd xmm4, [rsp + 8 + PP_INV + 8]
    mulsd xmm4, xmm0
    movsd xmm3, [rsp + 8 + PP_INV + 24]
    mulsd xmm3, xmm1
    addsd xmm4, xmm3
    addsd xmm4, [rsp + 8 + PP_INV + 40]
    cmp dword [rsp + 8 + PP_ANY], 0
    jne .grow
    mov dword [rsp + 8 + PP_ANY], 1
    movsd [rsp + 8 + PP_P], xmm2
    movsd [rsp + 8 + PP_P + 8], xmm4
    movsd [rsp + 8 + PP_P + 16], xmm2
    movsd [rsp + 8 + PP_P + 24], xmm4
    ret
.grow:
    movsd xmm0, [rsp + 8 + PP_P]
    minsd xmm0, xmm2
    movsd [rsp + 8 + PP_P], xmm0
    movsd xmm0, [rsp + 8 + PP_P + 8]
    minsd xmm0, xmm4
    movsd [rsp + 8 + PP_P + 8], xmm0
    movsd xmm0, [rsp + 8 + PP_P + 16]
    maxsd xmm0, xmm2
    movsd [rsp + 8 + PP_P + 16], xmm0
    movsd xmm0, [rsp + 8 + PP_P + 24]
    maxsd xmm0, xmm4
    movsd [rsp + 8 + PP_P + 24], xmm0
    ret
; xmm0 -> eax = floor / ceil, CF set when |xmm0| is beyond 2^30 (or NaN)
.ceil:
    xorpd xmm1, xmm1
    subsd xmm1, xmm0
    movapd xmm0, xmm1
    call .floor
    jc .ceil_out
    neg eax
    clc
.ceil_out:
    ret
.floor:
    movsd xmm1, xmm0
    andpd xmm1, [rel svg_abs_mask]
    ucomisd xmm1, [rel svg_2p30]
    jp .too_far                         ; NaN
    jae .too_far
    cvttsd2si eax, xmm0
    cvtsi2sd xmm1, eax
    ucomisd xmm1, xmm0
    jbe .floored
    dec eax
.floored:
    clc
    ret
.too_far:
    stc
    ret

; -----------------------------------------------------------------------------
; svg_vertices — r12 = a shape item (its path), r15 = frame -> P_VERTS /
;   P_NVERTS: each vertex with its incoming / outgoing tangent directions.
;   A segment's start direction is toward its first distinct control point
;   (else the end), its end direction from its last; a close adds a vertex
;   at the subpath's start unless it is already there, gives that vertex
;   the first segment's outgoing direction and the start the closing
;   segment's incoming one; a segment after a close starts a new subpath.
; -----------------------------------------------------------------------------
%define VS_CUR      0                   ; f64 x, y: the current point
%define VS_START    16                  ; f64 x, y: the subpath's start
%define VS_FIRST    32                  ; u32 the subpath's first vertex
%define VS_OPEN     36                  ; u32 a subpath is open (its vertex exists)
%define VS_DS       40                  ; f64 dx, dy: a segment's start direction
%define VS_DE       56                  ; f64 dx, dy: its end direction
%define VS_PT       72                  ; f64 x, y: a closing segment's end
%define VS_SIZE     88

svg_vertices:
    push rbx
    push r13
    push r14
    push rbp
    sub rsp, VS_SIZE
    mov dword [r15 + P_NVERTS], 0
    ; room: two vertices a verb is plenty
    mov eax, [r12 + UgfxSvgItem_path + UgfxPath_verb_count]
    lea esi, [rax + rax + 2]
    imul esi, esi, VX_SIZE
    mov rax, [r15 + P_SVG]
    mov rdi, [rax + UgfxSvg_arena]
    call arena_alloc
    mov [r15 + P_VERTS], rax
    test rax, rax
    jz .nomem
    mov dword [rsp + VS_OPEN], 0
    mov dword [rsp + VS_FIRST], 0
    xorpd xmm0, xmm0
    movsd [rsp + VS_CUR], xmm0
    movsd [rsp + VS_CUR + 8], xmm0
    movsd [rsp + VS_START], xmm0
    movsd [rsp + VS_START + 8], xmm0
    mov rbx, [r12 + UgfxSvgItem_path + UgfxPath_verbs]
    mov rbp, [r12 + UgfxSvgItem_path + UgfxPath_points]
    xor r13d, r13d                      ; verb index
.verb:
    cmp r13d, [r12 + UgfxSvgItem_path + UgfxPath_verb_count]
    jae .out
    movzx eax, byte [rbx + r13]
    inc r13d
    cmp eax, PATH_VERB_MOVE
    je .move
    cmp eax, PATH_VERB_LINE
    je .line
    cmp eax, PATH_VERB_QUAD
    je .quad
    cmp eax, PATH_VERB_CUBIC
    je .cubic
    cmp eax, PATH_VERB_CLOSE
    je .close
    jmp .out                            ; (no other verbs come from SVG geometry)
.move:
    movsd xmm0, [rbp]
    movsd xmm1, [rbp + 8]
    add rbp, 16
    movsd [rsp + VS_CUR], xmm0
    movsd [rsp + VS_CUR + 8], xmm1
    movsd [rsp + VS_START], xmm0
    movsd [rsp + VS_START + 8], xmm1
    call .push_at                       ; no directions yet
    mov eax, [r15 + P_NVERTS]
    dec eax
    mov [rsp + VS_FIRST], eax
    mov dword [rsp + VS_OPEN], 1
    jmp .verb
.line:
    movsd xmm0, [rbp]
    movsd xmm1, [rbp + 8]
    subsd xmm0, [rsp + VS_CUR]
    subsd xmm1, [rsp + VS_CUR + 8]
    movsd [rsp + VS_DS], xmm0
    movsd [rsp + VS_DS + 8], xmm1
    movsd [rsp + VS_DE], xmm0
    movsd [rsp + VS_DE + 8], xmm1
    mov r14, rbp                        ; the end point
    add rbp, 16
    call .seg
    jmp .verb
.quad:
    ; start: c - cur, else p - cur; end: p - c, else p - cur
    lea r14, [rbp + 16]
    movsd xmm0, [rbp]
    movsd xmm1, [rbp + 8]
    subsd xmm0, [rsp + VS_CUR]
    subsd xmm1, [rsp + VS_CUR + 8]
    call .zero
    jne .quad_ds
    movsd xmm0, [r14]
    movsd xmm1, [r14 + 8]
    subsd xmm0, [rsp + VS_CUR]
    subsd xmm1, [rsp + VS_CUR + 8]
.quad_ds:
    movsd [rsp + VS_DS], xmm0
    movsd [rsp + VS_DS + 8], xmm1
    movsd xmm0, [r14]
    movsd xmm1, [r14 + 8]
    subsd xmm0, [rbp]
    subsd xmm1, [rbp + 8]
    call .zero
    jne .quad_de
    movsd xmm0, [r14]
    movsd xmm1, [r14 + 8]
    subsd xmm0, [rsp + VS_CUR]
    subsd xmm1, [rsp + VS_CUR + 8]
.quad_de:
    movsd [rsp + VS_DE], xmm0
    movsd [rsp + VS_DE + 8], xmm1
    add rbp, 32
    call .seg
    jmp .verb
.cubic:
    lea r14, [rbp + 32]
    ; start: c1 - cur, c2 - cur, p - cur
    movsd xmm0, [rbp]
    movsd xmm1, [rbp + 8]
    subsd xmm0, [rsp + VS_CUR]
    subsd xmm1, [rsp + VS_CUR + 8]
    call .zero
    jne .cubic_ds
    movsd xmm0, [rbp + 16]
    movsd xmm1, [rbp + 24]
    subsd xmm0, [rsp + VS_CUR]
    subsd xmm1, [rsp + VS_CUR + 8]
    call .zero
    jne .cubic_ds
    movsd xmm0, [r14]
    movsd xmm1, [r14 + 8]
    subsd xmm0, [rsp + VS_CUR]
    subsd xmm1, [rsp + VS_CUR + 8]
.cubic_ds:
    movsd [rsp + VS_DS], xmm0
    movsd [rsp + VS_DS + 8], xmm1
    ; end: p - c2, p - c1, p - cur
    movsd xmm0, [r14]
    movsd xmm1, [r14 + 8]
    subsd xmm0, [rbp + 16]
    subsd xmm1, [rbp + 24]
    call .zero
    jne .cubic_de
    movsd xmm0, [r14]
    movsd xmm1, [r14 + 8]
    subsd xmm0, [rbp]
    subsd xmm1, [rbp + 8]
    call .zero
    jne .cubic_de
    movsd xmm0, [r14]
    movsd xmm1, [r14 + 8]
    subsd xmm0, [rsp + VS_CUR]
    subsd xmm1, [rsp + VS_CUR + 8]
.cubic_de:
    movsd [rsp + VS_DE], xmm0
    movsd [rsp + VS_DE + 8], xmm1
    add rbp, 48
    call .seg
    jmp .verb
.close:
    cmp dword [rsp + VS_OPEN], 0
    je .verb
    movsd xmm0, [rsp + VS_START]
    movsd xmm1, [rsp + VS_START + 8]
    subsd xmm0, [rsp + VS_CUR]
    subsd xmm1, [rsp + VS_CUR + 8]
    call .zero
    je .closed_here
    ; a closing line, its vertex at the start
    movsd [rsp + VS_DS], xmm0
    movsd [rsp + VS_DS + 8], xmm1
    movsd [rsp + VS_DE], xmm0
    movsd [rsp + VS_DE + 8], xmm1
    movsd xmm0, [rsp + VS_START]
    movsd xmm1, [rsp + VS_START + 8]
    movsd [rsp + VS_PT], xmm0
    movsd [rsp + VS_PT + 8], xmm1
    lea r14, [rsp + VS_PT]
    call .seg
.closed_here:
    ; the closing vertex leaves along the first segment; the start comes in
    ; along the closing one
    call .last
    mov ecx, [rsp + VS_FIRST]
    imul rcx, rcx, VX_SIZE
    add rcx, [r15 + P_VERTS]
    test dword [rcx + VX_FLAGS], 2
    jz .no_first_out
    movsd xmm0, [rcx + VX_OUT]
    movsd [rax + VX_OUT], xmm0
    or dword [rax + VX_FLAGS], 2
.no_first_out:
    cmp rax, rcx
    je .no_close_in
    test dword [rax + VX_FLAGS], 1
    jz .no_close_in
    movsd xmm0, [rax + VX_IN]
    movsd [rcx + VX_IN], xmm0
    or dword [rcx + VX_FLAGS], 1
.no_close_in:
    mov dword [rsp + VS_OPEN], 0
    movsd xmm0, [rsp + VS_START]
    movsd xmm1, [rsp + VS_START + 8]
    movsd [rsp + VS_CUR], xmm0
    movsd [rsp + VS_CUR + 8], xmm1
    jmp .verb
.nomem:
    mov dword [r15 + P_ERR], -(ENOMEM)
.out:
    add rsp, VS_SIZE
    pop rbp
    pop r14
    pop r13
    pop rbx
    ret
; a segment ending at r14 with VS_DS / VS_DE: the last vertex leaves along
;   it (unless it already has a way out), a new vertex comes in along it;
;   after a close it first opens a subpath at the current point (frame at
;   rsp + 8)
.seg:
    sub rsp, 8                          ; (frame at rsp + 16)
    cmp dword [rsp + 16 + VS_OPEN], 0
    jne .seg_open
    movsd xmm0, [rsp + 16 + VS_CUR]
    movsd xmm1, [rsp + 16 + VS_CUR + 8]
    movsd [rsp + 16 + VS_START], xmm0
    movsd [rsp + 16 + VS_START + 8], xmm1
    call .push_at
    mov eax, [r15 + P_NVERTS]
    dec eax
    mov [rsp + 16 + VS_FIRST], eax
    mov dword [rsp + 16 + VS_OPEN], 1
.seg_open:
    call .last
    test dword [rax + VX_FLAGS], 2
    jnz .seg_in
    movsd xmm0, [rsp + 16 + VS_DS + 8]
    movsd xmm1, [rsp + 16 + VS_DS]
    call umath_atan2_f64
    call .last
    movsd [rax + VX_OUT], xmm0
    or dword [rax + VX_FLAGS], 2
.seg_in:
    movsd xmm0, [r14]
    movsd xmm1, [r14 + 8]
    movsd [rsp + 16 + VS_CUR], xmm0
    movsd [rsp + 16 + VS_CUR + 8], xmm1
    call .push_at
    movsd xmm0, [rsp + 16 + VS_DE + 8]
    movsd xmm1, [rsp + 16 + VS_DE]
    call umath_atan2_f64
    call .last
    movsd [rax + VX_IN], xmm0
    or dword [rax + VX_FLAGS], 1
    add rsp, 8
    ret
; (xmm0, xmm1) -> ZF = 1 when both are 0
.zero:
    xorpd xmm2, xmm2
    ucomisd xmm0, xmm2
    jne .zero_out
    jp .zero_out
    ucomisd xmm1, xmm2
.zero_out:
    ret
; rax -> the last vertex
.last:
    mov eax, [r15 + P_NVERTS]
    dec eax
    imul rax, rax, VX_SIZE
    add rax, [r15 + P_VERTS]
    ret
; xmm0, xmm1 = a point: a vertex there, no directions
.push_at:
    mov eax, [r15 + P_NVERTS]
    inc dword [r15 + P_NVERTS]
    imul rax, rax, VX_SIZE
    add rax, [r15 + P_VERTS]
    movsd [rax + VX_X], xmm0
    movsd [rax + VX_Y], xmm1
    mov dword [rax + VX_FLAGS], 0
    ret

; -----------------------------------------------------------------------------
; svg_markers — r15 = frame (P_VERTS / P_NVERTS), rbx = the shape's state:
;   marker items at its vertices - marker-start at the first, marker-mid
;   at the others, marker-end at the last (a lone vertex has both ends)
; -----------------------------------------------------------------------------
%define MK_REC      0                   ; UgfxSvgMarker*[3]
%define MK_M        24                  ; f64[6]
%define MK_T        72                  ; f64[6]
%define MK_I        120                 ; u32
%define MK_A        128                 ; f64 the marker's angle
%define MK_SIZE     144

svg_markers:
    push r12
    push r13
    push r14
    sub rsp, MK_SIZE
    xor r12d, r12d
.compile:
    mov qword [rsp + MK_REC + r12 * 8], 0
    mov eax, r12d
    shl eax, 4
    mov rdi, [rbx + S_MARKERS + rax]
    mov rsi, [rbx + S_MARKERS + rax + 8]
    test rdi, rdi
    jz .next_rec
    call svg_url_ref
    test rax, rax
    jz .next_rec
    mov rsi, rax
    mov ecx, K_MARKER
    call svg_compile
    mov [rsp + MK_REC + r12 * 8], rax
.next_rec:
    inc r12d
    cmp r12d, 3
    jb .compile
    mov r13d, [r15 + P_NVERTS]
    test r13d, r13d
    jz .out
    ; start, mids, end
    xor edx, edx
    mov rcx, [rsp + MK_REC]
    mov r8d, 1
    call .emit
    mov dword [rsp + MK_I], 1
.mid:
    mov edx, [rsp + MK_I]
    lea eax, [r13 - 1]
    cmp edx, eax
    jae .end
    mov rcx, [rsp + MK_REC + 8]
    xor r8d, r8d
    call .emit
    inc dword [rsp + MK_I]
    jmp .mid
.end:
    lea edx, [r13 - 1]
    mov rcx, [rsp + MK_REC + 16]
    xor r8d, r8d
    call .emit
.out:
    add rsp, MK_SIZE
    pop r14
    pop r13
    pop r12
    ret
; edx = a vertex, rcx = its marker (0: none), r8d = 1 for the start one
;   (frame at rsp + 8)
.emit:
    sub rsp, 8                          ; (frame at rsp + 16)
    mov r14, rcx
    test r14, r14
    jz .emit_out
    cmp dword [r14 + UgfxSvgMarker_count], 0
    je .emit_out
    xorpd xmm0, xmm0
    ucomisd xmm0, [r14 + UgfxSvgMarker_size]
    jae .emit_out
    ucomisd xmm0, [r14 + UgfxSvgMarker_size + 8]
    jae .emit_out
    imul r12, rdx, VX_SIZE
    add r12, [r15 + P_VERTS]            ; the vertex
    ; the angle: the bisector of in and out, else either, else 0
    xorpd xmm0, xmm0
    mov eax, [r12 + VX_FLAGS]
    cmp eax, 3
    je .bisect
    cmp eax, 1
    je .in
    cmp eax, 2
    jne .oriented
    movsd xmm0, [r12 + VX_OUT]
    jmp .oriented
.in:
    movsd xmm0, [r12 + VX_IN]
    jmp .oriented
.bisect:
    movsd xmm1, [r12 + VX_OUT]
    subsd xmm1, [r12 + VX_IN]           ; d = out - in, into [-pi, pi]
    ucomisd xmm1, [rel svg_pi]
    jbe .not_over
    subsd xmm1, [rel svg_two_pi]
    jmp .halved
.not_over:
    movsd xmm2, [rel svg_pi]
    xorpd xmm3, xmm3
    subsd xmm3, xmm2
    ucomisd xmm3, xmm1
    jbe .halved
    addsd xmm1, [rel svg_two_pi]
.halved:
    mulsd xmm1, [rel svg_half]
    movsd xmm0, [r12 + VX_IN]
    addsd xmm0, xmm1
.oriented:
    mov eax, [r14 + UgfxSvgMarker_orient]
    test eax, eax
    jnz .auto
    movsd xmm0, [r14 + UgfxSvgMarker_angle]
    jmp .angled
.auto:
    cmp eax, 2
    jne .angled
    test r8d, r8d
    jz .angled
    addsd xmm0, [rel svg_pi]            ; auto-start-reverse
.angled:
    movsd [rsp + 16 + MK_A], xmm0
    ; M = the shape's x translate(v) x rotate(a) x scale(k) x translate(-ref)
    xor ecx, ecx
.m:
    mov rax, [rbx + S_M + rcx * 8]
    mov [rsp + 16 + MK_M + rcx * 8], rax
    inc ecx
    cmp ecx, 6
    jb .m
    lea rdi, [rsp + 16 + MK_T]
    movsd xmm0, [r12 + VX_X]
    movsd xmm1, [r12 + VX_Y]
    call umath_affine2_translate
    call .apply
    lea rdi, [rsp + 16 + MK_T]
    movsd xmm0, [rsp + 16 + MK_A]
    call umath_affine2_rotate
    call .apply
    movsd xmm0, [rel svg_one]
    cmp dword [r14 + UgfxSvgMarker_units], 0
    jne .scale
    movsd xmm0, [rbx + S_SW]
.scale:
    movapd xmm1, xmm0
    lea rdi, [rsp + 16 + MK_T]
    call umath_affine2_scale
    call .apply
    xorpd xmm0, xmm0
    subsd xmm0, [r14 + UgfxSvgMarker_ref]
    xorpd xmm1, xmm1
    subsd xmm1, [r14 + UgfxSvgMarker_ref + 8]
    lea rdi, [rsp + 16 + MK_T]
    call umath_affine2_translate
    call .apply
    mov ecx, 1
    call svg_item_room
    test rax, rax
    jz .emit_nomem
    mov dword [rax + UgfxSvgItem_kind], UGFX_SVG_MARKER
    mov [rax + UgfxSvgItem_marker], r14
    xor ecx, ecx
.copy:
    mov rdx, [rsp + 16 + MK_M + rcx * 8]
    mov [rax + UgfxSvgItem_matrix + rcx * 8], rdx
    inc ecx
    cmp ecx, 6
    jb .copy
    mov rax, [r15 + P_SVG]
    inc dword [rax + UgfxSvg_count]
    jmp .emit_out
.emit_nomem:
    mov dword [r15 + P_ERR], -(ENOMEM)
.emit_out:
    add rsp, 8
    ret
; MK_M = MK_M x MK_T (frame at rsp + 24: called from .emit)
.apply:
    sub rsp, 8
    lea rdi, [rsp + 32 + MK_M]
    mov rsi, rdi
    lea rdx, [rsp + 32 + MK_T]
    call umath_affine2_multiply
    add rsp, 8
    ret

; -----------------------------------------------------------------------------
; svg_marker_attrs — r13 = a new UgfxSvgMarker (content compiled), the
;   marker's tag through svg_compile's frame, r15 = frame, rbx = the
;   referencing state: markerUnits, refX / refY, markerWidth / Height
;   (default 3), orient, viewBox, preserveAspectRatio, overflow
; -----------------------------------------------------------------------------
%define MA_RAW      0                   ; refX, refY, markerWidth, markerHeight as written
%define MA_VB       64                  ; f64[4]
%define MA_SIZE     104

svg_marker_attrs:
    push r12
    push r14
    sub rsp, MA_SIZE
    %define MA_CC (8 + MA_SIZE + 16)    ; svg_compile's frame, from here
    mov dword [r13 + UgfxSvgMarker_units], 0
    mov dword [r13 + UgfxSvgMarker_orient], 0
    mov dword [r13 + UgfxSvgMarker_clip], 1
    mov dword [r13 + UgfxSvgMarker_has_vb], 0
    xorpd xmm0, xmm0
    movsd [r13 + UgfxSvgMarker_angle], xmm0
    lea rax, [rel svg_zero_text]
    mov [rsp + MA_RAW], rax
    mov [rsp + MA_RAW + 16], rax
    inc rax
    mov [rsp + MA_RAW + 8], rax
    mov [rsp + MA_RAW + 24], rax
    lea rax, [rel svg_three_text]
    mov [rsp + MA_RAW + 32], rax
    mov [rsp + MA_RAW + 48], rax
    inc rax
    mov [rsp + MA_RAW + 40], rax
    mov [rsp + MA_RAW + 56], rax
    mov r12d, PAR_DEFAULT
.attr:
    lea rdi, [rsp + MA_CC + CC_XML]
    lea rsi, [rsp + MA_CC + CC_ATTR]
    call ugfx_svg_xml_attr
    test eax, eax
    jz .sizes
    mov rdi, [rsp + MA_CC + CC_ATTR + UgfxSvgAttr_name]
    mov rsi, [rsp + MA_CC + CC_ATTR + UgfxSvgAttr_name_end]
    lea rdx, [rel svg_marker_words]
    call ugfx_svg_lookup
    test eax, eax
    jle .attr
    mov r14d, eax
    mov rdi, [rsp + MA_CC + CC_ATTR + UgfxSvgAttr_val]
    mov rsi, [rsp + MA_CC + CC_ATTR + UgfxSvgAttr_val_end]
    cmp r14d, 2
    jb .units
    cmp r14d, 5
    ja .other
    lea eax, [r14 - 2]
    shl eax, 4
    mov [rsp + MA_RAW + rax], rdi
    mov [rsp + MA_RAW + rax + 8], rsi
    jmp .attr
.units:
    call ugfx_svg_trim
    lea rdx, [rel svg_word_user]
    mov ecx, 14
    call svg_word
    sete al
    movzx eax, al
    mov [r13 + UgfxSvgMarker_units], eax
    jmp .attr
.other:
    cmp r14d, 6
    je .orient
    cmp r14d, 7
    je .viewbox
    cmp r14d, 8
    je .par
    ; overflow: visible / auto draw outside the viewport
    call ugfx_svg_trim
    lea rdx, [rel svg_overflow_words]
    call ugfx_svg_lookup
    xor ecx, ecx
    cmp eax, 1
    setne cl
    mov [r13 + UgfxSvgMarker_clip], ecx
    jmp .attr
.par:
    call svg_par
    mov r12d, eax
    jmp .attr
.orient:
    call ugfx_svg_trim
    push rdi
    push rsi
    lea rdx, [rel svg_orient_words]
    call ugfx_svg_lookup
    pop rsi
    pop rdi
    cmp eax, 0
    jg .orient_word
    mov dword [r13 + UgfxSvgMarker_orient], 0
    call ugfx_svg_number
    xorpd xmm1, xmm1
    test rax, rax
    jz .orient_angle
    mulsd xmm0, [rel svg_deg]
    movapd xmm1, xmm0
.orient_angle:
    movsd [r13 + UgfxSvgMarker_angle], xmm1
    jmp .attr
.orient_word:
    mov [r13 + UgfxSvgMarker_orient], eax
    jmp .attr
.viewbox:
    mov r14, rdi
    mov [rsp + MA_VB + 32], rsi         ; (the end, kept)
    xor ecx, ecx
    mov dword [r13 + UgfxSvgMarker_has_vb], 0
.vb_number:
    cmp ecx, 4
    jae .vb_check
    push rcx
    sub rsp, 8
    mov rdi, r14
    mov rsi, [rsp + 16 + MA_VB + 32]
    call ugfx_svg_number
    add rsp, 8
    pop rcx
    test rax, rax
    jz .attr
    mov r14, rax
    movsd [rsp + MA_VB + rcx * 8], xmm0
    inc ecx
    jmp .vb_number
.vb_check:
    xorpd xmm1, xmm1
    movsd xmm0, [rsp + MA_VB + 16]
    ucomisd xmm0, xmm1
    jbe .attr
    movsd xmm0, [rsp + MA_VB + 24]
    ucomisd xmm0, xmm1
    jbe .attr
    mov dword [r13 + UgfxSvgMarker_has_vb], 1
    jmp .attr
.sizes:
    ; refX, refY, markerWidth, markerHeight: lengths (0 if invalid)
    xor r14d, r14d
.size_value:
    cmp r14d, 4
    jae .fit
    mov eax, r14d
    shl eax, 4
    mov rdi, [rsp + MA_RAW + rax]
    mov rsi, [rsp + MA_RAW + rax + 8]
    mov edx, r14d
    and edx, 1
    call svg_length
    test rax, rax
    jnz .size_set
    xorpd xmm0, xmm0
.size_set:
    movsd [r13 + UgfxSvgMarker_ref + r14 * 8], xmm0
    inc r14d
    jmp .size_value
.fit:
    ; the viewBox into markerWidth x markerHeight; refX / refY through it
    lea rdi, [r13 + UgfxSvgMarker_vbm]
    call umath_affine2_identity
    cmp dword [r13 + UgfxSvgMarker_has_vb], 0
    je .square
    xorpd xmm2, xmm2
    movsd xmm0, [r13 + UgfxSvgMarker_size]
    ucomisd xmm0, xmm2
    jbe .square
    movsd xmm1, [r13 + UgfxSvgMarker_size + 8]
    ucomisd xmm1, xmm2
    jbe .square
    lea rdi, [r13 + UgfxSvgMarker_vbm]
    lea rsi, [rsp + MA_VB]
    mov edx, r12d
    call svg_fit
    movsd xmm0, [r13 + UgfxSvgMarker_vbm]
    mulsd xmm0, [r13 + UgfxSvgMarker_ref]
    addsd xmm0, [r13 + UgfxSvgMarker_vbm + 32]
    movsd [r13 + UgfxSvgMarker_ref], xmm0
    movsd xmm0, [r13 + UgfxSvgMarker_vbm + 24]
    mulsd xmm0, [r13 + UgfxSvgMarker_ref + 8]
    addsd xmm0, [r13 + UgfxSvgMarker_vbm + 40]
    movsd [r13 + UgfxSvgMarker_ref + 8], xmm0
.square:
    lea rdi, [r13 + UgfxSvgMarker_path]
    mov rax, [r15 + P_SVG]
    mov rsi, [rax + UgfxSvg_arena]
    call ugfx_path_init
    test rax, rax
    jnz .nomem
    lea rdi, [r13 + UgfxSvgMarker_path]
    xorpd xmm0, xmm0
    xorpd xmm1, xmm1
    movsd xmm2, [rel svg_one]
    movapd xmm3, xmm2
    call ugfx_path_add_rect
    test rax, rax
    jz .out
.nomem:
    mov dword [r15 + P_ERR], -(ENOMEM)
.out:
    add rsp, MA_SIZE
    pop r14
    pop r12
    ret

; -----------------------------------------------------------------------------
; svg_image — r15 = frame, rbx = state: an image item from the href through
;   UgfxSvg_image_fn, placed by preserveAspectRatio
; -----------------------------------------------------------------------------
%define IM_VB       0                   ; f64[4] (0, 0, image w, h)
%define IM_M        32                  ; f64[6] the fit
%define IM_BOX      80                  ; f64 x, y, w, h
%define IM_PIX      112
%define IM_SIZE     120

svg_image:
    push r12
    push r13
    push r14
    sub rsp, IM_SIZE
    cmp dword [rbx + S_HIDDEN], 0
    jne .out
    mov r14, [r15 + P_SVG]
    cmp qword [r14 + UgfxSvg_image_fn], 0
    je .out
    mov rdi, [r15 + P_HREF_RAW]
    test rdi, rdi
    jz .out
    mov rsi, [r15 + P_HREF_RAW_END]
    ; a data: URI's bytes, else the reference
    mov r12, rdi
    mov r13, rsi
    call svg_data_uri
    mov ecx, 0
    test rax, rax
    jnz .call
    mov rax, r12
    mov rdx, r13
    sub rdx, r12
    mov ecx, 1
.call:
    mov rdi, [r14 + UgfxSvg_image_user]
    mov rsi, rax
    mov r8, [r14 + UgfxSvg_arena]
    call [r14 + UgfxSvg_image_fn]
    test rax, rax
    jle .out
    mov [rsp + IM_PIX], rax
    ; the box: x, y, width / height (default: the image's own)
    xorpd xmm0, xmm0
    movsd [rsp + IM_VB], xmm0
    movsd [rsp + IM_VB + 8], xmm0
    cvtsi2sd xmm0, qword [rax + PixBuf_width]
    movsd [rsp + IM_VB + 16], xmm0
    cvtsi2sd xmm1, qword [rax + PixBuf_height]
    movsd [rsp + IM_VB + 24], xmm1
    xorpd xmm2, xmm2
    ucomisd xmm0, xmm2
    jbe .out
    ucomisd xmm1, xmm2
    jbe .out
    movsd xmm2, [r15 + P_G + G_X * 8]
    movsd [rsp + IM_BOX], xmm2
    movsd xmm2, [r15 + P_G + G_Y * 8]
    movsd [rsp + IM_BOX + 8], xmm2
    test dword [r15 + P_HAVE], 1 << G_W
    jz .width
    movsd xmm0, [r15 + P_G + G_W * 8]
.width:
    test dword [r15 + P_HAVE], 1 << G_H
    jz .height
    movsd xmm1, [r15 + P_G + G_H * 8]
.height:
    movsd [rsp + IM_BOX + 16], xmm0
    movsd [rsp + IM_BOX + 24], xmm1
    xorpd xmm2, xmm2
    ucomisd xmm0, xmm2
    jbe .out
    ucomisd xmm1, xmm2
    jbe .out
    lea rdi, [rsp + IM_M]
    lea rsi, [rsp + IM_VB]
    mov edx, [r15 + P_PAR]
    call svg_fit
    ; the item
    mov ecx, 1
    call svg_item_room
    test rax, rax
    jz .nomem
    mov r12, rax
    mov dword [r12 + UgfxSvgItem_kind], UGFX_SVG_IMAGE
    xor ecx, ecx
.m:
    mov rax, [rbx + S_M + rcx * 8]
    mov [r12 + UgfxSvgItem_matrix + rcx * 8], rax
    inc ecx
    cmp ecx, 6
    jb .m
    mov rax, [rsp + IM_PIX]
    mov [r12 + UgfxSvgItem_fill_paint], rax
    ; drawn at x + tx, y + ty, w sx, h sy
    movsd xmm0, [rsp + IM_BOX]
    addsd xmm0, [rsp + IM_M + 32]
    movsd [r12 + UgfxSvgItem_bbox], xmm0
    movsd xmm0, [rsp + IM_BOX + 8]
    addsd xmm0, [rsp + IM_M + 40]
    movsd [r12 + UgfxSvgItem_bbox + 8], xmm0
    movsd xmm0, [rsp + IM_VB + 16]
    mulsd xmm0, [rsp + IM_M]
    movsd [r12 + UgfxSvgItem_bbox + 16], xmm0
    movsd xmm0, [rsp + IM_VB + 24]
    mulsd xmm0, [rsp + IM_M + 24]
    movsd [r12 + UgfxSvgItem_bbox + 24], xmm0
    ; slice: clipped to the box
    mov eax, [r15 + P_PAR]
    xor ecx, ecx
    test eax, 0x100
    jz .clip_flag
    test al, al
    setnz cl
.clip_flag:
    mov [r12 + UgfxSvgItem_order], ecx
    mov edi, 0xFF000000
    movsd xmm0, [rel svg_one]
    call svg_bake_alpha
    mov [r12 + UgfxSvgItem_fill], eax
    lea rdi, [r12 + UgfxSvgItem_path]
    mov rsi, [r14 + UgfxSvg_arena]
    call ugfx_path_init
    test rax, rax
    jnz .nomem
    lea rdi, [r12 + UgfxSvgItem_path]
    movsd xmm0, [rsp + IM_BOX]
    movsd xmm1, [rsp + IM_BOX + 8]
    movsd xmm2, [rsp + IM_BOX + 16]
    movsd xmm3, [rsp + IM_BOX + 24]
    call ugfx_path_add_rect
    test rax, rax
    jnz .nomem
    inc dword [r14 + UgfxSvg_count]
    jmp .out
.nomem:
    mov dword [r15 + P_ERR], -(ENOMEM)
.out:
    add rsp, IM_SIZE
    pop r14
    pop r13
    pop r12
    ret

; -----------------------------------------------------------------------------
; svg_data_uri — rdi / rsi = an href, r15 = frame -> rax = the bytes of a
;   data: URI (decoded: base64 with ;base64, else percent-encoding), rdx =
;   their length; rax = 0 when it is not one (or out of memory)
; -----------------------------------------------------------------------------
svg_data_uri:
    push r12
    push r13
    push r14
    xor eax, eax
    mov rcx, rsi
    sub rcx, rdi
    cmp rcx, 5
    jb .out
    mov ecx, [rdi]
    or ecx, 0x20202020
    cmp ecx, 'data'
    jne .out
    cmp byte [rdi + 4], ':'
    jne .out
    ; the payload after ','; ";base64" just before it
    mov r12, rdi
.comma:
    cmp r12, rsi
    jae .none
    cmp byte [r12], ','
    je .have_comma
    inc r12
    jmp .comma
.have_comma:
    xor r14d, r14d                      ; base64?
    lea rax, [r12 - 7]
    cmp rax, rdi
    jb .payload
    mov ecx, [rax]
    or ecx, 0x20202020
    cmp ecx, ';bas'
    jne .payload
    mov ecx, [rax + 3]
    or ecx, 0x20202020
    cmp ecx, 'se64'
    jne .payload
    mov r14d, 1
.payload:
    inc r12
    mov r13, rsi
    mov rax, [r15 + P_SVG]
    mov rdi, [rax + UgfxSvg_arena]
    mov rsi, r13
    sub rsi, r12
    inc rsi
    call arena_alloc
    test rax, rax
    jz .none
    mov rdi, rax                        ; out
    mov rdx, rax                        ; start
    test r14d, r14d
    jnz .base64
.percent:
    cmp r12, r13
    jae .done
    movzx ecx, byte [r12]
    inc r12
    cmp cl, '%'
    jne .byte
    lea r8, [r12 + 2]
    cmp r8, r13
    ja .byte
    movzx eax, byte [r12]
    call .hex
    js .byte
    mov r9d, eax
    movzx eax, byte [r12 + 1]
    call .hex
    js .byte
    shl r9d, 4
    or eax, r9d
    mov ecx, eax
    add r12, 2
.byte:
    mov [rdi], cl
    inc rdi
    jmp .percent
.base64:
    xor r8d, r8d                        ; bits
    xor r9d, r9d                        ; bit count
.b64:
    cmp r12, r13
    jae .done
    movzx eax, byte [r12]
    inc r12
    cmp al, '='
    je .done
    cmp al, ' '
    jbe .b64                            ; whitespace
    call .b64_value
    js .done                            ; not base64: stop
    shl r8d, 6
    or r8d, eax
    add r9d, 6
    cmp r9d, 8
    jb .b64
    sub r9d, 8
    mov eax, r8d
    mov ecx, r9d
    shr eax, cl
    mov [rdi], al
    inc rdi
    mov eax, 1
    shl eax, cl
    dec eax
    and r8d, eax                        ; keep the bits not yet used
    jmp .b64
.done:
    mov rax, rdx
    mov rdx, rdi
    sub rdx, rax
    jmp .out
.none:
    xor eax, eax
.out:
    pop r14
    pop r13
    pop r12
    ret
; al = a hex digit -> eax = its value, SF set when it is not one
.hex:
    sub eax, '0'
    cmp eax, 9
    jbe .hex_ok
    or eax, 0x20
    sub eax, 'a' - '0' - 10
    cmp eax, 10
    jb .hex_bad
    cmp eax, 15
    jbe .hex_ok
.hex_bad:
    mov eax, -1
    test eax, eax
    ret
.hex_ok:
    test eax, eax
    ret
; al = a base64 character -> eax = its value, SF set when it is not one
.b64_value:
    cmp al, 'A'
    jb .b64_digit
    cmp al, 'Z'
    ja .b64_lower
    sub eax, 'A'
    ret
.b64_lower:
    cmp al, 'a'
    jb .b64_bad
    cmp al, 'z'
    ja .b64_bad
    sub eax, 'a' - 26
    ret
.b64_digit:
    cmp al, '0'
    jb .b64_sign
    cmp al, '9'
    ja .b64_bad
    sub eax, '0' - 52
    ret
.b64_sign:
    cmp al, '+'
    jne .b64_slash
    mov eax, 62
    test eax, eax
    ret
.b64_slash:
    cmp al, '/'
    jne .b64_bad
    mov eax, 63
    test eax, eax
    ret
.b64_bad:
    mov eax, -1
    test eax, eax
    ret

; rsi = a BEGIN item, rdi = where its END goes: kind END, everything else
;   (alpha, clip, mask, matrix, bbox) as the BEGIN has it
svg_end_from:
    push rdi
    mov ecx, UgfxSvgItem_SIZE
    rep movsb
    pop rdi
    mov dword [rdi + UgfxSvgItem_kind], UGFX_SVG_END
    ret

; -----------------------------------------------------------------------------
; svg_clip_ref / svg_mask_ref — r15 = frame, rbx = state -> rax = the
;   element's compiled clip-path / mask (0: none, not a clipPath / mask,
;   or inside a clip's content)
; -----------------------------------------------------------------------------
svg_clip_ref:
    mov rdi, [r15 + P_CLIP]
    mov rsi, [r15 + P_CLIP_END]
    mov ecx, K_CLIP
    jmp svg_ref
svg_mask_ref:
    mov rdi, [r15 + P_MASK]
    mov rsi, [r15 + P_MASK_END]
    mov ecx, K_MASK
svg_ref:
    push r12
    mov r12d, ecx
    xor eax, eax
    cmp dword [r15 + P_CLIPMODE], 0
    jne .out
    test rdi, rdi
    jz .out
    call svg_url_ref
    test rax, rax
    jz .out
    mov rsi, rax
    mov ecx, r12d
    call svg_compile
.out:
    pop r12
    ret

; rdi / rsi = a trimmed value -> rax = the id of url(#id) (0: not one), rdx
;   = its end
svg_url_ref:
    xor eax, eax
    mov rcx, rsi
    sub rcx, rdi
    cmp rcx, 4
    jb .no
    mov ecx, [rdi]
    or ecx, 0x20202020
    cmp ecx, 'url('
    jne .no
    jmp svg_url
.no:
    ret

; -----------------------------------------------------------------------------
; svg_compile — rsi / rdx = an id, ecx = K_CLIP / K_MASK, r15 = frame, rbx =
;   the referencing element's state -> rax = UgfxSvgClip* / UgfxSvgMask*
;   (0: no such clipPath / mask, too deep, or out of memory). Its subtree is
;   walked from a fresh state (the defaults, with the element's viewport
;   and font-size) into an item list of its own - a clip's in clip mode,
;   geometry only - with every frame field kept.
; -----------------------------------------------------------------------------
; (svg_compile's frame: CC_* with the parser frame's layout, above)

svg_compile:
    push r12
    push r13
    push r14
    push rbp
    sub rsp, CC_SIZE
    mov [rsp + CC_KIND], ecx
    xor r13d, r13d
    cmp dword [r15 + P_COMPILE], SVG_MAX_CLIPS
    jae .out
    mov eax, [r15 + P_DEPTH]
    cmp eax, SVG_MAX_DEPTH
    jae .out
    lea rdi, [r15 + P_DEFS]
    call ugfx_svg_defs_id
    test rax, rax
    jz .out
    mov r12, rax                        ; its '<'
    ; the right element: clipPath or mask
    mov rcx, [r15 + P_XML + UgfxSvgXml_end]
    lea rdx, [r12 + 10]
    cmp rdx, rcx
    ja .out
    cmp dword [rsp + CC_KIND], K_MASK
    je .want_mask
    cmp dword [rsp + CC_KIND], K_PATTERN
    je .want_pattern
    cmp dword [rsp + CC_KIND], K_MARKER
    je .want_marker
    mov rdx, 'clipPath'
    cmp [r12 + 1], rdx
    jne .out
    movzx eax, byte [r12 + 9]
    mov esi, UgfxSvgClip_SIZE
    jmp .name_end
.want_mask:
    cmp dword [r12 + 1], 'mask'
    jne .out
    movzx eax, byte [r12 + 5]
    mov esi, UgfxSvgMask_SIZE
    jmp .name_end
.want_pattern:
    cmp dword [r12 + 1], 'patt'
    jne .out
    cmp dword [r12 + 4], 'tern'
    jne .out
    movzx eax, byte [r12 + 8]
    mov esi, UgfxSvgPattern_SIZE
    jmp .name_end
.want_marker:
    cmp dword [r12 + 1], 'mark'
    jne .out
    cmp word [r12 + 5], 'er'
    jne .out
    movzx eax, byte [r12 + 7]
    mov esi, UgfxSvgMarker_SIZE
.name_end:
    cmp al, '>'
    je .is_it
    cmp al, '/'
    je .is_it
    cmp al, ' '
    ja .out
.is_it:
    mov rax, [r15 + P_SVG]
    mov rdi, [rax + UgfxSvg_arena]
    call arena_alloc
    test rax, rax
    jz .nomem
    mov r13, rax
    mov qword [r13 + UgfxSvgClip_items], 0
    mov dword [r13 + UgfxSvgClip_count], 0
    mov dword [r13 + UgfxSvgClip_units], 0
    mov qword [r13 + UgfxSvgClip_next], 0   ; (a mask's content units and mode: 0)
    inc dword [r15 + P_COMPILE]
    ; keep the frame and the main list
    lea rdi, [rsp + CC_FRAME]
    mov rsi, r15
    mov ecx, P_SIZE
    rep movsb
    xor eax, eax
    cmp dword [rsp + CC_KIND], K_CLIP
    sete al
    mov [r15 + P_CLIPMODE], eax         ; a clip's content: geometry only
    mov rax, [r15 + P_SVG]
    mov rcx, [rax + UgfxSvg_items]
    mov [rsp + CC_ITEMS], rcx
    mov ecx, [rax + UgfxSvg_count]
    mov [rsp + CC_COUNT], ecx
    mov ecx, [rax + UgfxSvg_cap]
    mov [rsp + CC_CAP], ecx
    mov qword [rax + UgfxSvg_items], 0
    mov dword [rax + UgfxSvg_count], 0
    mov dword [rax + UgfxSvg_cap], 0
    ; a fresh state above this element's
    mov eax, [r15 + P_DEPTH]
    inc eax
    imul rdi, rax, S_SIZE
    add rdi, [r15 + P_STACK]
    mov rbp, rdi
    mov rsi, [r15 + P_STACK]
    mov ecx, S_SIZE
    rep movsb
    movsd xmm0, [rbx + S_VW]
    movsd [rbp + S_VW], xmm0
    movsd xmm0, [rbx + S_VH]
    movsd [rbp + S_VH], xmm0
    movsd xmm0, [rbx + S_FONT]
    movsd [rbp + S_FONT], xmm0
    inc dword [r15 + P_DEPTH]
    mov [r15 + P_XML + UgfxSvgXml_cur], r12
    mov eax, [rsp + CC_KIND]
    mov [r15 + P_INST], eax
    mov edi, [r15 + P_DEPTH]
    call svg_walk
    ; the content, then everything back
    mov rax, [r15 + P_SVG]
    mov rcx, [rax + UgfxSvg_items]
    mov [r13 + UgfxSvgClip_items], rcx
    mov ecx, [rax + UgfxSvg_count]
    mov [r13 + UgfxSvgClip_count], ecx
    mov r14d, [r15 + P_ERR]
    mov rdi, r15
    lea rsi, [rsp + CC_FRAME]
    mov ecx, P_SIZE
    rep movsb
    test r14d, r14d
    jz .kept
    mov [r15 + P_ERR], r14d
.kept:
    mov rax, [r15 + P_SVG]
    mov rcx, [rsp + CC_ITEMS]
    mov [rax + UgfxSvg_items], rcx
    mov ecx, [rsp + CC_COUNT]
    mov [rax + UgfxSvg_count], ecx
    mov ecx, [rsp + CC_CAP]
    mov [rax + UgfxSvg_cap], ecx
    ; its own attributes: clipPathUnits and clip-path, or a mask's
    mov [rsp + CC_XML + UgfxSvgXml_cur], r12
    mov rax, [r15 + P_XML + UgfxSvgXml_end]
    mov [rsp + CC_XML + UgfxSvgXml_end], rax
    lea rdi, [rsp + CC_XML]
    call ugfx_svg_xml_next
    test eax, eax
    jz .done
    cmp eax, 2
    je .done
    mov qword [rsp + CC_ATTR + UgfxSvgAttr_cur], 0
    cmp dword [rsp + CC_KIND], K_MASK
    je .mask_attrs
    cmp dword [rsp + CC_KIND], K_PATTERN
    je .pattern_attrs
    cmp dword [rsp + CC_KIND], K_MARKER
    je .marker_attrs
.attr:
    lea rdi, [rsp + CC_XML]
    lea rsi, [rsp + CC_ATTR]
    call ugfx_svg_xml_attr
    test eax, eax
    jz .done
    mov rdi, [rsp + CC_ATTR + UgfxSvgAttr_name]
    mov rsi, [rsp + CC_ATTR + UgfxSvgAttr_name_end]
    lea rdx, [rel svg_clip_attrs]
    call ugfx_svg_lookup
    mov r14d, eax
    mov rdi, [rsp + CC_ATTR + UgfxSvgAttr_val]
    mov rsi, [rsp + CC_ATTR + UgfxSvgAttr_val_end]
    call ugfx_svg_trim
    cmp r14d, 1
    je .units
    cmp r14d, 2
    jne .attr
    call svg_url_ref
    test rax, rax
    jz .attr
    mov rsi, rax
    mov ecx, K_CLIP
    call svg_compile                    ; intersected with this one
    mov [r13 + UgfxSvgClip_next], rax
    jmp .attr
.units:
    lea rdx, [rel svg_word_obb]
    mov ecx, 17
    call svg_word
    jne .attr
    mov dword [r13 + UgfxSvgClip_units], 1
    jmp .attr
.mask_attrs:
    ; maskUnits (objectBoundingBox unless userSpaceOnUse), maskContentUnits,
    ; mask-type, and the region as written (-10%, -10%, 120%, 120%)
    mov dword [r13 + UgfxSvgMask_units], 1
    xorpd xmm0, xmm0
    movsd [r13 + UgfxSvgMask_region], xmm0
    movsd [r13 + UgfxSvgMask_region + 8], xmm0
    movsd [r13 + UgfxSvgMask_region + 16], xmm0
    movsd [r13 + UgfxSvgMask_region + 24], xmm0
    lea rax, [rel svg_m10]
    mov [rsp + CC_RAW], rax
    mov [rsp + CC_RAW + 16], rax
    add rax, 4
    mov [rsp + CC_RAW + 8], rax
    mov [rsp + CC_RAW + 24], rax
    lea rax, [rel svg_120]
    mov [rsp + CC_RAW + 32], rax
    mov [rsp + CC_RAW + 48], rax
    add rax, 4
    mov [rsp + CC_RAW + 40], rax
    mov [rsp + CC_RAW + 56], rax
.mask_attr:
    lea rdi, [rsp + CC_XML]
    lea rsi, [rsp + CC_ATTR]
    call ugfx_svg_xml_attr
    test eax, eax
    jz .region
    mov rdi, [rsp + CC_ATTR + UgfxSvgAttr_name]
    mov rsi, [rsp + CC_ATTR + UgfxSvgAttr_name_end]
    lea rdx, [rel svg_mask_attrs]
    call ugfx_svg_lookup
    mov r14d, eax
    mov rdi, [rsp + CC_ATTR + UgfxSvgAttr_val]
    mov rsi, [rsp + CC_ATTR + UgfxSvgAttr_val_end]
    cmp r14d, 3
    jb .mask_word
    cmp r14d, 6
    ja .mask_word
    lea eax, [r14 - 3]
    shl eax, 4
    mov [rsp + CC_RAW + rax], rdi
    mov [rsp + CC_RAW + rax + 8], rsi
    jmp .mask_attr
.mask_word:
    call ugfx_svg_trim
    cmp r14d, 7
    je .mask_type
    cmp r14d, 2
    ja .mask_attr
    jb .mask_units
    lea rdx, [rel svg_word_obb]
    mov ecx, 17
    call svg_word
    sete al
    movzx eax, al
    mov [r13 + UgfxSvgMask_content], eax
    jmp .mask_attr
.mask_units:
    cmp r14d, 1
    jne .mask_attr
    lea rdx, [rel svg_word_obb]
    mov ecx, 17
    call svg_word
    sete al
    movzx eax, al
    mov [r13 + UgfxSvgMask_units], eax
    jmp .mask_attr
.mask_type:
    lea rdx, [rel svg_word_alpha]
    mov ecx, 5
    call svg_word
    sete al
    movzx eax, al
    mov [r13 + UgfxSvgMask_mode], eax
    jmp .mask_attr
.region:
    ; x, y, w, h: fractions (or percentages) of the bbox, else user lengths
    xor r14d, r14d
.region_value:
    cmp r14d, 4
    jae .unit_square
    mov eax, r14d
    shl eax, 4
    mov rdi, [rsp + CC_RAW + rax]
    mov rsi, [rsp + CC_RAW + rax + 8]
    cmp dword [r13 + UgfxSvgMask_units], 0
    je .region_user
    push rsi
    sub rsp, 8
    call ugfx_svg_number
    add rsp, 8
    pop rsi
    test rax, rax
    jz .region_next                     ; (0: unparsable)
    cmp rax, rsi
    jae .region_set
    cmp byte [rax], '%'
    jne .region_set
    mulsd xmm0, [rel svg_hundredth]
    jmp .region_set
.region_user:
    mov edx, r14d
    and edx, 1                          ; x, w: AX_X; y, h: AX_Y
    call svg_length
    test rax, rax
    jz .region_next
.region_set:
    movsd [r13 + UgfxSvgMask_region + r14 * 8], xmm0
.region_next:
    inc r14d
    jmp .region_value
.pattern_attrs:
    call svg_pattern_attrs
    jmp .done
.marker_attrs:
    call svg_marker_attrs
    jmp .done
.unit_square:
    lea rdi, [r13 + UgfxSvgMask_path]
    mov rax, [r15 + P_SVG]
    mov rsi, [rax + UgfxSvg_arena]
    call ugfx_path_init
    test rax, rax
    jnz .nomem_done
    lea rdi, [r13 + UgfxSvgMask_path]
    xorpd xmm0, xmm0
    xorpd xmm1, xmm1
    movsd xmm2, [rel svg_one]
    movapd xmm3, xmm2
    call ugfx_path_add_rect
    test rax, rax
    jz .done
.nomem_done:
    mov dword [r15 + P_ERR], -(ENOMEM)
.done:
    dec dword [r15 + P_COMPILE]
    jmp .out
.nomem:
    mov dword [r15 + P_ERR], -(ENOMEM)
.out:
    mov rax, r13
    add rsp, CC_SIZE
    pop rbp
    pop r14
    pop r13
    pop r12
    ret

; eax = paint kind, edx = colour, rbx = state -> currentColor becomes the
;   color property's colour where one was given
svg_current:
    cmp eax, 2
    jne .done
    cmp dword [rbx + S_COLOR_SET], 0
    je .done
    mov eax, 1
    mov edx, [rbx + S_COLOR]
.done:
    ret

; -----------------------------------------------------------------------------
; svg_lengths — r15 = frame, rbx = state, attributes and styles read: the
;   lengths written with units, in order: font-size (em and % of the
;   parent's), stroke-width, then the geometry. A root svg's width or
;   height in percent stays unset.
; -----------------------------------------------------------------------------
svg_lengths:
    push r12
    push r13
    push r14
    mov rdi, [r15 + P_FONT_RAW]
    test rdi, rdi
    jz .stroke_width
    mov rsi, [r15 + P_FONT_RAW_END]
    call svg_font_size
.stroke_width:
    mov rdi, [r15 + P_SW_RAW]
    test rdi, rdi
    jz .dashes
    mov rsi, [r15 + P_SW_RAW_END]
    mov edx, AX_D
    call svg_length
    test rax, rax
    jz .dashes
    xorpd xmm1, xmm1
    ucomisd xmm0, xmm1
    jb .dashes                          ; negative: ignored
    movsd [rbx + S_SW], xmm0
.dashes:
    mov rdi, [r15 + P_DASH_RAW]
    test rdi, rdi
    jz .dash_offset
    mov rsi, [r15 + P_DASH_RAW_END]
    call ugfx_svg_trim
    push rdi
    push rsi
    IS_WORD none
    pop rsi
    pop rdi
    jne .dash_list
    mov dword [rbx + S_DASH_N], 0
    jmp .dash_offset
.dash_list:
    call svg_dash_list
.dash_offset:
    mov rdi, [r15 + P_DOFF_RAW]
    test rdi, rdi
    jz .geometry
    mov rsi, [r15 + P_DOFF_RAW_END]
    mov edx, AX_D
    call svg_length
    test rax, rax
    jz .geometry
    movsd [rbx + S_DASH_OFF], xmm0
.geometry:
    xor r12d, r12d
.slot:
    cmp r12d, G_COUNT
    jae .done
    bt dword [r15 + P_GRAW], r12d
    jnc .next
    mov eax, r12d
    shl eax, 4
    mov rdi, [r15 + P_GV + rax]
    mov rsi, [r15 + P_GV + rax + 8]
    lea rax, [rel svg_slot_axis]
    movzx edx, byte [rax + r12]
    call svg_length
    test rax, rax
    jz .next
    test ecx, ecx
    jz .store
    cmp dword [r15 + P_ELEM], E_SVG
    jne .store
    cmp dword [r15 + P_ROOT], 0
    jne .store
    cmp r12d, G_W
    je .next
    cmp r12d, G_H
    je .next
.store:
    movsd [r15 + P_G + r12 * 8], xmm0
    bts dword [r15 + P_HAVE], r12d
.next:
    inc r12d
    jmp .slot
.done:
    pop r14
    pop r13
    pop r12
    ret

; -----------------------------------------------------------------------------
; svg_length — rdi / rsi = a length, edx = AX_* (what a percentage is of),
;   rbx = state -> xmm0 = user units, rax = the byte after it (0: not a
;   length), ecx = 1 for a percentage. Units px, pt, pc, mm, cm, in (96 per
;   inch), em, ex (half an em), %; any other unit is not a length.
; -----------------------------------------------------------------------------
svg_length:
    push r12
    push r13
    sub rsp, 8
    mov r12d, edx
    mov r13, rsi
    call ugfx_svg_number
    xor ecx, ecx
    test rax, rax
    jz .out
    cmp rax, r13
    jae .out
    movzx edx, byte [rax]
    cmp dl, '%'
    je .percent
    or dl, 0x20
    sub dl, 'a'
    cmp dl, 25
    ja .out                             ; no unit
    lea rdx, [rax + 2]
    cmp rdx, r13
    ja .bad
    movzx edx, word [rax]
    or edx, 0x2020
    add rax, 2
    cmp dx, 'px'
    je .out
    cmp dx, 'pt'
    je .pt
    cmp dx, 'pc'
    je .pc
    cmp dx, 'mm'
    je .mm
    cmp dx, 'cm'
    je .cm
    cmp dx, 'in'
    je .in
    cmp dx, 'em'
    je .em
    cmp dx, 'ex'
    je .ex
.bad:
    xor eax, eax
    jmp .out
.pt:
    mulsd xmm0, [rel svg_pt]
    jmp .out
.pc:
    mulsd xmm0, [rel svg_pc]
    jmp .out
.mm:
    mulsd xmm0, [rel svg_mm]
    jmp .out
.cm:
    mulsd xmm0, [rel svg_cm]
    jmp .out
.in:
    mulsd xmm0, [rel svg_in]
    jmp .out
.em:
    mulsd xmm0, [rbx + S_FONT]
    jmp .out
.ex:
    mulsd xmm0, [rbx + S_FONT]
    mulsd xmm0, [rel svg_half]
    jmp .out
.percent:
    inc rax
    mov ecx, 1
    mulsd xmm0, [rel svg_hundredth]
    cmp r12d, AX_X
    je .of_w
    cmp r12d, AX_Y
    je .of_h
    cmp r12d, AX_FONT
    je .em
    movsd xmm1, [rbx + S_VW]
    mulsd xmm1, xmm1
    movsd xmm2, [rbx + S_VH]
    mulsd xmm2, xmm2
    addsd xmm1, xmm2
    mulsd xmm1, [rel svg_half]
    sqrtsd xmm1, xmm1
    mulsd xmm0, xmm1
    jmp .out
.of_w:
    mulsd xmm0, [rbx + S_VW]
    jmp .out
.of_h:
    mulsd xmm0, [rbx + S_VH]
.out:
    add rsp, 8
    pop r13
    pop r12
    ret

; rdi / rsi = font-size, rbx = state (S_FONT still the parent's): a
;   keyword, larger / smaller (x 1.2, / 1.2) or a length >= 0
svg_font_size:
    push r12
    push r13
    sub rsp, 8
    call ugfx_svg_trim
    mov r12, rdi
    mov r13, rsi
    lea rdx, [rel svg_font_words]
    call ugfx_svg_lookup
    cmp eax, -1
    je .length
    cmp eax, 8
    je .larger
    cmp eax, 9
    je .smaller
    lea rcx, [rel svg_font_sizes]
    movsd xmm0, [rcx + rax * 8 - 8]
    jmp .set
.larger:
    movsd xmm0, [rbx + S_FONT]
    mulsd xmm0, [rel svg_1_2]
    jmp .set
.smaller:
    movsd xmm0, [rbx + S_FONT]
    divsd xmm0, [rel svg_1_2]
    jmp .set
.length:
    mov rdi, r12
    mov rsi, r13
    mov edx, AX_FONT
    call svg_length
    test rax, rax
    jz .out
    xorpd xmm1, xmm1
    ucomisd xmm0, xmm1
    jb .out
.set:
    movsd [rbx + S_FONT], xmm0
.out:
    add rsp, 8
    pop r13
    pop r12
    ret

; -----------------------------------------------------------------------------
; svg_shape — r15 = frame, rbx = state: builds the element's path into a new
;   item (dropped if it is empty or neither filled nor stroked)
; -----------------------------------------------------------------------------
svg_shape:
    push r12
    push r13
    push r14
    cmp dword [rbx + S_HIDDEN], 0
    jne .shape_out                      ; visibility hidden: nothing of its own
    cmp dword [r15 + P_CLIPMODE], 0
    jne .clip_shape
    ; paints that draw
    xor r13d, r13d
    cmp dword [rbx + S_FILL_KIND], 0
    setne r13b
    cmp dword [rbx + S_STROKE_KIND], 0
    je .have_paint
    xorpd xmm0, xmm0
    ucomisd xmm0, [rbx + S_SW]
    jae .have_paint                     ; width 0: no stroke
    or r13d, 2
.have_paint:
    ; markers (bit 32): path, line, polyline, polygon, outside clips
    cmp dword [r15 + P_CLIPMODE], 0
    jne .markers_known
    mov eax, [r15 + P_ELEM]
    cmp eax, E_PATH
    je .marker_kind
    cmp eax, E_LINE
    jb .markers_known
.marker_kind:
    mov rax, [rbx + S_MARKERS]
    or rax, [rbx + S_MARKERS + 16]
    or rax, [rbx + S_MARKERS + 32]
    jz .markers_known
    or r13d, 32
.markers_known:
    test r13d, r13d
    jz .shape_out
    ; clip-path (bit 8), mask (bit 16): a group
    call svg_clip_ref
    mov [r15 + P_CLIPREC], rax
    test rax, rax
    jz .no_clip
    or r13d, 8
.no_clip:
    call svg_mask_ref
    mov [r15 + P_MASKREC], rax
    test rax, rax
    jz .no_mask
    or r13d, 16
.no_mask:
    ; opacity: a group around fill and stroke together (bit 4), else baked
    movsd xmm0, [r15 + P_OPACITY]
    ucomisd xmm0, [rel svg_one]
    jae .baked
    mov eax, r13d
    and eax, 3
    cmp eax, 3
    jne .bake
.group_alpha:
    or r13d, 4
    jmp .baked
.bake:
    mulsd xmm0, [rbx + S_OP]
    movsd [rbx + S_OP], xmm0
.baked:
    ; room for the item (and a group around it)
    mov ecx, 3
    call svg_item_room
    test rax, rax
    jz .nomem
    mov r14, [r15 + P_SVG]
    mov r12, rax                        ; the item
    mov dword [r12 + UgfxSvgItem_kind], UGFX_SVG_SHAPE
    lea rdi, [r12 + UgfxSvgItem_path]
    mov rsi, [r14 + UgfxSvg_arena]
    call ugfx_path_init
    test rax, rax
    jnz .nomem
    call svg_geometry
    test rax, rax
    jnz .nomem
    cmp dword [r12 + UgfxSvgItem_path + UgfxPath_verb_count], 0
    je .shape_out
    cmp dword [r12 + UgfxSvgItem_path + UgfxPath_error], 0
    jne .nomem
    test r13d, 32
    jz .no_vertices
    call svg_vertices                   ; (before the item moves)
.no_vertices:
    ; transform, paints, style
    xor ecx, ecx
.copy_m:
    mov rax, [rbx + S_M + rcx * 8]
    mov [r12 + UgfxSvgItem_matrix + rcx * 8], rax
    inc ecx
    cmp ecx, 6
    jb .copy_m
    xor eax, eax
    mov edx, [rbx + S_FILL]
    test r13d, 1
    jz .fill_kind
    mov eax, [rbx + S_FILL_KIND]
    cmp eax, 3
    jne .fill_kind
    xor ecx, ecx
    call svg_resolve
.fill_kind:
    call svg_current
    mov [r12 + UgfxSvgItem_fill_kind], eax
    mov edi, edx
    movsd xmm0, [rbx + S_FILL_OP]
    call svg_bake_alpha
    mov [r12 + UgfxSvgItem_fill], eax
    xor eax, eax
    mov edx, [rbx + S_STROKE]
    test r13d, 2
    jz .stroke_kind
    mov eax, [rbx + S_STROKE_KIND]
    cmp eax, 3
    jne .stroke_kind
    mov ecx, 1
    call svg_resolve
.stroke_kind:
    call svg_current
    mov [r12 + UgfxSvgItem_stroke_kind], eax
    mov edi, edx
    movsd xmm0, [rbx + S_STROKE_OP]
    call svg_bake_alpha
    mov [r12 + UgfxSvgItem_stroke], eax
    ; a pattern's tiles are placed by the shape's bounds
    cmp dword [r12 + UgfxSvgItem_fill_kind], 4
    je .pattern_bounds
    cmp dword [r12 + UgfxSvgItem_stroke_kind], 4
    jne .bounded
.pattern_bounds:
    lea rdi, [r12 + UgfxSvgItem_path]
    lea rsi, [r12 + UgfxSvgItem_bbox]
    call ugfx_path_bounds_tight
.bounded:
    mov eax, [rbx + S_RULE]
    mov [r12 + UgfxSvgItem_rule], eax
    mov eax, [rbx + S_JOIN]
    mov [r12 + UgfxSvgItem_join], eax
    mov eax, [rbx + S_CAP]
    mov [r12 + UgfxSvgItem_cap], eax
    movsd xmm0, [rbx + S_SW]
    movsd [r12 + UgfxSvgItem_width], xmm0
    movsd xmm0, [rbx + S_MITER]
    movsd [r12 + UgfxSvgItem_miter], xmm0
    mov eax, [rbx + S_ORDER]
    mov [r12 + UgfxSvgItem_order], eax
    mov rax, [rbx + S_DASH]
    mov [r12 + UgfxSvgItem_dash], rax
    mov eax, [rbx + S_DASH_N]
    mov [r12 + UgfxSvgItem_dash_n], eax
    movsd xmm0, [rbx + S_DASH_OFF]
    movsd [r12 + UgfxSvgItem_dash_off], xmm0
    inc dword [r14 + UgfxSvg_count]
    test r13d, 4 | 8 | 16
    jz .ungrouped
    ; BEGIN, the shape, END
    lea rsi, [r12 + UgfxSvgItem_SIZE - 1]
    lea rdi, [r12 + 2 * UgfxSvgItem_SIZE - 1]
    mov ecx, UgfxSvgItem_SIZE
    std
    rep movsb
    cld
    mov dword [r12 + UgfxSvgItem_kind], UGFX_SVG_BEGIN
    mov eax, 255
    test r13d, 4
    jz .begin_alpha
    call svg_group_alpha
.begin_alpha:
    mov [r12 + UgfxSvgItem_alpha], eax
    mov rcx, [r15 + P_CLIPREC]
    test r13d, 8
    jnz .begin_clip
    xor ecx, ecx
.begin_clip:
    mov [r12 + UgfxSvgItem_clip], rcx
    mov rax, [r15 + P_MASKREC]
    test r13d, 16
    jnz .begin_mask
    xor eax, eax
.begin_mask:
    mov [r12 + UgfxSvgItem_mask], rax
    or rcx, rax                         ; a bbox for either
    xor edx, edx
.begin_m:
    mov rax, [r12 + UgfxSvgItem_SIZE + UgfxSvgItem_matrix + rdx * 8]
    mov [r12 + UgfxSvgItem_matrix + rdx * 8], rax
    inc edx
    cmp edx, 6
    jb .begin_m
    mov edi, [r14 + UgfxSvg_count]
    dec edi                             ; the BEGIN's index
    lea esi, [rdi + 2]
    add dword [r14 + UgfxSvg_count], 2
    test rcx, rcx
    jz .shape_end
    push rdi
    sub rsp, 8
    call svg_group_bbox
    add rsp, 8
    pop rdi
.shape_end:
    imul rsi, rdi, UgfxSvgItem_SIZE
    mov r14, [r15 + P_SVG]
    add rsi, [r14 + UgfxSvg_items]
    lea rdi, [rsi + 2 * UgfxSvgItem_SIZE]
    call svg_end_from
    test r13d, 32
    jz .shape_out
    ; markers inside the group: END goes after them
    mov r14, [r15 + P_SVG]
    dec dword [r14 + UgfxSvg_count]
    mov r12d, [r14 + UgfxSvg_count]
    sub r12d, 2                         ; the BEGIN's index
    call svg_markers
    mov ecx, 1
    call svg_item_room
    test rax, rax
    jz .nomem
    mov rdi, rax
    mov r14, [r15 + P_SVG]
    imul rsi, r12, UgfxSvgItem_SIZE
    add rsi, [r14 + UgfxSvg_items]
    call svg_end_from
    inc dword [r14 + UgfxSvg_count]
    jmp .shape_out
.ungrouped:
    test r13d, 32
    jz .shape_out
    call svg_markers
    jmp .shape_out
.clip_shape:
    ; a clip's content: the geometry, its transform and clip-rule
    mov ecx, 1
    call svg_item_room
    test rax, rax
    jz .nomem
    mov r14, [r15 + P_SVG]
    mov r12, rax
    mov dword [r12 + UgfxSvgItem_kind], UGFX_SVG_SHAPE
    lea rdi, [r12 + UgfxSvgItem_path]
    mov rsi, [r14 + UgfxSvg_arena]
    call ugfx_path_init
    test rax, rax
    jnz .nomem
    call svg_geometry
    test rax, rax
    jnz .nomem
    cmp dword [r12 + UgfxSvgItem_path + UgfxPath_verb_count], 0
    je .shape_out
    cmp dword [r12 + UgfxSvgItem_path + UgfxPath_error], 0
    jne .nomem
    xor ecx, ecx
.clip_m:
    mov rax, [rbx + S_M + rcx * 8]
    mov [r12 + UgfxSvgItem_matrix + rcx * 8], rax
    inc ecx
    cmp ecx, 6
    jb .clip_m
    mov eax, [rbx + S_CLIPRULE]
    mov [r12 + UgfxSvgItem_rule], eax
    inc dword [r14 + UgfxSvg_count]
    jmp .shape_out
.nomem:
    mov dword [r15 + P_ERR], -(ENOMEM)
.shape_out:
    pop r14
    pop r13
    pop r12
    ret

; -----------------------------------------------------------------------------
; svg_resolve — ecx = 0 fill / 1 stroke of state rbx (kind 3), r12 = the
;   item (path built), r15 = frame -> eax = kind, edx = colour: the
;   gradient as a paint (kind 3, edx opaque so the opacities make its
;   alpha), a solid colour (1), nothing (0), or the fallback when the id
;   names no gradient
; -----------------------------------------------------------------------------
svg_resolve:
    push r13
    push r14
    sub rsp, 8
    mov r13d, ecx
    mov rax, [r15 + P_SVG]
    mov rdi, [rax + UgfxSvg_arena]
    mov esi, UgfxPaint_SIZE
    call arena_alloc
    test rax, rax
    jz .nomem
    mov r14, rax
    lea rcx, [r12 + UgfxSvgItem_fill_paint]
    test r13d, r13d
    jz .slot
    lea rcx, [r12 + UgfxSvgItem_stroke_paint]
.slot:
    mov [rcx], r14
    call svg_viewport
    lea rdi, [r15 + P_DEFS]
    mov rsi, [rbx + S_FILL_ID]
    mov rdx, [rbx + S_FILL_ID_END]
    lea rax, [r12 + UgfxSvgItem_fill_pm]
    test r13d, r13d
    jz .args
    mov rsi, [rbx + S_STROKE_ID]
    mov rdx, [rbx + S_STROKE_ID_END]
    lea rax, [r12 + UgfxSvgItem_stroke_pm]
.args:
    lea rcx, [r12 + UgfxSvgItem_path]
    lea r8, [r15 + P_VIEW]
    mov r9, r14
    sub rsp, 8
    push rax                            ; the matrix (7th argument)
    call ugfx_svg_defs_paint
    add rsp, 16
    cmp eax, -1
    je .fallback
    cmp eax, 3
    jne .out
    mov edx, 0xFF000000
    jmp .out
.fallback:
    ; a pattern by that id?
    mov rsi, [rbx + S_FILL_ID]
    mov rdx, [rbx + S_FILL_ID_END]
    test r13d, r13d
    jz .pattern
    mov rsi, [rbx + S_STROKE_ID]
    mov rdx, [rbx + S_STROKE_ID_END]
.pattern:
    mov ecx, K_PATTERN
    call svg_compile
    test rax, rax
    jz .no_pattern
    lea rcx, [r12 + UgfxSvgItem_fill_paint]
    test r13d, r13d
    jz .pattern_slot
    lea rcx, [r12 + UgfxSvgItem_stroke_paint]
.pattern_slot:
    mov [rcx], rax
    mov eax, 4
    mov edx, 0xFF000000
    jmp .out
.no_pattern:
    mov eax, [rbx + S_FILL_FB]
    mov edx, [rbx + S_FILL]
    test r13d, r13d
    jz .out
    mov eax, [rbx + S_STROKE_FB]
    mov edx, [rbx + S_STROKE]
    jmp .out
.nomem:
    mov dword [r15 + P_ERR], -(ENOMEM)
    xor eax, eax
    xor edx, edx
.out:
    add rsp, 8
    pop r14
    pop r13
    ret

; r15 = frame -> P_VIEW = the viewport (viewBox size, else width / height,
;   else 300 x 150), for userSpaceOnUse percentages
svg_viewport:
    mov rax, [r15 + P_SVG]
    movsd xmm0, [rel svg_default_w]
    movsd xmm1, [rel svg_default_h]
    mov ecx, [rax + UgfxSvg_has]
    test ecx, 1
    jz .no_viewbox
    movsd xmm0, [rax + UgfxSvg_viewbox + 16]
    movsd xmm1, [rax + UgfxSvg_viewbox + 24]
    jmp .done
.no_viewbox:
    xorpd xmm2, xmm2
    test ecx, 2
    jz .no_width
    movsd xmm3, [rax + UgfxSvg_width]
    ucomisd xmm3, xmm2
    jbe .no_width
    movapd xmm0, xmm3
.no_width:
    test ecx, 4
    jz .done
    movsd xmm3, [rax + UgfxSvg_height]
    ucomisd xmm3, xmm2
    jbe .done
    movapd xmm1, xmm3
.done:
    movsd [r15 + P_VIEW], xmm0
    movsd [r15 + P_VIEW + 8], xmm1
    ret

; rdi = "url(" ..., rsi = the value's end -> rax = id (0: malformed), rdx =
;   its end, rdi = after ')' (the fallback follows), rsi kept
svg_url:
    add rdi, 4
.ws:
    cmp rdi, rsi
    jae .bad
    cmp byte [rdi], ' '
    ja .quote
    inc rdi
    jmp .ws
.quote:
    xor ecx, ecx
    movzx eax, byte [rdi]
    cmp al, '"'
    je .quoted
    cmp al, 39
    je .quoted
    ; &quot; / &apos; (as written inside an attribute): the id ends at '&'
    cmp al, '&'
    jne .hash
    lea rdx, [rdi + 6]
    cmp rdx, rsi
    ja .hash
    cmp dword [rdi], '&quo'
    je .entity
    cmp dword [rdi], '&apo'
    jne .hash
.entity:
    cmp word [rdi + 4], 't;'
    je .entity_quote
    cmp word [rdi + 4], 's;'
    jne .hash
.entity_quote:
    mov ecx, '&'
    add rdi, 6
    jmp .hash
.quoted:
    mov ecx, eax
    inc rdi
.hash:
    cmp rdi, rsi
    jae .bad
    cmp byte [rdi], '#'
    jne .id
    inc rdi
.id:
    mov rax, rdi
.id_scan:
    cmp rdi, rsi
    jae .bad
    movzx edx, byte [rdi]
    cmp dl, ')'
    je .id_end
    cmp dl, ' '
    jbe .id_end
    test ecx, ecx
    jz .id_next
    cmp edx, ecx
    je .id_end
.id_next:
    inc rdi
    jmp .id_scan
.id_end:
    mov rdx, rdi
.close:
    cmp rdi, rsi
    jae .bad
    inc rdi
    cmp byte [rdi - 1], ')'
    jne .close
    cmp rax, rdx
    je .bad                             ; no id
    ret
.bad:
    xor eax, eax
    ret

; edi = straight colour (its own alpha), xmm0 = paint opacity, rbx = state
;   -> eax = the colour with alpha = round(a x opacity x S_OP); for
;   currentColor items only that alpha byte matters (a = 255 is assumed by
;   the default colours)
svg_bake_alpha:
    mov eax, edi
    shr eax, 24
    cvtsi2sd xmm1, eax
    mulsd xmm1, xmm0
    mulsd xmm1, [rbx + S_OP]
    addsd xmm1, [rel svg_half]
    cvttsd2si eax, xmm1
    shl eax, 24
    and edi, 0x00FFFFFF
    or eax, edi
    ret

; r12 = item, r15 = frame -> rax = 0 or a path error: the geometry of
;   P_ELEM into the item's path (invalid sizes leave it empty)
svg_geometry:
    push rbx
    push r13
    sub rsp, 8
    lea rbx, [r12 + UgfxSvgItem_path]
    mov eax, [r15 + P_ELEM]
    cmp eax, E_PATH
    je .path
    cmp eax, E_POLYLINE
    je .polyline
    cmp eax, E_POLYGON
    je .polygon
    cmp eax, E_LINE
    je .line
    cmp eax, E_CIRCLE
    je .circle
    cmp eax, E_ELLIPSE
    je .ellipse
    ; rect: width and height > 0
    xorpd xmm7, xmm7
    movsd xmm2, [r15 + P_G + G_W * 8]
    ucomisd xmm2, xmm7
    jbe .empty
    movsd xmm3, [r15 + P_G + G_H * 8]
    ucomisd xmm3, xmm7
    jbe .empty
    ; rx / ry: one given means both; clamped to half the size
    mov eax, [r15 + P_HAVE]
    movsd xmm4, [r15 + P_G + G_RX * 8]
    movsd xmm5, [r15 + P_G + G_RY * 8]
    bt eax, G_RX
    jc .rx_given
    movapd xmm4, xmm5
.rx_given:
    bt eax, G_RY
    jc .ry_given
    movapd xmm5, xmm4
.ry_given:
    maxsd xmm4, xmm7
    maxsd xmm5, xmm7
    movapd xmm6, xmm2
    mulsd xmm6, [rel svg_half]
    minsd xmm4, xmm6
    movapd xmm6, xmm3
    mulsd xmm6, [rel svg_half]
    minsd xmm5, xmm6
    ucomisd xmm4, xmm7
    je .plain_rect
    ucomisd xmm5, xmm7
    je .plain_rect
    movsd [r15 + P_G + G_RX * 8], xmm4
    movsd [r15 + P_G + G_RY * 8], xmm5
    call svg_rounded_rect
    jmp .out
.plain_rect:
    mov rdi, rbx
    movsd xmm0, [r15 + P_G + G_X * 8]
    movsd xmm1, [r15 + P_G + G_Y * 8]
    call ugfx_path_add_rect
    jmp .out
.circle:
    xorpd xmm7, xmm7
    movsd xmm2, [r15 + P_G + G_R * 8]
    ucomisd xmm2, xmm7
    jbe .empty
    mov rdi, rbx
    movsd xmm0, [r15 + P_G + G_CX * 8]
    movsd xmm1, [r15 + P_G + G_CY * 8]
    call ugfx_path_add_circle
    jmp .out
.ellipse:
    ; rx / ry (one given means both), > 0
    mov eax, [r15 + P_HAVE]
    movsd xmm2, [r15 + P_G + G_RX * 8]
    movsd xmm3, [r15 + P_G + G_RY * 8]
    bt eax, G_RX
    jc .erx
    movapd xmm2, xmm3
.erx:
    bt eax, G_RY
    jc .ery
    movapd xmm3, xmm2
.ery:
    xorpd xmm7, xmm7
    ucomisd xmm2, xmm7
    jbe .empty
    ucomisd xmm3, xmm7
    jbe .empty
    mov rdi, rbx
    movsd xmm0, [r15 + P_G + G_CX * 8]
    movsd xmm1, [r15 + P_G + G_CY * 8]
    call ugfx_path_add_ellipse
    jmp .out
.line:
    mov rdi, rbx
    movsd xmm0, [r15 + P_G + G_X1 * 8]
    movsd xmm1, [r15 + P_G + G_Y1 * 8]
    call ugfx_path_move_to
    test rax, rax
    jnz .out
    mov rdi, rbx
    movsd xmm0, [r15 + P_G + G_X2 * 8]
    movsd xmm1, [r15 + P_G + G_Y2 * 8]
    call ugfx_path_line_to
    jmp .out
.polyline:
    xor ecx, ecx
    jmp .points
.polygon:
    mov ecx, 1
.points:
    mov rdi, [r15 + P_D]
    test rdi, rdi
    jz .empty
    mov rsi, [r15 + P_D_END]
    mov rdx, rbx
    call ugfx_svg_points
    jmp .out
.path:
    mov rdi, [r15 + P_D]
    test rdi, rdi
    jz .empty
    mov rsi, [r15 + P_D_END]
    mov rdx, rbx
    call ugfx_svg_path_data
    jmp .out
.empty:
    xor eax, eax
.out:
    add rsp, 8
    pop r13
    pop rbx
    ret

; rbx = path, frame geometry (x, y, w, h, rx, ry > 0) -> rax = 0 or error:
;   a rectangle with elliptical corners, clockwise from (x + rx, y)
svg_rounded_rect:
    push r12
    push r13
    sub rsp, 8
    mov rdi, rbx
    movsd xmm0, [r15 + P_G + G_X * 8]
    addsd xmm0, [r15 + P_G + G_RX * 8]
    movsd xmm1, [r15 + P_G + G_Y * 8]
    call ugfx_path_move_to
    test rax, rax
    jnz .out
    ; corners: top right, bottom right, bottom left, top left; each a line
    ; to the corner's start, then a quarter arc
    xor r12d, r12d
.corner:
    cmp r12d, 4
    jae .close
    ; centre: x + rx or x + w - rx, y + ry or y + h - ry
    movsd xmm0, [r15 + P_G + G_X * 8]
    movsd xmm1, [r15 + P_G + G_Y * 8]
    movsd xmm2, [r15 + P_G + G_RX * 8]
    movsd xmm3, [r15 + P_G + G_RY * 8]
    cmp r12d, 2
    jae .left
    addsd xmm0, [r15 + P_G + G_W * 8]
    subsd xmm0, xmm2
    jmp .have_cx
.left:
    addsd xmm0, xmm2
.have_cx:
    cmp r12d, 1
    je .bottom
    cmp r12d, 2
    je .bottom
    addsd xmm1, xmm3
    jmp .have_cy
.bottom:
    addsd xmm1, [r15 + P_G + G_H * 8]
    subsd xmm1, xmm3
.have_cy:
    movsd [r15 + P_ARC + 192 - 32], xmm0     ; (scratch past the one piece a quarter turn makes)
    movsd [r15 + P_ARC + 192 - 24], xmm1
    ; start angle -pi/2 + corner * pi/2
    cvtsi2sd xmm4, r12d
    mulsd xmm4, [rel svg_half_pi]
    addsd xmm4, [rel svg_neg_half_pi]
    movsd [r15 + P_ARC + 192 - 16], xmm4
    ; the line to where the arc starts: centre + (rx cos a, ry sin a)
    ; for a = -pi/2, 0, pi/2, pi: (0, -ry), (rx, 0), (0, ry), (-rx, 0)
    movapd xmm5, xmm0
    movapd xmm6, xmm1
    cmp r12d, 0
    jne .c1
    subsd xmm6, xmm3
    jmp .line_to
.c1:
    cmp r12d, 1
    jne .c2
    addsd xmm5, xmm2
    jmp .line_to
.c2:
    cmp r12d, 2
    jne .c3
    addsd xmm6, xmm3
    jmp .line_to
.c3:
    subsd xmm5, xmm2
.line_to:
    mov rdi, rbx
    movapd xmm0, xmm5
    movapd xmm1, xmm6
    call ugfx_path_line_to
    test rax, rax
    jnz .out
    lea rdi, [r15 + P_ARC]
    movsd xmm0, [r15 + P_ARC + 192 - 32]
    movsd xmm1, [r15 + P_ARC + 192 - 24]
    movsd xmm2, [r15 + P_G + G_RX * 8]
    movsd xmm3, [r15 + P_G + G_RY * 8]
    movsd xmm4, [r15 + P_ARC + 192 - 16]
    movsd xmm5, [rel svg_half_pi]
    call umath_arc_to_cubics
    mov r13, rax
    xor ecx, ecx
.piece:
    cmp rcx, r13
    jae .next_corner
    push rcx
    sub rsp, 8
    imul rax, rcx, 48
    lea rax, [r15 + P_ARC + rax]
    movsd xmm0, [rax]
    movsd xmm1, [rax + 8]
    movsd xmm2, [rax + 16]
    movsd xmm3, [rax + 24]
    movsd xmm4, [rax + 32]
    movsd xmm5, [rax + 40]
    mov rdi, rbx
    call ugfx_path_cubic_to
    add rsp, 8
    pop rcx
    test rax, rax
    jnz .out
    inc rcx
    jmp .piece
.next_corner:
    inc r12d
    jmp .corner
.close:
    mov rdi, rbx
    call ugfx_path_close
.out:
    add rsp, 8
    pop r13
    pop r12
    ret

; -----------------------------------------------------------------------------
; ugfx_svg_draw — rdi = const UgfxSvg*, rsi = UgfxContext*, edx = current
;   colour (straight BGRA), xmm0 = x, xmm1 = y, xmm2 = size -> rax = 0,
;   -EINVAL, or a context error
; -----------------------------------------------------------------------------
%define V_CURRENT   0                   ; u32 (shared with svg_draw_list)
%define V_CTX       8                   ; UgfxContext* (shared)
%define V_T         16                  ; f64[6] the document's device transform (shared)
%define V_BOX       64                  ; f64[4] the viewBox used
%define V_TMP       96                  ; f64[3]
%define V_M         120                 ; f64[6]
%define V_M2        168                 ; f64[6]
%define V_SIZE      232
; the shared fields, from svg_draw_list (rbp is ugfx_svg_draw's frame pointer)
%define DRAW(f)     (rbp - 40 - V_SIZE + (f))

global ugfx_svg_draw
ugfx_svg_draw:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, V_SIZE
    mov rbx, rdi
    mov r13, rsi
    mov rax, -(EINVAL)
    test rdi, rdi
    jz .draw_out
    test rsi, rsi
    jz .draw_out
    mov [rsp + V_CURRENT], edx
    mov [rsp + V_CTX], rsi
    movsd [rsp + V_TMP], xmm0
    movsd [rsp + V_TMP + 8], xmm1
    movsd [rsp + V_TMP + 16], xmm2
    ; the box: viewBox, else (0, 0, width, height), else 300 x 150
    xorpd xmm0, xmm0
    movsd [rsp + V_BOX], xmm0
    movsd [rsp + V_BOX + 8], xmm0
    movsd xmm0, [rel svg_default_w]
    movsd [rsp + V_BOX + 16], xmm0
    movsd xmm0, [rel svg_default_h]
    movsd [rsp + V_BOX + 24], xmm0
    mov eax, [rbx + UgfxSvg_has]
    test eax, 1
    jz .no_viewbox
    xor ecx, ecx
.copy_vb:
    movsd xmm0, [rbx + UgfxSvg_viewbox + rcx * 8]
    movsd [rsp + V_BOX + rcx * 8], xmm0
    inc ecx
    cmp ecx, 4
    jb .copy_vb
    jmp .have_box
.no_viewbox:
    xorpd xmm1, xmm1
    test eax, 2
    jz .no_width
    movsd xmm0, [rbx + UgfxSvg_width]
    ucomisd xmm0, xmm1
    jbe .no_width
    movsd [rsp + V_BOX + 16], xmm0
.no_width:
    test eax, 4
    jz .have_box
    movsd xmm0, [rbx + UgfxSvg_height]
    ucomisd xmm0, xmm1
    jbe .have_box
    movsd [rsp + V_BOX + 24], xmm0
.have_box:
    ; viewBox and width x height: the viewBox into width x height, that box
    ; centred in the square; else the box straight into the square
    mov eax, [rbx + UgfxSvg_has]
    mov edx, PAR_DEFAULT
    test eax, 1
    jz .one_step
    mov edx, [rbx + UgfxSvg_par]
    and eax, 6
    cmp eax, 6
    jne .one_step
    xorpd xmm2, xmm2
    movsd xmm0, [rbx + UgfxSvg_width]
    ucomisd xmm0, xmm2
    jbe .one_step
    movsd xmm1, [rbx + UgfxSvg_height]
    ucomisd xmm1, xmm2
    jbe .one_step
    lea rdi, [rsp + V_M]
    lea rsi, [rsp + V_BOX]
    call svg_fit
    xorpd xmm0, xmm0
    movsd [rsp + V_BOX], xmm0
    movsd [rsp + V_BOX + 8], xmm0
    movsd xmm0, [rbx + UgfxSvg_width]
    movsd [rsp + V_BOX + 16], xmm0
    movsd xmm0, [rbx + UgfxSvg_height]
    movsd [rsp + V_BOX + 24], xmm0
    lea rdi, [rsp + V_M2]
    mov edx, PAR_DEFAULT
    call .square
    lea rdi, [rsp + V_M]
    lea rsi, [rsp + V_M2]
    lea rdx, [rsp + V_M]
    call umath_affine2_multiply
    jmp .mapped
.one_step:
    lea rdi, [rsp + V_M]
    call .square
.mapped:
    mov rdi, r13
    call ugfx_ctx_save
    test rax, rax
    jnz .draw_out
    mov rdi, r13
    lea rsi, [rsp + V_M]
    call ugfx_ctx_transform
    xor ecx, ecx
.keep_t:
    mov rax, [r13 + UgfxContext_state + UgfxState_transform + rcx * 8]
    mov [rsp + V_T + rcx * 8], rax
    inc ecx
    cmp ecx, 6
    jb .keep_t
    mov rdi, r13
    xor esi, esi
    call ugfx_ctx_set_dash
    mov rdi, [rbx + UgfxSvg_items]
    mov esi, [rbx + UgfxSvg_count]
    call svg_draw_list
    push rax
    sub rsp, 8
    mov rdi, r13
    call ugfx_ctx_restore
    add rsp, 8
    pop rax
.draw_out:
    add rsp, V_SIZE
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
; rdi = out, edx = preserveAspectRatio: V_BOX fitted into the square,
;   offset to (x, y) (frame at rsp + 8)
.square:
    lea rsi, [rsp + 8 + V_BOX]
    movsd xmm0, [rsp + 8 + V_TMP + 16]
    movapd xmm1, xmm0
    push rdi
    call svg_fit
    pop rdi
    movsd xmm0, [rdi + 32]
    addsd xmm0, [rsp + 8 + V_TMP]
    movsd [rdi + 32], xmm0
    movsd xmm0, [rdi + 40]
    addsd xmm0, [rsp + 8 + V_TMP + 8]
    movsd [rdi + 40], xmm0
    ret

; -----------------------------------------------------------------------------
; svg_draw_list — rdi = UgfxSvgItem[], esi = count, rbp = ugfx_svg_draw's
;   frame (DRAW: the context, the current colour) -> rax = 0 or a context
;   error, every level it opened closed. Items' matrices are relative to
;   the context's transform when it begins. Re-entrant: a mask's content
;   and a pattern's tiles are drawn through it.
; -----------------------------------------------------------------------------
%define L_COUNT     0                   ; u32
%define L_OPEN      4                   ; u32 context levels BEGINs opened
%define L_CI        8                   ; u32 a clip item's index
%define L_ALPHA     12                  ; u32 the context's alpha at an item
%define L_STYLE     16                  ; UgfxStroke
%define L_DASH      40                  ; UgfxDash
%define L_M2        64                  ; f64[6]
%define L_T         112                 ; f64[6] the context's transform when the list began
%define L_SIZE      160

svg_draw_list:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, L_SIZE
    mov rbx, rdi
    mov [rsp + L_COUNT], esi
    mov dword [rsp + L_OPEN], 0
    mov r13, [DRAW(V_CTX)]
    xor ecx, ecx
.keep_t:
    mov rax, [r13 + UgfxContext_state + UgfxState_transform + rcx * 8]
    mov [rsp + L_T + rcx * 8], rax      ; the items' matrices start from here
    inc ecx
    cmp ecx, 6
    jb .keep_t
    xor r14d, r14d
.item:
    cmp r14d, [rsp + L_COUNT]
    jae .items_done
    imul r12, r14, UgfxSvgItem_SIZE
    add r12, rbx
    mov eax, [r12 + UgfxSvgItem_kind]
    cmp eax, UGFX_SVG_BEGIN
    je .begin
    cmp eax, UGFX_SVG_END
    je .end
    cmp eax, UGFX_SVG_MARKER
    je .marker
    mov eax, [r13 + UgfxContext_state + UgfxState_alpha]
    mov [rsp + L_ALPHA], eax            ; paints' alpha is relative to this
    cmp dword [r12 + UgfxSvgItem_kind], UGFX_SVG_IMAGE
    je .image
    mov [rsp + L_ALPHA], eax            ; paints' alpha is relative to this
    mov rdi, r13
    call ugfx_ctx_save
    test rax, rax
    jnz .fail
    mov rdi, r13
    lea rsi, [r12 + UgfxSvgItem_matrix]
    call ugfx_ctx_transform
    ; fill then stroke, or the other way round (paint-order)
    xor r15d, r15d
.pass:
    cmp r15d, 2
    jae .item_done
    mov eax, r15d
    xor eax, [r12 + UgfxSvgItem_order]
    inc r15d
    test eax, eax
    jnz .stroke
    mov eax, [r12 + UgfxSvgItem_fill_kind]
    test eax, eax
    jz .pass
    cmp eax, 4
    je .fill_pattern
    cmp eax, 3
    jne .fill_colour
    mov rdi, r13
    mov rsi, [r12 + UgfxSvgItem_fill_paint]
    lea rdx, [r12 + UgfxSvgItem_fill_pm]
    call ugfx_ctx_set_fill_paint
    mov edi, [r12 + UgfxSvgItem_fill]
    call .paint_alpha
    jmp .fill_rule
.fill_colour:
    mov edi, 0xFF000000
    call .paint_alpha                   ; back to the item's alpha
    mov eax, [r12 + UgfxSvgItem_fill_kind]
    mov edi, [r12 + UgfxSvgItem_fill]
    call .paint_colour
    mov rdi, r13
    mov esi, eax
    call ugfx_ctx_set_fill_color
.fill_rule:
    mov rdi, r13
    mov esi, [r12 + UgfxSvgItem_rule]
    call ugfx_ctx_set_fill_rule
    mov rdi, r13
    lea rsi, [r12 + UgfxSvgItem_path]
    call ugfx_ctx_fill
    test rax, rax
    jnz .item_fail
    jmp .pass
.stroke:
    mov eax, [r12 + UgfxSvgItem_stroke_kind]
    test eax, eax
    jz .pass
    cmp eax, 4
    je .stroke_style
    cmp eax, 3
    jne .stroke_colour
    mov rdi, r13
    mov rsi, [r12 + UgfxSvgItem_stroke_paint]
    lea rdx, [r12 + UgfxSvgItem_stroke_pm]
    call ugfx_ctx_set_stroke_paint
    mov edi, [r12 + UgfxSvgItem_stroke]
    call .paint_alpha
    jmp .stroke_style
.stroke_colour:
    mov edi, 0xFF000000
    call .paint_alpha                   ; back to the item's alpha
    mov eax, [r12 + UgfxSvgItem_stroke_kind]
    mov edi, [r12 + UgfxSvgItem_stroke]
    call .paint_colour
    mov rdi, r13
    mov esi, eax
    call ugfx_ctx_set_stroke_color
.stroke_style:
    movsd xmm0, [r12 + UgfxSvgItem_width]
    movsd [rsp + L_STYLE + UgfxStroke_width], xmm0
    movsd xmm0, [r12 + UgfxSvgItem_miter]
    movsd [rsp + L_STYLE + UgfxStroke_miter_limit], xmm0
    mov eax, [r12 + UgfxSvgItem_join]
    mov [rsp + L_STYLE + UgfxStroke_join], eax
    mov eax, [r12 + UgfxSvgItem_cap]
    mov [rsp + L_STYLE + UgfxStroke_cap], eax
    mov rdi, r13
    lea rsi, [rsp + L_STYLE]
    call ugfx_ctx_set_stroke_style
    cmp dword [r12 + UgfxSvgItem_dash_n], 0
    je .solid
    mov rax, [r12 + UgfxSvgItem_dash]
    mov [rsp + L_DASH + UgfxDash_intervals], rax
    mov eax, [r12 + UgfxSvgItem_dash_n]
    mov [rsp + L_DASH + UgfxDash_count], eax
    movsd xmm0, [r12 + UgfxSvgItem_dash_off]
    movsd [rsp + L_DASH + UgfxDash_offset], xmm0
    mov rdi, r13
    lea rsi, [rsp + L_DASH]
    call ugfx_ctx_set_dash
.solid:
    cmp dword [r12 + UgfxSvgItem_stroke_kind], 4
    je .stroke_pattern
    mov rdi, r13
    lea rsi, [r12 + UgfxSvgItem_path]
    call ugfx_ctx_stroke
    test rax, rax
    jnz .item_fail
    jmp .pass
.fill_pattern:
    ; clipped to the fill, then the tiles
    mov rdi, r13
    call ugfx_ctx_save
    test rax, rax
    jnz .item_fail
    mov rdi, r13
    mov esi, [r12 + UgfxSvgItem_rule]
    call ugfx_ctx_set_fill_rule
    mov rdi, r13
    lea rsi, [r12 + UgfxSvgItem_path]
    call ugfx_ctx_clip
    test rax, rax
    jnz .pattern_fail
    mov rdi, [r12 + UgfxSvgItem_fill_paint]
    xor edx, edx
    mov ecx, [r12 + UgfxSvgItem_fill]
    jmp .pattern_tiles
.stroke_pattern:
    ; clipped to the stroke's outline, then the tiles
    mov rdi, r13
    call ugfx_ctx_save
    test rax, rax
    jnz .item_fail
    mov rdi, r13
    lea rsi, [r12 + UgfxSvgItem_path]
    call ugfx_ctx_clip_stroke
    test rax, rax
    jnz .pattern_fail
    mov rdi, [r12 + UgfxSvgItem_stroke_paint]
    mov edx, 1
    mov ecx, [r12 + UgfxSvgItem_stroke]
.pattern_tiles:
    shr ecx, 24                         ; the paint's alpha
    mov rsi, r12
    call svg_pattern_paint
.pattern_fail:
    push rax
    sub rsp, 8
    mov rdi, r13
    call ugfx_ctx_restore
    add rsp, 8
    pop rax
    test rax, rax
    jnz .item_fail
    jmp .pass
.item_done:
    mov rdi, r13
    call ugfx_ctx_restore
.next_item:
    inc r14d
    jmp .item

.begin:
    mov r15, [r12 + UgfxSvgItem_clip]
    test r15, r15
    jz .begin_layer
    mov rdi, r13
    call ugfx_ctx_save
    test rax, rax
    jnz .fail
    inc dword [rsp + L_OPEN]
.clip_rec:
    ; each clip in the element's space (or its bbox), then intersected
    test r15, r15
    jz .clipped
    call .element_space
    mov dword [rsp + L_CI], 0
    cmp dword [r15 + UgfxSvgClip_units], 0
    je .clip_open
    mov eax, [r15 + UgfxSvgClip_count]
    mov [rsp + L_CI], eax               ; empty box: no shapes
    call .bbox_matrix
    jbe .clip_open
    mov dword [rsp + L_CI], 0
    mov rdi, r13
    lea rsi, [rsp + L_M2]
    call ugfx_ctx_transform
.clip_open:
    mov rdi, r13
    call ugfx_ctx_clip_begin
    test rax, rax
    jnz .fail
.clip_item:
    mov eax, [rsp + L_CI]
    cmp eax, [r15 + UgfxSvgClip_count]
    jae .clip_close
    inc dword [rsp + L_CI]
    imul rax, rax, UgfxSvgItem_SIZE
    add rax, [r15 + UgfxSvgClip_items]
    push rax
    sub rsp, 8
    mov rdi, r13
    call ugfx_ctx_save
    mov rdi, r13
    mov rsi, [rsp + 8]
    lea rsi, [rsi + UgfxSvgItem_matrix]
    call ugfx_ctx_transform
    mov rdi, r13
    mov rsi, [rsp + 8]
    mov esi, [rsi + UgfxSvgItem_rule]
    call ugfx_ctx_set_fill_rule
    mov rdi, r13
    mov rsi, [rsp + 8]
    lea rsi, [rsi + UgfxSvgItem_path]
    call ugfx_ctx_clip_add
    mov [rsp], rax
    mov rdi, r13
    call ugfx_ctx_restore
    mov rax, [rsp]
    add rsp, 16
    test rax, rax
    jz .clip_item
    push rax
    sub rsp, 8
    mov rdi, r13
    call ugfx_ctx_clip_end
    add rsp, 8
    pop rax
    jmp .fail
.clip_close:
    mov rdi, r13
    call ugfx_ctx_clip_end
    mov r15, [r15 + UgfxSvgClip_next]
    jmp .clip_rec
.clipped:
    mov rdi, r13
    lea rsi, [rsp + L_T]
    call ugfx_ctx_set_transform
.begin_layer:
    ; a layer for opacity or a mask
    cmp qword [r12 + UgfxSvgItem_mask], 0
    jne .layer
    cmp dword [r12 + UgfxSvgItem_alpha], 255
    jae .next_item
.layer:
    mov rdi, r13
    mov esi, [r12 + UgfxSvgItem_alpha]
    call ugfx_ctx_begin_layer
    test rax, rax
    jnz .fail
    inc dword [rsp + L_OPEN]
    jmp .next_item

.end:
    cmp dword [rsp + L_OPEN], 0
    je .next_item
    mov r15, [r12 + UgfxSvgItem_mask]
    test r15, r15
    jnz .masked
    cmp dword [r12 + UgfxSvgItem_alpha], 255
    jae .end_clip
    jmp .end_layer
.masked:
    ; the mask's content in its own layer: clipped to its region (user
    ; space or the bbox), in user space or the bbox
    mov rdi, r13
    call ugfx_ctx_begin_mask
    test rax, rax
    jnz .fail
    call .element_space
    movsd xmm0, [r15 + UgfxSvgMask_region + 16]
    movsd xmm1, [r15 + UgfxSvgMask_region + 24]
    movsd xmm2, [r15 + UgfxSvgMask_region]
    movsd xmm3, [r15 + UgfxSvgMask_region + 8]
    cmp dword [r15 + UgfxSvgMask_units], 0
    je .region
    ; x = bx + rx bw, y = by + ry bh, w = rw bw, h = rh bh
    movsd xmm4, [r12 + UgfxSvgItem_bbox + 16]
    subsd xmm4, [r12 + UgfxSvgItem_bbox]
    movsd xmm5, [r12 + UgfxSvgItem_bbox + 24]
    subsd xmm5, [r12 + UgfxSvgItem_bbox + 8]
    mulsd xmm0, xmm4
    mulsd xmm1, xmm5
    mulsd xmm2, xmm4
    addsd xmm2, [r12 + UgfxSvgItem_bbox]
    mulsd xmm3, xmm5
    addsd xmm3, [r12 + UgfxSvgItem_bbox + 8]
.region:
    xorpd xmm4, xmm4
    movsd [rsp + L_M2], xmm0
    movsd [rsp + L_M2 + 8], xmm4
    movsd [rsp + L_M2 + 16], xmm4
    movsd [rsp + L_M2 + 24], xmm1
    movsd [rsp + L_M2 + 32], xmm2
    movsd [rsp + L_M2 + 40], xmm3
    mov rdi, r13
    lea rsi, [rsp + L_M2]
    call ugfx_ctx_transform
    mov rdi, r13
    lea rsi, [r15 + UgfxSvgMask_path]   ; the unit square
    call ugfx_ctx_clip
    test rax, rax
    jnz .mask_fail
    call .element_space
    cmp dword [r15 + UgfxSvgMask_content], 0
    je .mask_content
    call .bbox_matrix
    jbe .mask_done                      ; no box: nothing in the mask
    mov rdi, r13
    lea rsi, [rsp + L_M2]
    call ugfx_ctx_transform
.mask_content:
    mov rdi, [r15 + UgfxSvgMask_items]
    mov esi, [r15 + UgfxSvgMask_count]
    call svg_draw_list
    test rax, rax
    jnz .mask_fail
.mask_done:
    mov rdi, r13
    mov esi, [r15 + UgfxSvgMask_mode]
    call ugfx_ctx_end_mask
    test rax, rax
    jnz .fail
.end_layer:
    mov rdi, r13
    call ugfx_ctx_end_layer
    dec dword [rsp + L_OPEN]
    test rax, rax
    jnz .fail
.end_clip:
    cmp qword [r12 + UgfxSvgItem_clip], 0
    je .next_item
    cmp dword [rsp + L_OPEN], 0
    je .next_item
    mov rdi, r13
    call ugfx_ctx_restore
    dec dword [rsp + L_OPEN]
    jmp .next_item
.mask_fail:
    push rax
    sub rsp, 8
    mov rdi, r13
    mov esi, UGFX_MASK_LUMINANCE
    call ugfx_ctx_end_mask
    add rsp, 8
    pop rax
    jmp .fail

.image:
    ; the PixBuf in its box, clipped to the viewport for slice
    mov rdi, r13
    call ugfx_ctx_save
    test rax, rax
    jnz .fail
    mov rdi, r13
    lea rsi, [r12 + UgfxSvgItem_matrix]
    call ugfx_ctx_transform
    cmp dword [r12 + UgfxSvgItem_order], 0
    je .image_draw
    mov rdi, r13
    lea rsi, [r12 + UgfxSvgItem_path]
    call ugfx_ctx_clip
    test rax, rax
    jnz .item_fail
.image_draw:
    mov edi, [r12 + UgfxSvgItem_fill]
    call .paint_alpha
    mov rdi, r13
    mov rsi, [r12 + UgfxSvgItem_fill_paint]
    movsd xmm0, [r12 + UgfxSvgItem_bbox]
    movsd xmm1, [r12 + UgfxSvgItem_bbox + 8]
    movsd xmm2, [r12 + UgfxSvgItem_bbox + 16]
    movsd xmm3, [r12 + UgfxSvgItem_bbox + 24]
    call ugfx_ctx_draw_image
    test rax, rax
    jnz .item_fail
    jmp .item_done
.marker:
    ; the marker's content at its matrix, clipped to its viewport
    mov r15, [r12 + UgfxSvgItem_marker]
    mov rdi, r13
    call ugfx_ctx_save
    test rax, rax
    jnz .fail
    call .element_space
    cmp dword [r15 + UgfxSvgMarker_clip], 0
    je .marker_vb
    xorpd xmm2, xmm2
    movsd xmm0, [r15 + UgfxSvgMarker_size]
    movsd [rsp + L_M2], xmm0
    movsd [rsp + L_M2 + 8], xmm2
    movsd [rsp + L_M2 + 16], xmm2
    movsd xmm0, [r15 + UgfxSvgMarker_size + 8]
    movsd [rsp + L_M2 + 24], xmm0
    movsd [rsp + L_M2 + 32], xmm2
    movsd [rsp + L_M2 + 40], xmm2
    mov rdi, r13
    lea rsi, [rsp + L_M2]
    call ugfx_ctx_transform
    mov rdi, r13
    lea rsi, [r15 + UgfxSvgMarker_path]
    call ugfx_ctx_clip
    test rax, rax
    jnz .item_fail
    call .element_space
.marker_vb:
    cmp dword [r15 + UgfxSvgMarker_has_vb], 0
    je .marker_content
    mov rdi, r13
    lea rsi, [r15 + UgfxSvgMarker_vbm]
    call ugfx_ctx_transform
.marker_content:
    mov rdi, [r15 + UgfxSvgMarker_items]
    mov esi, [r15 + UgfxSvgMarker_count]
    call svg_draw_list
    test rax, rax
    jnz .item_fail
    jmp .item_done
.item_fail:
    push rax
    sub rsp, 8
    mov rdi, r13
    call ugfx_ctx_restore
    add rsp, 8
    pop rax
.fail:
    ; close every level this list opened
    push rax
    sub rsp, 8
.unwind:
    cmp dword [rsp + 16 + L_OPEN], 0
    je .unwound
    mov rdi, r13
    call ugfx_ctx_end_layer             ; a layer, else a clip's save
    test rax, rax
    jz .unwound_one
    mov rdi, r13
    call ugfx_ctx_restore
.unwound_one:
    dec dword [rsp + 16 + L_OPEN]
    jmp .unwind
.unwound:
    add rsp, 8
    pop rax
    jmp .out
.items_done:
    cmp dword [rsp + L_OPEN], 0
    je .closed
    mov rdi, r13
    call ugfx_ctx_end_layer
    test rax, rax
    jz .closed_one
    mov rdi, r13
    call ugfx_ctx_restore
.closed_one:
    dec dword [rsp + L_OPEN]
    jmp .items_done
.closed:
    xor eax, eax
.out:
    add rsp, L_SIZE
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; the context's transform = the list's x the item's matrix (r12)
.element_space:
    sub rsp, 8
    mov rdi, r13
    lea rsi, [rsp + 16 + L_T]
    call ugfx_ctx_set_transform
    mov rdi, r13
    lea rsi, [r12 + UgfxSvgItem_matrix]
    call ugfx_ctx_transform
    add rsp, 8
    ret
; L_M2 = [bw 0 0 bh bx by] from the item's bbox; flags "below or equal"
;   when the box is empty (frame at rsp + 8)
.bbox_matrix:
    movsd xmm0, [r12 + UgfxSvgItem_bbox + 16]
    subsd xmm0, [r12 + UgfxSvgItem_bbox]
    movsd xmm1, [r12 + UgfxSvgItem_bbox + 24]
    subsd xmm1, [r12 + UgfxSvgItem_bbox + 8]
    xorpd xmm2, xmm2
    movsd [rsp + 8 + L_M2], xmm0
    movsd [rsp + 8 + L_M2 + 8], xmm2
    movsd [rsp + 8 + L_M2 + 16], xmm2
    movsd [rsp + 8 + L_M2 + 24], xmm1
    movsd xmm3, [r12 + UgfxSvgItem_bbox]
    movsd [rsp + 8 + L_M2 + 32], xmm3
    movsd xmm3, [r12 + UgfxSvgItem_bbox + 8]
    movsd [rsp + 8 + L_M2 + 40], xmm3
    ucomisd xmm0, xmm2
    jbe .bbox_done
    ucomisd xmm1, xmm2
.bbox_done:
    ret
; edi = item colour: the context's alpha = the item's alpha x its / 255
;   (frame at rsp + 8)
.paint_alpha:
    shr edi, 24
    mov esi, [rsp + 8 + L_ALPHA]
    imul esi, edi
    add esi, 128
    mov eax, esi
    shr eax, 8
    add esi, eax
    shr esi, 8
    mov rdi, r13
    sub rsp, 8
    call ugfx_ctx_set_alpha
    add rsp, 8
    ret
; eax = kind, edi = item colour -> eax = premultiplied colour; currentColor
;   takes the given colour with its alpha x the item's
.paint_colour:
    cmp eax, 2
    jne .premultiply
    mov eax, [DRAW(V_CURRENT)]
    mov ecx, eax
    shr ecx, 24
    shr edi, 24
    imul ecx, edi
    add ecx, 128
    mov edx, ecx
    shr edx, 8
    add ecx, edx
    shr ecx, 8                          ; alpha x item alpha / 255
    shl ecx, 24
    and eax, 0x00FFFFFF
    or eax, ecx
    mov edi, eax
.premultiply:
    mov eax, edi
    mov r8d, eax
    shr r8d, 24
    mov r9d, r8d
    shl r9d, 24
    xor ecx, ecx
.pm_channel:
    mov edx, eax
    shr edx, cl
    and edx, 255
    imul edx, r8d
    add edx, 128
    mov r10d, edx
    shr r10d, 8
    add edx, r10d
    shr edx, 8
    shl edx, cl
    or r9d, edx
    add ecx, 8
    cmp ecx, 24
    jb .pm_channel
    mov eax, r9d
    ret

section .rodata
svg_hundredth:      dq 0.01
svg_2p30:           dq 1073741824.0
align 16
svg_abs_mask:       dq 0x7FFFFFFFFFFFFFFF, 0

section .data
global ugfx_svg_version
ugfx_svg_version: dq 0x010000
