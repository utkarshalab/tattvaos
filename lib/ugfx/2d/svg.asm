; =============================================================================
; Utkarsha OS — lib/ugfx/2d/svg.asm
; =============================================================================
; SVG documents: parsed once into a flat list of drawing items, drawn any
; number of times through a context.
;
;   ugfx_svg_parse(svg, arena, data, size)
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
extern ugfx_path_bounds_tight
extern ugfx_ctx_set_transform
extern ugfx_ctx_clip_begin
extern ugfx_ctx_clip_add
extern ugfx_ctx_clip_end
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
%define S_SIZE          240

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
%define SVG_MAX_CLIPS   4               ; clipPaths compiling inside each other
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
%define A_LAST_PROP     19              ; ids up to here are style properties too
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
%define P_SIZE          (((P_FONT_RAW + 96 + 15) & ~15) + 8)

%define PAR_DEFAULT     5               ; xMidYMid meet

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
    NAME "mask", E_SKIP
    NAME "symbol", E_SYMBOL
    NAME "use", E_USE
    NAME "linearGradient", E_SKIP
    NAME "radialGradient", E_SKIP
    NAME "pattern", E_SKIP
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
    db 0
svg_clip_attrs:
    NAME "clipPathUnits", 1
    NAME "clip-path", 2
    db 0
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
    cmp eax, E_CLIPPATH
    je .clip_root
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
    cmp ecx, 2
    jne .kind
    mov eax, E_GROUP
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
    mov dword [r15 + P_GRAW], 0
    mov qword [r15 + P_FONT_RAW], 0
    mov qword [r15 + P_SW_RAW], 0
    mov qword [r15 + P_DASH_RAW], 0
    mov qword [r15 + P_DOFF_RAW], 0
    mov dword [r15 + P_PAR], PAR_DEFAULT
    mov qword [r15 + P_CLIP], 0
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
    call svg_clip_ref
    mov [r15 + P_CLIPREC], rax
    test rax, rax
    jnz .open
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
    cmp qword [rcx + UgfxSvgItem_clip], 0
    je .room
    mov edi, r12d
    mov esi, [rax + UgfxSvg_count]
    call svg_group_bbox
.room:
    mov ecx, 1
    call svg_item_room
    test rax, rax
    jz .nomem
    mov rdx, [r15 + P_SVG]
    imul rcx, r12, UgfxSvgItem_SIZE
    add rcx, [rdx + UgfxSvg_items]
    mov dword [rax + UgfxSvgItem_kind], UGFX_SVG_END
    mov edx, [rcx + UgfxSvgItem_alpha]
    mov [rax + UgfxSvgItem_alpha], edx
    mov rdx, [rcx + UgfxSvgItem_clip]
    mov [rax + UgfxSvgItem_clip], rdx
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
    jne .next
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
; svg_clip_ref — r15 = frame, rbx = state -> rax = the element's compiled
;   clip-path (0: none, not a clipPath, or inside a clip's content)
; -----------------------------------------------------------------------------
svg_clip_ref:
    sub rsp, 8
    xor eax, eax
    cmp dword [r15 + P_CLIPMODE], 0
    jne .out
    mov rdi, [r15 + P_CLIP]
    test rdi, rdi
    jz .out
    mov rsi, [r15 + P_CLIP_END]
    call svg_url_ref
    test rax, rax
    jz .out
    mov rsi, rax
    call svg_clip_compile
.out:
    add rsp, 8
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
; svg_clip_compile — rsi / rdx = a clipPath's id, r15 = frame, rbx = the
;   referencing element's state -> rax = UgfxSvgClip* (0: no such clipPath,
;   too deep, or out of memory). The clipPath's subtree is walked from a
;   fresh state (the defaults, with the element's viewport and font-size)
;   into an item list of its own, with every frame field kept.
; -----------------------------------------------------------------------------
%define CC_FRAME    0                               ; the frame, P_SIZE bytes
%define CC_ITEMS    (((P_SIZE + 15) & ~15))         ; the main item list
%define CC_COUNT    (CC_ITEMS + 8)
%define CC_CAP      (CC_ITEMS + 12)
%define CC_XML      (CC_ITEMS + 16)                 ; the clipPath's tag, read again
%define CC_ATTR     (CC_XML + UgfxSvgXml_SIZE)
%define CC_SIZE     (((CC_ATTR + UgfxSvgAttr_SIZE + 15) & ~15) + 8)

svg_clip_compile:
    push r12
    push r13
    push r14
    push rbp
    sub rsp, CC_SIZE
    xor r13d, r13d
    cmp dword [r15 + P_CLIPMODE], SVG_MAX_CLIPS
    jae .out
    mov eax, [r15 + P_DEPTH]
    cmp eax, SVG_MAX_DEPTH
    jae .out
    lea rdi, [r15 + P_DEFS]
    call ugfx_svg_defs_id
    test rax, rax
    jz .out
    mov r12, rax                        ; its '<'
    ; a clipPath element
    mov rcx, [r15 + P_XML + UgfxSvgXml_end]
    lea rdx, [r12 + 10]
    cmp rdx, rcx
    ja .out
    mov rdx, 'clipPath'
    cmp [r12 + 1], rdx
    jne .out
    movzx eax, byte [r12 + 9]
    cmp al, '>'
    je .is_clip
    cmp al, '/'
    je .is_clip
    cmp al, ' '
    ja .out
.is_clip:
    mov rax, [r15 + P_SVG]
    mov rdi, [rax + UgfxSvg_arena]
    mov esi, UgfxSvgClip_SIZE
    call arena_alloc
    test rax, rax
    jz .nomem
    mov r13, rax
    mov qword [r13 + UgfxSvgClip_items], 0
    mov dword [r13 + UgfxSvgClip_count], 0
    mov dword [r13 + UgfxSvgClip_units], 0
    mov qword [r13 + UgfxSvgClip_next], 0
    inc dword [r15 + P_CLIPMODE]
    ; keep the frame and the main list
    lea rdi, [rsp + CC_FRAME]
    mov rsi, r15
    mov ecx, P_SIZE
    rep movsb
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
    mov dword [r15 + P_INST], 2
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
    ; the clipPath's own attributes: clipPathUnits, clip-path
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
    call svg_clip_compile               ; intersected with this one
    mov [r13 + UgfxSvgClip_next], rax
    jmp .attr
.units:
    lea rdx, [rel svg_word_obb]
    mov ecx, 17
    call svg_word
    jne .attr
    mov dword [r13 + UgfxSvgClip_units], 1
    jmp .attr
.done:
    dec dword [r15 + P_CLIPMODE]
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
    test r13d, r13d
    jz .shape_out
    ; clip-path: a group (bit 8)
    call svg_clip_ref
    mov [r15 + P_CLIPREC], rax
    test rax, rax
    jz .no_clip
    or r13d, 8
.no_clip:
    ; opacity: a group around fill and stroke together (bit 4), else baked
    movsd xmm0, [r15 + P_OPACITY]
    ucomisd xmm0, [rel svg_one]
    jae .baked
    cmp r13d, 3
    je .group_alpha
    cmp r13d, 3 | 8
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
    test r13d, 4 | 8
    jz .shape_out
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
    xor edx, edx
.begin_m:
    mov rax, [r12 + UgfxSvgItem_SIZE + UgfxSvgItem_matrix + rdx * 8]
    mov [r12 + UgfxSvgItem_matrix + rdx * 8], rax
    inc edx
    cmp edx, 6
    jb .begin_m
    mov dword [r12 + 2 * UgfxSvgItem_SIZE + UgfxSvgItem_kind], UGFX_SVG_END
    mov eax, [r12 + UgfxSvgItem_alpha]
    mov [r12 + 2 * UgfxSvgItem_SIZE + UgfxSvgItem_alpha], eax
    mov [r12 + 2 * UgfxSvgItem_SIZE + UgfxSvgItem_clip], rcx
    mov edi, [r14 + UgfxSvg_count]
    dec edi                             ; the BEGIN's index
    lea esi, [rdi + 2]
    add dword [r14 + UgfxSvg_count], 2
    test rcx, rcx
    jz .shape_out
    call svg_group_bbox
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
%define V_CURRENT   0                   ; u32
%define V_BOX       8                   ; f64[4] the viewBox used
%define V_STYLE     40                  ; UgfxStroke
%define V_TMP       64                  ; f64[3]
%define V_ALPHA     88                  ; u32 the context's alpha on entry
%define V_DASH      104                 ; UgfxDash
%define V_M         128                 ; f64[6]
%define V_M2        176                 ; f64[6]
%define V_OPEN      224                 ; u32 context levels BEGINs opened
%define V_CI        228                 ; u32 a clip item's index
%define V_T         232                 ; f64[6] the context's transform for the document
%define V_SIZE      280

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
    mov dword [rsp + V_OPEN], 0
    ; the items
    xor r14d, r14d
.item:
    cmp r14d, [rbx + UgfxSvg_count]
    jae .items_done
    imul r12, r14, UgfxSvgItem_SIZE
    add r12, [rbx + UgfxSvg_items]
    mov eax, [r12 + UgfxSvgItem_kind]
    cmp eax, UGFX_SVG_BEGIN
    je .begin
    cmp eax, UGFX_SVG_END
    je .end
    mov eax, [r13 + UgfxContext_state + UgfxState_alpha]
    mov [rsp + V_ALPHA], eax            ; paints' alpha is relative to this
    mov rdi, r13
    call ugfx_ctx_save
    test rax, rax
    jnz .item_fail_outer
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
    call .paint_alpha                   ; back to the entry alpha
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
    call .paint_alpha                   ; back to the entry alpha
    mov eax, [r12 + UgfxSvgItem_stroke_kind]
    mov edi, [r12 + UgfxSvgItem_stroke]
    call .paint_colour
    mov rdi, r13
    mov esi, eax
    call ugfx_ctx_set_stroke_color
.stroke_style:
    movsd xmm0, [r12 + UgfxSvgItem_width]
    movsd [rsp + V_STYLE + UgfxStroke_width], xmm0
    movsd xmm0, [r12 + UgfxSvgItem_miter]
    movsd [rsp + V_STYLE + UgfxStroke_miter_limit], xmm0
    mov eax, [r12 + UgfxSvgItem_join]
    mov [rsp + V_STYLE + UgfxStroke_join], eax
    mov eax, [r12 + UgfxSvgItem_cap]
    mov [rsp + V_STYLE + UgfxStroke_cap], eax
    mov rdi, r13
    lea rsi, [rsp + V_STYLE]
    call ugfx_ctx_set_stroke_style
    cmp dword [r12 + UgfxSvgItem_dash_n], 0
    je .solid
    mov rax, [r12 + UgfxSvgItem_dash]
    mov [rsp + V_DASH + UgfxDash_intervals], rax
    mov eax, [r12 + UgfxSvgItem_dash_n]
    mov [rsp + V_DASH + UgfxDash_count], eax
    movsd xmm0, [r12 + UgfxSvgItem_dash_off]
    movsd [rsp + V_DASH + UgfxDash_offset], xmm0
    mov rdi, r13
    lea rsi, [rsp + V_DASH]
    call ugfx_ctx_set_dash
.solid:
    mov rdi, r13
    lea rsi, [r12 + UgfxSvgItem_path]
    call ugfx_ctx_stroke
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
    jnz .item_fail_outer
    inc dword [rsp + V_OPEN]
.clip_rec:
    ; each clip in the element's space (or its bbox), then intersected
    test r15, r15
    jz .clipped
    mov rdi, r13
    lea rsi, [rsp + V_T]
    call ugfx_ctx_set_transform
    mov rdi, r13
    lea rsi, [r12 + UgfxSvgItem_matrix]
    call ugfx_ctx_transform
    mov dword [rsp + V_CI], 0
    cmp dword [r15 + UgfxSvgClip_units], 0
    je .clip_open
    movsd xmm0, [r12 + UgfxSvgItem_bbox + 16]
    subsd xmm0, [r12 + UgfxSvgItem_bbox]
    movsd xmm1, [r12 + UgfxSvgItem_bbox + 24]
    subsd xmm1, [r12 + UgfxSvgItem_bbox + 8]
    xorpd xmm2, xmm2
    mov eax, [r15 + UgfxSvgClip_count]
    mov [rsp + V_CI], eax               ; empty box: no shapes
    ucomisd xmm0, xmm2
    jbe .clip_open
    ucomisd xmm1, xmm2
    jbe .clip_open
    mov dword [rsp + V_CI], 0
    movsd [rsp + V_M2], xmm0
    movsd [rsp + V_M2 + 8], xmm2
    movsd [rsp + V_M2 + 16], xmm2
    movsd [rsp + V_M2 + 24], xmm1
    movsd xmm0, [r12 + UgfxSvgItem_bbox]
    movsd [rsp + V_M2 + 32], xmm0
    movsd xmm0, [r12 + UgfxSvgItem_bbox + 8]
    movsd [rsp + V_M2 + 40], xmm0
    mov rdi, r13
    lea rsi, [rsp + V_M2]
    call ugfx_ctx_transform
.clip_open:
    mov rdi, r13
    call ugfx_ctx_clip_begin
    test rax, rax
    jnz .item_fail_outer
.clip_item:
    mov eax, [rsp + V_CI]
    cmp eax, [r15 + UgfxSvgClip_count]
    jae .clip_close
    inc dword [rsp + V_CI]
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
    jmp .item_fail_outer
.clip_close:
    mov rdi, r13
    call ugfx_ctx_clip_end
    mov r15, [r15 + UgfxSvgClip_next]
    jmp .clip_rec
.clipped:
    mov rdi, r13
    lea rsi, [rsp + V_T]
    call ugfx_ctx_set_transform
.begin_layer:
    cmp dword [r12 + UgfxSvgItem_alpha], 255
    jae .next_item
    mov rdi, r13
    mov esi, [r12 + UgfxSvgItem_alpha]
    call ugfx_ctx_begin_layer
    test rax, rax
    jnz .item_fail_outer
    inc dword [rsp + V_OPEN]
    jmp .next_item
.end:
    cmp dword [r12 + UgfxSvgItem_alpha], 255
    jae .end_clip
    cmp dword [rsp + V_OPEN], 0
    je .next_item
    mov rdi, r13
    call ugfx_ctx_end_layer
    dec dword [rsp + V_OPEN]
    test rax, rax
    jnz .item_fail_outer
.end_clip:
    cmp qword [r12 + UgfxSvgItem_clip], 0
    je .next_item
    cmp dword [rsp + V_OPEN], 0
    je .next_item
    mov rdi, r13
    call ugfx_ctx_restore
    dec dword [rsp + V_OPEN]
    jmp .next_item
.item_fail:
    push rax
    sub rsp, 8
    mov rdi, r13
    call ugfx_ctx_restore
    add rsp, 8
    pop rax
.item_fail_outer:
    push rax
    sub rsp, 8
.unwind:
    cmp dword [rsp + 16 + V_OPEN], 0
    je .unwound
    mov rdi, r13
    call ugfx_ctx_end_layer             ; a layer, else a clip's save
    test rax, rax
    jz .unwound_one
    mov rdi, r13
    call ugfx_ctx_restore
.unwound_one:
    dec dword [rsp + 16 + V_OPEN]
    jmp .unwind
.unwound:
    mov rdi, r13
    call ugfx_ctx_restore
    add rsp, 8
    pop rax
    jmp .draw_out
.items_done:
    cmp dword [rsp + V_OPEN], 0
    je .all_closed
    mov rdi, r13
    call ugfx_ctx_end_layer
    test rax, rax
    jz .closed_one
    mov rdi, r13
    call ugfx_ctx_restore
.closed_one:
    dec dword [rsp + V_OPEN]
    jmp .items_done
.all_closed:
    mov rdi, r13
    call ugfx_ctx_restore
    xor eax, eax
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
; edi = item colour: the context's alpha = entry alpha x its alpha / 255
;   (frame at rsp + 8)
.paint_alpha:
    shr edi, 24
    mov esi, [rsp + 8 + V_ALPHA]
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
;   takes the given colour with its alpha x the item's (frame at rsp + 8)
.paint_colour:
    cmp eax, 2
    jne .premultiply
    mov eax, [rsp + 8 + V_CURRENT]
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

section .data
global ugfx_svg_version
ugfx_svg_version: dq 0x010000
