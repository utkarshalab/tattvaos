; =============================================================================
; Utkarsha OS — lib/ugfx/2d/svg_defs.asm
; =============================================================================
; SVG definitions found before drawing: gradients, looked up by id when a
; fill or stroke says url(#id), and the CSS rules of <style> elements.
;
;   ugfx_svg_defs_scan(defs, arena, data, size)
;       every linearGradient / radialGradient in the document with its
;       stops (wherever it is: defs or not)
;   ugfx_svg_defs_id(defs, id, id_end) -> rax = the '<' of the first
;          element with that id, or 0 (for <use>)
;   ugfx_svg_defs_rule(defs, index, selectable)
;       -> rax = rule index's declarations (rdx their end) if it applies
;          to the element, else 0; rules come in cascade order
;   ugfx_svg_defs_paint(defs, id, id_end, path, viewport, paint, matrix)
;       -> -1 no such gradient, 0 paints nothing, 1 a solid colour (edx,
;          straight BGRA), 3 a ugfx paint (written to paint) with its
;          paint -> user space matrix
;
; Gradients: x1 y1 x2 y2 (linear), cx cy r fx fy fr (radial) as numbers or
; percentages, gradientUnits (objectBoundingBox, the default, or
; userSpaceOnUse), spreadMethod (pad, reflect, repeat), gradientTransform,
; href / xlink:href to another gradient whose attributes (of the same kind)
; and stops fill in what is missing (16 deep at most). Stops: offset
; (number or percentage), stop-color, stop-opacity, also from style.
;
; Defaults: linear x1 0% y1 0% x2 100% y2 0%; radial cx cy r 50%, fx / fy
; = cx / cy, fr 0%. In objectBoundingBox units every value is a fraction
; of the shape's tight bounding box (ugfx_path_bounds_tight; a box with no
; width or height paints nothing); in userSpaceOnUse a percentage is of
; the viewport width (x), height (y) or sqrt((w^2 + h^2) / 2) (r, fr).
; No stops paint nothing; one stop, a linear gradient whose ends meet or a
; radial one with no radius paint the last stop's colour. A focal point or
; radius makes it a two-circle gradient from (fx, fy, fr) to (cx, cy, r).
;
; CSS: rules "selectors { declarations }" from every <style> (entities
; decoded outside CDATA; comments, CDATA and HTML comment markers skipped;
; at-rules skipped with their blocks). Selectors: compounds of a type or *,
; .class, #id, [attr], [attr=v] ~= |= ^= $= *= (v an identifier or quoted),
; :first-child, :last-child, :only-child, :root, :nth-child(an+b),
; :nth-last-child(an+b), joined by descendant, > child, + next sibling and
; ~ later sibling combinators, in comma lists. Anything else (other
; pseudo-classes, which a still picture never is in, pseudo-elements,
; namespaces, escapes) leaves that selector out. Matching uses the
; document's element tree, which the scan records (an element in a <use>
; instance is matched where it is written). Rules are kept in cascade
; order: by specificity (ids 10000, classes / attributes / pseudo-classes
; 100, types 1 each), then document order.
; =============================================================================

%include "ugfx.inc"

extern arena_alloc
extern ugfx_svg_xml_next
extern ugfx_svg_xml_attr
extern ugfx_svg_xml_text_end
extern ugfx_svg_xml_decode
extern ugfx_svg_lookup
extern ugfx_svg_trim
extern ugfx_svg_same
extern ugfx_svg_number
extern ugfx_svg_colour
extern ugfx_svg_transform
extern ugfx_path_bounds_tight
extern ugfx_paint_linear
extern ugfx_paint_radial
extern ugfx_paint_radial2
extern umath_affine2_identity
extern umath_affine2_multiply

; one gradient
%define GR_ID           0
%define GR_ID_END       8
%define GR_HREF         16
%define GR_HREF_END     24
%define GR_KIND         32              ; u32 1 linear, 2 radial
%define GR_HAVE         36              ; u32 given: values (bits 0-9), units 10, spread 11, transform 12
%define GR_PCT          40              ; u32 values given as percentages
%define GR_UNITS        44              ; u32 0 objectBoundingBox, 1 userSpaceOnUse
%define GR_SPREAD       48              ; u32 UGFX_SPREAD_*
%define GR_VAL          56              ; f64[10]
%define GR_M            136             ; f64[6] gradientTransform
%define GR_STOPS        184             ; UgfxStop*
%define GR_NSTOPS       192             ; u32
%define GR_STOPCAP      196             ; u32
%define GR_SIZE         200

%define V_X1            0
%define V_Y1            1
%define V_X2            2
%define V_Y2            3
%define V_CX            4
%define V_CY            5
%define V_R             6
%define V_FX            7
%define V_FY            8
%define V_FR            9
%define V_COUNT         10
%define H_UNITS         10
%define H_SPREAD        11
%define H_TRANSFORM     12

; CSS rules
%define RL_SPEC         0               ; u32 specificity
%define RL_COUNT        4               ; u32 simple selectors
%define RL_SIMPLES      8               ; SM_SIZE each, left to right
%define RL_DECL         16              ; the declarations
%define RL_DECL_END     24
%define RL_SIZE         32

; a simple selector
%define SM_KIND         0               ; u8 SK_*
%define SM_OP           1               ; u8 attribute: 0 there, 1 = 2 ~= 3 |= 4 ^= 5 $= 6 *=
%define SM_NEW          2               ; u8 1: a compound starts here
%define SM_COMB         3               ; u8 its combinator with the compound before (CB_*)
%define SM_A            4               ; i32 nth: a n + b
%define SM_B            8
%define SM_NAME         16              ; type / class / id / attribute name
%define SM_NAME_END     24
%define SM_VALUE        32              ; an attribute value
%define SM_VALUE_END    40
%define SM_SIZE         48
%define SK_TYPE         1
%define SK_CLASS        2
%define SK_ID           3
%define SK_ATTR         4
%define SK_FIRST        5
%define SK_LAST         6
%define SK_ROOT         7
%define SK_NTH          8
%define SK_NTH_LAST     9
%define SK_ONLY         10
%define SK_ANY          12
%define CB_DESCENDANT   1
%define CB_CHILD        2
%define CB_NEXT         3
%define CB_LATER        4

; an element of the document
%define EL_TAG          0               ; its '<'
%define EL_PARENT       8               ; i32 element index, -1 none
%define EL_PREV         12              ; i32 the previous sibling
%define EL_NEXT         16              ; i32 the next
%define EL_INDEX        20              ; u32 its place among its siblings, from 1
%define EL_SIZE         24
%define SC_MAX_DEPTH    128

; attribute ids
%define DA_ID           1
%define DA_HREF         2
%define DA_UNITS        3
%define DA_SPREAD       4
%define DA_TRANSFORM    5
%define DA_OFFSET       6
%define DA_STOP_COLOR   7
%define DA_STOP_OPACITY 8
%define DA_STYLE        9
%define DA_VALUE        16              ; + V_*

%define SVG_HREF_DEPTH  16

section .rodata
align 8
defs_one:           dq 1.0
defs_hundredth:     dq 0.01
defs_half:          dq 0.5
defs_255:           dq 255.0
; the defaults: linear (percent), radial (percent)
defs_default:       dq 0.0, 0.0, 1.0, 0.0, 0.5, 0.5, 0.5, 0.5, 0.5, 0.0

%macro NAME 2
    db %strlen(%1), %1, %2
%endmacro
defs_elements:
    NAME "linearGradient", 1
    NAME "radialGradient", 2
    NAME "stop", 3
    NAME "style", 4
    db 0
defs_attributes:
    NAME "id", DA_ID
    NAME "href", DA_HREF
    NAME "xlink:href", DA_HREF
    NAME "gradientUnits", DA_UNITS
    NAME "spreadMethod", DA_SPREAD
    NAME "gradientTransform", DA_TRANSFORM
    NAME "offset", DA_OFFSET
    NAME "stop-color", DA_STOP_COLOR
    NAME "stop-opacity", DA_STOP_OPACITY
    NAME "style", DA_STYLE
    NAME "x1", DA_VALUE + V_X1
    NAME "y1", DA_VALUE + V_Y1
    NAME "x2", DA_VALUE + V_X2
    NAME "y2", DA_VALUE + V_Y2
    NAME "cx", DA_VALUE + V_CX
    NAME "cy", DA_VALUE + V_CY
    NAME "r", DA_VALUE + V_R
    NAME "fx", DA_VALUE + V_FX
    NAME "fy", DA_VALUE + V_FY
    NAME "fr", DA_VALUE + V_FR
    db 0
defs_keywords:
    NAME "userSpaceOnUse", 101
    NAME "objectBoundingBox", 100
    NAME "pad", 110
    NAME "reflect", 112
    NAME "repeat", 111
    db 0

section .text

; -----------------------------------------------------------------------------
; ugfx_svg_defs_scan — rdi = UgfxSvgDefs*, rsi = arena, rdx = data, rcx =
;   bytes -> rax = 0, -ENOMEM
; -----------------------------------------------------------------------------
%define SC_DEFS     0
%define SC_GRAD     8                   ; the gradient being read, or 0
%define SC_STOP     16                  ; f64 offset, u32 -, u32 colour, f64 opacity, style range
%define SC_XML      64                  ; UgfxSvgXml
%define SC_ATTR     (SC_XML + UgfxSvgXml_SIZE)
%define SC_DEPTH    (SC_ATTR + UgfxSvgAttr_SIZE)    ; u32 open elements
%define SC_OPEN     (SC_DEPTH + 8)                  ; i32[SC_MAX_DEPTH] their indexes
%define SC_LAST     (SC_OPEN + 4 * SC_MAX_DEPTH)    ; i32[SC_MAX_DEPTH + 1] each depth's last child
%define SC_SIZE     (((SC_LAST + 4 * SC_MAX_DEPTH + 4 + 15) & ~15) + 8)

global ugfx_svg_defs_scan
ugfx_svg_defs_scan:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, SC_SIZE
    mov r15, rsp
    mov [r15 + SC_DEFS], rdi
    mov [rdi + UgfxSvgDefs_arena], rsi
    mov qword [rdi + UgfxSvgDefs_grads], 0
    mov dword [rdi + UgfxSvgDefs_count], 0
    mov dword [rdi + UgfxSvgDefs_cap], 0
    mov qword [rdi + UgfxSvgDefs_rules], 0
    mov dword [rdi + UgfxSvgDefs_nrules], 0
    mov dword [rdi + UgfxSvgDefs_rulecap], 0
    mov qword [rdi + UgfxSvgDefs_ids], 0
    mov dword [rdi + UgfxSvgDefs_nids], 0
    mov dword [rdi + UgfxSvgDefs_idcap], 0
    mov qword [rdi + UgfxSvgDefs_elems], 0
    mov dword [rdi + UgfxSvgDefs_nelems], 0
    mov dword [rdi + UgfxSvgDefs_elemcap], 0
    lea rax, [rdx + rcx]
    mov [rdi + UgfxSvgDefs_end], rax
    mov qword [r15 + SC_GRAD], 0
    mov dword [r15 + SC_DEPTH], 0
    mov dword [r15 + SC_LAST], -1
    mov [r15 + SC_XML + UgfxSvgXml_cur], rdx
    add rdx, rcx
    mov [r15 + SC_XML + UgfxSvgXml_end], rdx
    mov [r15 + SC_XML + UgfxSvgXml_arena], rsi
.token:
    lea rdi, [r15 + SC_XML]
    call ugfx_svg_xml_next
    test eax, eax
    jz .done
    mov ebx, eax
    call defs_element                   ; the element tree, for CSS
    test rax, rax
    jnz .nomem
    cmp ebx, 2
    je .named
    call defs_record_id                 ; every start tag: its id, if any
    test rax, rax
    jnz .nomem
.named:
    mov rdi, [r15 + SC_XML + UgfxSvgXml_name]
    mov rsi, [r15 + SC_XML + UgfxSvgXml_name_end]
    lea rdx, [rel defs_elements]
    call ugfx_svg_lookup
    cmp ebx, 2
    je .end_tag
    cmp eax, 3
    je .stop
    cmp eax, 4
    je .style
    cmp eax, 1
    jb .token                           ; another element
    cmp eax, 2
    ja .token
    ; a gradient
    mov r12d, eax
    call defs_new_gradient
    test rax, rax
    jz .nomem
    mov r13, rax
    mov [r13 + GR_KIND], r12d
    mov qword [r15 + SC_GRAD], r13
    call defs_gradient_attrs
    cmp dword [r15 + SC_XML + UgfxSvgXml_self], 0
    je .token
    mov qword [r15 + SC_GRAD], 0        ; <linearGradient ... />: no stops
    jmp .token
.end_tag:
    cmp eax, 1
    jb .token
    cmp eax, 2
    ja .token
    mov qword [r15 + SC_GRAD], 0
    jmp .token
.stop:
    mov r13, [r15 + SC_GRAD]
    test r13, r13
    jz .token
    call defs_stop
    test rax, rax
    jnz .nomem
    jmp .token
.style:
    cmp dword [r15 + SC_XML + UgfxSvgXml_self], 0
    jne .token
    ; the CSS text runs to </style>
    lea rdi, [r15 + SC_XML]
    lea rsi, [rel defs_style_name]
    mov edx, 5
    call ugfx_svg_xml_text_end
    mov r12, rax
    mov rdi, [r15 + SC_XML + UgfxSvgXml_cur]
    mov rsi, r12
    ; entities in it: a decoded copy
    mov rax, rdi
.style_amp:
    cmp rax, rsi
    jae .style_css
    cmp byte [rax], '&'
    je .style_decode
    inc rax
    jmp .style_amp
.style_decode:
    mov rdx, [r15 + SC_DEFS]
    mov rdx, [rdx + UgfxSvgDefs_arena]
    call ugfx_svg_xml_decode
    test rax, rax
    jz .nomem
    mov rdi, rax
    mov rsi, rdx
.style_css:
    call defs_css
    test rax, rax
    jnz .nomem
    mov [r15 + SC_XML + UgfxSvgXml_cur], r12
    jmp .token
.done:
    call defs_sort_rules
    xor eax, eax
    jmp .out
.nomem:
    mov rax, -(ENOMEM)
.out:
    add rsp, SC_SIZE
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15

; -----------------------------------------------------------------------------
; defs_css — rdi = CSS text, rsi = its end, r15 = scan frame -> rax = 0 or
;   -ENOMEM: its rules appended (unsorted)
; -----------------------------------------------------------------------------
defs_css:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 24
    mov r12, rdi                        ; cursor
    mov r13, rsi                        ; end
.rule:
    mov rdi, r12
    mov rsi, r13
    call css_skip
    mov r12, rdi
    cmp r12, r13
    jae .done
    cmp byte [r12], '@'
    je .at_rule
    ; selectors up to '{'
    mov rbx, r12
.to_brace:
    cmp r12, r13
    jae .done
    cmp byte [r12], '{'
    je .brace
    inc r12
    jmp .to_brace
.brace:
    mov [rsp], rbx                      ; selectors
    mov [rsp + 8], r12                  ; their end
    lea r14, [r12 + 1]                  ; declarations
    mov r12, r14
.to_close:
    cmp r12, r13
    jae .closed
    cmp byte [r12], '}'
    je .closed
    inc r12
    jmp .to_close
.closed:
    mov [rsp + 16], r12                 ; declarations end
    cmp r12, r13
    jae .selectors
    inc r12                             ; past '}'
.selectors:
    ; each selector of the comma list
    mov rbx, [rsp]
.selector:
    cmp rbx, [rsp + 8]
    jae .rule
    mov rdi, rbx
.comma:
    cmp rdi, [rsp + 8]
    jae .one
    cmp byte [rdi], ','
    je .one
    inc rdi
    jmp .comma
.one:
    push rdi
    mov rsi, rdi
    mov rdi, rbx
    mov rdx, r14
    mov rcx, [rsp + 8 + 16]
    call css_add_rule
    pop rdi
    test rax, rax
    jnz .nomem
    lea rbx, [rdi + 1]
    jmp .selector
.at_rule:
    ; @...; or @... { ... } with nested blocks
    xor ecx, ecx                        ; depth
.at_scan:
    cmp r12, r13
    jae .done
    movzx eax, byte [r12]
    inc r12
    cmp al, '{'
    je .at_open
    cmp al, '}'
    je .at_close
    cmp al, ';'
    jne .at_scan
    test ecx, ecx
    jz .rule
    jmp .at_scan
.at_open:
    inc ecx
    jmp .at_scan
.at_close:
    dec ecx
    jg .at_scan
    jmp .rule
.done:
    xor eax, eax
    jmp .out
.nomem:
    mov rax, -(ENOMEM)
.out:
    add rsp, 24
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; rdi / rsi -> rdi past whitespace, /* comments */, <!-- --> and CDATA
;   markers
css_skip:
    cmp rdi, rsi
    jae .done
    movzx eax, byte [rdi]
    cmp al, ' '
    jbe .one
    mov rcx, rsi
    sub rcx, rdi
    cmp al, '/'
    je .comment
    cmp al, '<'
    je .open_marker
    cmp al, '-'
    je .html_close
    cmp al, ']'
    je .cdata_close
.done:
    ret
.one:
    inc rdi
    jmp css_skip
.comment:
    cmp rcx, 2
    jb .done
    cmp byte [rdi + 1], '*'
    jne .done
    add rdi, 2
.comment_end:
    lea rax, [rdi + 1]
    cmp rax, rsi
    jae .to_end
    cmp word [rdi], '*/'
    je .comment_out
    inc rdi
    jmp .comment_end
.comment_out:
    add rdi, 2
    jmp css_skip
.to_end:
    mov rdi, rsi
    ret
.open_marker:
    cmp rcx, 9
    jb .html_open
    cmp dword [rdi], '<![C'
    jne .html_open
    cmp dword [rdi + 4], 'DATA'
    jne .html_open
    cmp byte [rdi + 8], '['
    jne .html_open
    add rdi, 9
    jmp css_skip
.html_open:
    cmp rcx, 4
    jb .done
    cmp dword [rdi], '<!--'
    jne .done
    add rdi, 4
    jmp css_skip
.html_close:
    cmp rcx, 3
    jb .done
    cmp word [rdi], '--'
    jne .done
    cmp byte [rdi + 2], '>'
    jne .done
    add rdi, 3
    jmp css_skip
.cdata_close:
    cmp rcx, 3
    jb .done
    cmp word [rdi], ']]'
    jne .done
    cmp byte [rdi + 2], '>'
    jne .done
    add rdi, 3
    jmp css_skip

; al -> ZF = 1 when it is an identifier character [A-Za-z0-9_-]
css_ident:
    cmp al, '-'
    je .yes
    cmp al, '_'
    je .yes
    mov ah, al
    sub ah, '0'
    cmp ah, 9
    jbe .yes
    mov ah, al
    or ah, 0x20
    sub ah, 'a'
    cmp ah, 25
    jbe .yes
    or ah, 1                            ; ZF = 0 (ah is non-zero: >= 1 after or)
    ret
.yes:
    cmp al, al                          ; ZF = 1
    ret

; rdi / rsi -> ZF = 1 when the range is one or more identifier characters
css_ident_run:
    cmp rdi, rsi
    jae .no
.byte:
    cmp rdi, rsi
    jae .yes
    mov al, [rdi]
    call css_ident
    jne .no
    inc rdi
    jmp .byte
.yes:
    cmp al, al
    ret
.no:
    or eax, 1
    ret

; rdi / rsi -> rdi past bytes <= ' ' (eax clobbered)
css_ws:
    cmp rdi, rsi
    jae .done
    cmp byte [rdi], ' '
    ja .done
    inc rdi
    jmp css_ws
.done:
    ret

; rdi / rsi -> rdi past identifier characters (eax clobbered)
css_run:
    cmp rdi, rsi
    jae .done
    mov al, [rdi]
    call css_ident
    jne .done
    inc rdi
    jmp css_run
.done:
    ret

; rdi / rsi -> eax = the decimal number there (1 to 6 digits) and rdi past
;   it; CF set (rdi kept) when there is none or it is longer
css_digits:
    mov rdx, rdi
    xor eax, eax
    xor ecx, ecx
.digit:
    cmp rdx, rsi
    jae .end
    movzx r8d, byte [rdx]
    sub r8d, '0'
    cmp r8d, 9
    ja .end
    imul eax, eax, 10
    add eax, r8d
    inc rdx
    inc ecx
    jmp .digit
.end:
    test ecx, ecx
    jz .bad
    cmp ecx, 6
    ja .bad
    mov rdi, rdx
    clc
    ret
.bad:
    stc
    ret

; rdi / rsi = the inside of :nth-child( ) -> eax = a, edx = b of an+b
;   (odd, even, [+-][digits]n [+- digits], [+-]digits); CF set when it is
;   none of those
css_nth:
    push rbx
    push r12
    sub rsp, 8
    call ugfx_svg_trim
    mov r12, rsi
    mov rax, rsi
    sub rax, rdi
    cmp rax, 3
    jne .even
    cmp word [rdi], 'od'
    jne .general
    cmp byte [rdi + 2], 'd'
    jne .general
    mov eax, 2
    mov edx, 1
    jmp .ok
.even:
    cmp rax, 4
    jne .general
    cmp dword [rdi], 'even'
    jne .general
    mov eax, 2
    xor edx, edx
    jmp .ok
.general:
    mov ebx, 1                          ; the sign
    cmp rdi, r12
    jae .bad
    movzx eax, byte [rdi]
    cmp al, '+'
    je .signed
    cmp al, '-'
    jne .number
    mov ebx, -1
.signed:
    inc rdi
.number:
    mov rsi, r12
    call css_digits
    jc .no_number
    mov r8d, eax
    mov r9d, 1
    jmp .n
.no_number:
    mov r8d, 1
    xor r9d, r9d
.n:
    cmp rdi, r12
    jae .plain
    movzx eax, byte [rdi]
    or al, 0x20
    cmp al, 'n'
    jne .plain
    mov eax, r8d
    imul eax, ebx
    mov [rsp], eax                      ; a
    inc rdi
    mov rsi, r12
    call css_ws
    xor edx, edx
    cmp rdi, r12
    jae .an
    movzx eax, byte [rdi]
    mov ebx, 1
    cmp al, '+'
    je .b_signed
    mov ebx, -1
    cmp al, '-'
    jne .bad
.b_signed:
    inc rdi
    mov rsi, r12
    call css_ws
    call css_digits
    jc .bad
    cmp rdi, r12
    jne .bad
    imul eax, ebx
    mov edx, eax
.an:
    mov eax, [rsp]
    jmp .ok
.plain:
    test r9d, r9d
    jz .bad
    cmp rdi, r12
    jne .bad
    mov edx, r8d
    imul edx, ebx
    xor eax, eax
.ok:
    clc
    jmp .out
.bad:
    stc
.out:
    lea rsp, [rsp + 8]                  ; (CF kept)
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; css_add_rule — rdi / rsi = one selector (untrimmed), rdx / rcx = its
;   declarations, r15 = scan frame -> rax = 0 or -ENOMEM; a selector not
;   supported is left out. It is compiled into simple selectors (SM_*), each
;   marking where a compound starts and the combinator before it; the
;   specificity counts ids 10000, classes / attributes / pseudo-classes
;   100, types 1.
; -----------------------------------------------------------------------------
%define CA_DECL     0
%define CA_DECL_END 8
%define CA_SPEC     16                  ; u32
%define CA_COUNT    20                  ; u32 simples
%define CA_NEW      24                  ; u32 1: the next simple starts a compound
%define CA_COMB     28                  ; u32 its combinator
%define CA_NCOMP    32                  ; u32 compounds
%define CA_TMP      40
%define CA_S        48                  ; SM_SIZE x 32
%define CA_SIZE     (((CA_S + 32 * SM_SIZE + 15) & ~15) + 8)

css_add_rule:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, CA_SIZE
    mov [rsp + CA_DECL], rdx
    mov [rsp + CA_DECL_END], rcx
    call ugfx_svg_trim
    mov r12, rdi
    mov r13, rsi
    cmp r12, r13
    jae .skip
    xor eax, eax
    mov [rsp + CA_SPEC], eax
    mov [rsp + CA_COUNT], eax
    mov [rsp + CA_COMB], eax
    mov [rsp + CA_NCOMP], eax
    mov dword [rsp + CA_NEW], 1
.next:
    cmp r12, r13
    jae .end
    movzx eax, byte [r12]
    cmp al, ' '
    jbe .combinator
    cmp al, '>'
    je .combinator
    cmp al, '+'
    je .combinator
    cmp al, '~'
    je .combinator
    ; a simple selector: its slot, cleared
    mov ecx, [rsp + CA_COUNT]
    cmp ecx, 32
    jae .skip
    imul r14, rcx, SM_SIZE
    lea r14, [rsp + CA_S + r14]
    xor ecx, ecx
.clear:
    mov qword [r14 + rcx * 8], 0
    inc ecx
    cmp ecx, SM_SIZE / 8
    jb .clear
    movzx eax, byte [r12]
    cmp al, '*'
    je .universal
    cmp al, '.'
    je .class
    cmp al, '#'
    je .id
    cmp al, '['
    je .attribute
    cmp al, ':'
    je .pseudo
    call css_ident
    jne .skip
    ; a type, first in its compound
    cmp dword [rsp + CA_NEW], 0
    je .skip
    mov byte [r14 + SM_KIND], SK_TYPE
    mov [r14 + SM_NAME], r12
    mov rdi, r12
    mov rsi, r13
    call css_run
    mov [r14 + SM_NAME_END], rdi
    mov r12, rdi
    add dword [rsp + CA_SPEC], 1
    jmp .emit
.universal:
    cmp dword [rsp + CA_NEW], 0
    je .skip
    mov byte [r14 + SM_KIND], SK_ANY
    inc r12
    jmp .emit
.class:
    mov byte [r14 + SM_KIND], SK_CLASS
    mov ebx, 100
    jmp .named
.id:
    mov byte [r14 + SM_KIND], SK_ID
    mov ebx, 10000
.named:
    lea rdi, [r12 + 1]
    mov rsi, r13
    call css_run
    lea rax, [r12 + 1]
    cmp rdi, rax
    je .skip
    mov [r14 + SM_NAME], rax
    mov [r14 + SM_NAME_END], rdi
    mov r12, rdi
    add [rsp + CA_SPEC], ebx
    jmp .emit
.attribute:
    ; [name], [name op value]: value an identifier or quoted
    mov byte [r14 + SM_KIND], SK_ATTR
    lea rdi, [r12 + 1]
    mov rsi, r13
    call css_ws
    mov rbx, rdi
    call css_run
    cmp rdi, rbx
    je .skip
    mov [r14 + SM_NAME], rbx
    mov [r14 + SM_NAME_END], rdi
    call css_ws
    cmp rdi, r13
    jae .skip
    cmp byte [rdi], ']'
    je .attr_close
    mov ecx, 1
    cmp byte [rdi], '='
    je .op_one
    lea rax, [rdi + 1]
    cmp rax, r13
    jae .skip
    cmp byte [rdi + 1], '='
    jne .skip
    movzx eax, byte [rdi]
    mov ecx, 2
    cmp al, '~'
    je .op_two
    mov ecx, 3
    cmp al, '|'
    je .op_two
    mov ecx, 4
    cmp al, '^'
    je .op_two
    mov ecx, 5
    cmp al, '$'
    je .op_two
    mov ecx, 6
    cmp al, '*'
    jne .skip
.op_two:
    inc rdi
.op_one:
    inc rdi
    mov [r14 + SM_OP], cl
    call css_ws
    cmp rdi, r13
    jae .skip
    movzx eax, byte [rdi]
    cmp al, '"'
    je .quoted
    cmp al, 39
    je .quoted
    mov rbx, rdi
    call css_run
    cmp rdi, rbx
    je .skip
    mov [r14 + SM_VALUE], rbx
    mov [r14 + SM_VALUE_END], rdi
    jmp .attr_end
.quoted:
    lea rbx, [rdi + 1]
    mov rdx, rbx
.q_scan:
    cmp rdx, r13
    jae .skip
    cmp [rdx], al
    je .q_end
    inc rdx
    jmp .q_scan
.q_end:
    mov [r14 + SM_VALUE], rbx
    mov [r14 + SM_VALUE_END], rdx
    lea rdi, [rdx + 1]
.attr_end:
    call css_ws
    cmp rdi, r13
    jae .skip
    cmp byte [rdi], ']'
    jne .skip
.attr_close:
    lea r12, [rdi + 1]
    add dword [rsp + CA_SPEC], 100
    jmp .emit
.pseudo:
    lea rdi, [r12 + 1]
    mov rsi, r13
    mov rbx, rdi
    call css_run
    mov [rsp + CA_TMP], rdi
    mov rsi, rdi
    mov rdi, rbx
    lea rdx, [rel css_pseudos]
    call ugfx_svg_lookup
    cmp eax, 0
    jle .skip
    mov [r14 + SM_KIND], al
    mov rdi, [rsp + CA_TMP]
    cmp eax, SK_NTH
    jb .pseudo_done
    cmp eax, SK_NTH_LAST
    ja .pseudo_done
    ; (an+b)
    cmp rdi, r13
    jae .skip
    cmp byte [rdi], '('
    jne .skip
    lea rbx, [rdi + 1]
    mov rdx, rbx
.paren:
    cmp rdx, r13
    jae .skip
    cmp byte [rdx], ')'
    je .paren_end
    inc rdx
    jmp .paren
.paren_end:
    mov [rsp + CA_TMP], rdx
    mov rdi, rbx
    mov rsi, rdx
    call css_nth
    jc .skip
    mov [r14 + SM_A], eax
    mov [r14 + SM_B], edx
    mov rdi, [rsp + CA_TMP]
    inc rdi
.pseudo_done:
    mov r12, rdi
    add dword [rsp + CA_SPEC], 100
.emit:
    mov eax, [rsp + CA_NEW]
    mov [r14 + SM_NEW], al
    add [rsp + CA_NCOMP], eax
    mov eax, [rsp + CA_COMB]
    mov [r14 + SM_COMB], al
    mov dword [rsp + CA_NEW], 0
    mov dword [rsp + CA_COMB], 0
    inc dword [rsp + CA_COUNT]
    jmp .next
.combinator:
    ; white space and / or one of > + ~ after a compound
    cmp dword [rsp + CA_NEW], 0
    jne .skip
    mov rdi, r12
    mov rsi, r13
    call css_ws
    mov ecx, CB_DESCENDANT
    cmp rdi, r13
    jae .comb_set
    movzx eax, byte [rdi]
    mov ecx, CB_CHILD
    cmp al, '>'
    je .comb_char
    mov ecx, CB_NEXT
    cmp al, '+'
    je .comb_char
    mov ecx, CB_LATER
    cmp al, '~'
    je .comb_char
    mov ecx, CB_DESCENDANT
    jmp .comb_set
.comb_char:
    inc rdi
    call css_ws
.comb_set:
    mov [rsp + CA_COMB], ecx
    mov dword [rsp + CA_NEW], 1
    mov r12, rdi
    jmp .next
.end:
    cmp dword [rsp + CA_NEW], 0
    jne .skip                           ; ends with a combinator
    cmp dword [rsp + CA_NCOMP], 16
    ja .skip
    ; the rule, its simples in the arena
    mov rbx, [r15 + SC_DEFS]
    mov rdi, [rbx + UgfxSvgDefs_arena]
    imul esi, [rsp + CA_COUNT], SM_SIZE
    call arena_alloc
    test rax, rax
    jz .nomem
    mov r14, rax
    mov rdi, rax
    lea rsi, [rsp + CA_S]
    imul ecx, [rsp + CA_COUNT], SM_SIZE
    rep movsb
    call defs_new_rule
    test rax, rax
    jz .nomem
    mov ecx, [rsp + CA_SPEC]
    mov [rax + RL_SPEC], ecx
    mov ecx, [rsp + CA_COUNT]
    mov [rax + RL_COUNT], ecx
    mov [rax + RL_SIMPLES], r14
    mov rdx, [rsp + CA_DECL]
    mov [rax + RL_DECL], rdx
    mov rdx, [rsp + CA_DECL_END]
    mov [rax + RL_DECL_END], rdx
.skip:
    xor eax, eax
    jmp .out
.nomem:
    mov rax, -(ENOMEM)
.out:
    add rsp, CA_SIZE
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; r15 = scan frame -> rax = a new rule slot (0: out of memory)
defs_new_rule:
    push rbx
    mov rbx, [r15 + SC_DEFS]
    mov eax, [rbx + UgfxSvgDefs_nrules]
    cmp eax, [rbx + UgfxSvgDefs_rulecap]
    jb .room
    mov ecx, [rbx + UgfxSvgDefs_rulecap]
    add ecx, ecx
    cmp ecx, 16
    jae .grow
    mov ecx, 16
.grow:
    push rcx
    mov rdi, [rbx + UgfxSvgDefs_arena]
    imul esi, ecx, RL_SIZE
    call arena_alloc
    pop rcx
    test rax, rax
    jz .fail
    mov [rbx + UgfxSvgDefs_rulecap], ecx
    mov rdi, rax
    mov rsi, [rbx + UgfxSvgDefs_rules]
    mov ecx, [rbx + UgfxSvgDefs_nrules]
    imul ecx, ecx, RL_SIZE
    mov rdx, rax
    rep movsb
    mov [rbx + UgfxSvgDefs_rules], rdx
.room:
    mov eax, [rbx + UgfxSvgDefs_nrules]
    inc dword [rbx + UgfxSvgDefs_nrules]
    imul rax, rax, RL_SIZE
    add rax, [rbx + UgfxSvgDefs_rules]
    pop rbx
    ret
.fail:
    xor eax, eax
    pop rbx
    ret

; r15 = scan frame: the rules sorted by specificity, stably (insertion)
defs_sort_rules:
    push rbx
    push r12
    sub rsp, RL_SIZE + 8
    mov rbx, [r15 + SC_DEFS]
    mov r12d, 1
.next:
    cmp r12d, [rbx + UgfxSvgDefs_nrules]
    jae .done
    ; hold rule i, shift larger ones up
    imul rsi, r12, RL_SIZE
    add rsi, [rbx + UgfxSvgDefs_rules]
    mov rdi, rsp
    mov ecx, RL_SIZE
    rep movsb
    mov r8d, r12d
.shift:
    test r8d, r8d
    jz .place
    lea eax, [r8 - 1]
    imul rax, rax, RL_SIZE
    add rax, [rbx + UgfxSvgDefs_rules]
    mov ecx, [rax + RL_SPEC]
    cmp ecx, [rsp + RL_SPEC]
    jbe .place
    mov rsi, rax
    lea rdi, [rax + RL_SIZE]
    mov ecx, RL_SIZE
    rep movsb
    dec r8d
    jmp .shift
.place:
    imul rdi, r8, RL_SIZE
    add rdi, [rbx + UgfxSvgDefs_rules]
    mov rsi, rsp
    mov ecx, RL_SIZE
    rep movsb
    inc r12d
    jmp .next
.done:
    add rsp, RL_SIZE + 8
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ugfx_svg_defs_rule — rdi = const UgfxSvgDefs*, esi = rule index (in
;   cascade order, below UgfxSvgDefs_nrules), rdx = const UgfxSvgSel*
;   (its tag) -> rax = the rule's declarations and rdx their end if it
;   applies to the element, else rax = 0
; -----------------------------------------------------------------------------
global ugfx_svg_defs_rule
ugfx_svg_defs_rule:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    xor eax, eax
    cmp esi, [rbx + UgfxSvgDefs_nrules]
    jae .out
    imul r12, rsi, RL_SIZE
    add r12, [rbx + UgfxSvgDefs_rules]
    mov rdi, [rdx + UgfxSvgSel_tag]
    call defs_element_of
    test eax, eax
    js .no
    mov edx, eax
    mov rdi, [r12 + RL_SIMPLES]
    mov ecx, [r12 + RL_COUNT]
    call css_match
    test eax, eax
    jz .no
    mov rax, [r12 + RL_DECL]
    mov rdx, [r12 + RL_DECL_END]
    jmp .out
.no:
    xor eax, eax
.out:
    pop r13
    pop r12
    pop rbx
    ret

; rbx = defs, rdi = a start tag's '<' -> eax = its element, -1 if none
;   (the table is in document order: a binary search)
defs_element_of:
    mov r8, [rbx + UgfxSvgDefs_elems]
    xor ecx, ecx
    mov edx, [rbx + UgfxSvgDefs_nelems]
.search:
    cmp ecx, edx
    jae .none
    lea eax, [rcx + rdx]
    shr eax, 1
    imul r9, rax, EL_SIZE
    mov r10, [r8 + r9 + EL_TAG]
    cmp r10, rdi
    je .found
    jb .right
    mov edx, eax
    jmp .search
.right:
    lea ecx, [rax + 1]
    jmp .search
.found:
    ret
.none:
    mov eax, -1
    ret

; rbx = defs, rdi = simples, ecx = the end of a compound, edx = an element
;   -> eax = 1 when the selector up to there matches it: the compound
;   itself, then the one before through its combinator (ancestors for
;   descendant, the parent for child, the previous sibling for next, any
;   earlier sibling for later)
css_match:
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov r12, rdi
    mov r13d, edx
    lea r14d, [rcx - 1]
.start:
    imul rax, r14, SM_SIZE
    cmp byte [r12 + rax + SM_NEW], 0
    jne .have_start
    dec r14d
    jmp .start
.have_start:
    mov edi, r14d
    mov esi, ecx
    mov edx, r13d
    call css_compound
    test eax, eax
    jz .no
    test r14d, r14d
    jz .yes
    imul rax, r14, SM_SIZE
    movzx r15d, byte [r12 + rax + SM_COMB]
    cmp r15d, CB_NEXT
    jae .siblings
.up:
    mov eax, r13d
    imul rax, rax, EL_SIZE
    add rax, [rbx + UgfxSvgDefs_elems]
    mov r13d, [rax + EL_PARENT]
    test r13d, r13d
    js .no
    mov rdi, r12
    mov ecx, r14d
    mov edx, r13d
    call css_match
    test eax, eax
    jnz .yes
    cmp r15d, CB_CHILD
    je .no
    jmp .up
.siblings:
    mov eax, r13d
    imul rax, rax, EL_SIZE
    add rax, [rbx + UgfxSvgDefs_elems]
    mov r13d, [rax + EL_PREV]
    test r13d, r13d
    js .no
    mov rdi, r12
    mov ecx, r14d
    mov edx, r13d
    call css_match
    test eax, eax
    jnz .yes
    cmp r15d, CB_NEXT
    je .no
    jmp .siblings
.yes:
    mov eax, 1
    jmp .out
.no:
    xor eax, eax
.out:
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    ret

; rbx = defs, r12 = simples, edi / esi = a compound's (start, end), edx =
;   an element -> eax = 1 when each of them holds for it (its tag read
;   again for its name and attributes, values as written)
%define CP_XML      0
%define CP_ATTR     UgfxSvgXml_SIZE
%define CP_I        (CP_ATTR + UgfxSvgAttr_SIZE)    ; u32
%define CP_END      (CP_I + 4)                      ; u32
%define CP_REC      (CP_I + 8)                      ; the element's record
%define CP_N        (CP_I + 16)                     ; an attribute name sought
%define CP_NE       (CP_I + 24)
%define CP_SIZE     (((CP_I + 32 + 15) & ~15) + 8)

css_compound:
    push r13
    push r14
    sub rsp, CP_SIZE
    mov [rsp + CP_I], edi
    mov [rsp + CP_END], esi
    mov eax, edx
    imul rax, rax, EL_SIZE
    add rax, [rbx + UgfxSvgDefs_elems]
    mov [rsp + CP_REC], rax
    mov rcx, [rax + EL_TAG]
    mov [rsp + CP_XML + UgfxSvgXml_cur], rcx
    mov rcx, [rbx + UgfxSvgDefs_end]
    mov [rsp + CP_XML + UgfxSvgXml_end], rcx
    mov qword [rsp + CP_XML + UgfxSvgXml_arena], 0
    lea rdi, [rsp + CP_XML]
    call ugfx_svg_xml_next
    cmp eax, 1
    jne .no
.simple:
    mov eax, [rsp + CP_I]
    cmp eax, [rsp + CP_END]
    jae .yes
    imul r13, rax, SM_SIZE
    add r13, r12
    movzx eax, byte [r13 + SM_KIND]
    cmp eax, SK_ANY
    je .ok
    cmp eax, SK_TYPE
    je .type
    cmp eax, SK_ATTR
    jbe .attribute
    mov r14, [rsp + CP_REC]
    cmp eax, SK_ROOT
    je .root
    cmp eax, SK_FIRST
    je .first
    cmp eax, SK_LAST
    je .last
    cmp eax, SK_ONLY
    je .only
    ; nth-child: its index from the start; nth-last-child: from the end
    mov ecx, [r14 + EL_INDEX]
    cmp eax, SK_NTH
    je .nth
    mov ecx, 1
    mov rdx, r14
.count:
    movsxd r8, dword [rdx + EL_NEXT]
    test r8, r8
    js .nth
    inc ecx
    imul rdx, r8, EL_SIZE
    add rdx, [rbx + UgfxSvgDefs_elems]
    jmp .count
.nth:
    ; i = a n + b for some n >= 0
    mov eax, [r13 + SM_A]
    mov r8d, [r13 + SM_B]
    test eax, eax
    jnz .nth_step
    cmp ecx, r8d
    je .ok
    jmp .no
.nth_step:
    mov r9d, eax
    mov eax, ecx
    sub eax, r8d
    cdq
    idiv r9d
    test edx, edx
    jnz .no
    test eax, eax
    js .no
    jmp .ok
.root:
    cmp dword [r14 + EL_PARENT], 0
    jl .ok
    jmp .no
.first:
    cmp dword [r14 + EL_PREV], 0
    jl .ok
    jmp .no
.last:
    cmp dword [r14 + EL_NEXT], 0
    jl .ok
    jmp .no
.only:
    cmp dword [r14 + EL_PREV], 0
    jge .no
    cmp dword [r14 + EL_NEXT], 0
    jl .ok
    jmp .no
.type:
    mov rdi, [rsp + CP_XML + UgfxSvgXml_name]
    mov rsi, [rsp + CP_XML + UgfxSvgXml_name_end]
    mov rdx, [r13 + SM_NAME]
    mov rcx, [r13 + SM_NAME_END]
    call ugfx_svg_same
    jne .no
    jmp .ok
.attribute:
    ; class, id or the attribute named: its value
    lea rdi, [rel css_class_word]
    lea rsi, [rdi + 5]
    cmp eax, SK_CLASS
    je .find_it
    lea rdi, [rel css_id_word]
    lea rsi, [rdi + 2]
    cmp eax, SK_ID
    je .find_it
    mov rdi, [r13 + SM_NAME]
    mov rsi, [r13 + SM_NAME_END]
.find_it:
    call .find
    test rax, rax
    jz .no
    movzx ecx, byte [r13 + SM_KIND]
    cmp ecx, SK_CLASS
    jne .not_class
    mov r10, [r13 + SM_NAME]
    mov r11, [r13 + SM_NAME_END]
    jmp .tokens
.not_class:
    cmp ecx, SK_ID
    jne .op
    mov rdi, rax
    mov rsi, rdx
    mov rdx, [r13 + SM_NAME]
    mov rcx, [r13 + SM_NAME_END]
    call ugfx_svg_same
    jne .no
    jmp .ok
.op:
    movzx ecx, byte [r13 + SM_OP]
    test ecx, ecx
    jz .ok                              ; [name]: there
    mov r8, rax                         ; the value
    mov r9, rdx
    mov r10, [r13 + SM_VALUE]           ; the selector's
    mov r11, [r13 + SM_VALUE_END]
    cmp ecx, 1
    je .equal
    cmp ecx, 2
    je .includes
    cmp ecx, 3
    je .dash
    ; ^= $= *=: never an empty value
    cmp r10, r11
    je .no
    mov rax, r9
    sub rax, r8                         ; its length
    mov rcx, r11
    sub rcx, r10                        ; the selector's
    cmp rax, rcx
    jb .no
    movzx edx, byte [r13 + SM_OP]
    cmp edx, 4
    je .prefix
    cmp edx, 5
    je .suffix
    ; *=: anywhere
    sub rax, rcx                        ; the last offset
    xor edx, edx
.within:
    cmp rdx, rax
    ja .no
    lea rdi, [r8 + rdx]
    mov rsi, r10
    push rcx
    push rdx
    call css_memeq
    pop rdx
    pop rcx
    je .ok
    inc rdx
    jmp .within
.prefix:
    mov rdi, r8
    mov rsi, r10
    call css_memeq
    je .ok
    jmp .no
.suffix:
    mov rdi, r9
    sub rdi, rcx
    mov rsi, r10
    call css_memeq
    je .ok
    jmp .no
.equal:
    mov rdi, r8
    mov rsi, r9
    mov rdx, r10
    mov rcx, r11
    call ugfx_svg_same
    je .ok
    jmp .no
.dash:
    ; equal, or it and '-' start the value
    mov rdi, r8
    mov rsi, r9
    mov rdx, r10
    mov rcx, r11
    push r8
    call ugfx_svg_same
    pop r8
    je .ok
    mov rax, r9
    sub rax, r8
    mov rcx, r11
    sub rcx, r10
    cmp rax, rcx
    jbe .no
    cmp byte [r8 + rcx], '-'
    jne .no
    mov rdi, r8
    mov rsi, r10
    call css_memeq
    je .ok
    jmp .no
.includes:
    ; one of its white-space separated words (the selector's is one word)
    cmp r10, r11
    je .no
    mov rdi, r10
.word:
    cmp rdi, r11
    jae .tokens_of
    cmp byte [rdi], ' '
    jbe .no
    inc rdi
    jmp .word
.tokens_of:
    mov rax, r8
    mov rdx, r9
.tokens:
    ; rax / rdx = a list, r10 / r11 = a word: in it?
    mov r8, rax
    mov r9, rdx
.t_space:
    cmp r8, r9
    jae .no
    cmp byte [r8], ' '
    ja .t_start
    inc r8
    jmp .t_space
.t_start:
    mov rdi, r8
.t_end:
    cmp r8, r9
    jae .t_compare
    cmp byte [r8], ' '
    jbe .t_compare
    inc r8
    jmp .t_end
.t_compare:
    mov rsi, r8
    mov rdx, r10
    mov rcx, r11
    push r8
    push r9
    call ugfx_svg_same
    pop r9
    pop r8
    je .ok
    jmp .t_space
.ok:
    inc dword [rsp + CP_I]
    jmp .simple
.yes:
    mov eax, 1
    jmp .out
.no:
    xor eax, eax
.out:
    add rsp, CP_SIZE
    pop r14
    pop r13
    ret
; rdi / rsi = an attribute name -> rax / rdx = its value in the tag (rax =
;   0: not there) (frame at rsp + 16)
.find:
    sub rsp, 8
    mov [rsp + 16 + CP_N], rdi
    mov [rsp + 16 + CP_NE], rsi
    mov qword [rsp + 16 + CP_ATTR + UgfxSvgAttr_cur], 0
.f_next:
    lea rdi, [rsp + 16 + CP_XML]
    lea rsi, [rsp + 16 + CP_ATTR]
    call ugfx_svg_xml_attr
    test eax, eax
    jz .f_none
    mov rdi, [rsp + 16 + CP_ATTR + UgfxSvgAttr_name]
    mov rsi, [rsp + 16 + CP_ATTR + UgfxSvgAttr_name_end]
    mov rdx, [rsp + 16 + CP_N]
    mov rcx, [rsp + 16 + CP_NE]
    call ugfx_svg_same
    jne .f_next
    mov rax, [rsp + 16 + CP_ATTR + UgfxSvgAttr_val]
    mov rdx, [rsp + 16 + CP_ATTR + UgfxSvgAttr_val_end]
    add rsp, 8
    ret
.f_none:
    xor eax, eax
    add rsp, 8
    ret

; rdi, rsi = two byte runs, rcx = their length -> ZF = 1 when equal
css_memeq:
    test rcx, rcx
    jz .equal
.byte:
    mov al, [rdi]
    cmp al, [rsi]
    jne .out
    inc rdi
    inc rsi
    dec rcx
    jnz .byte
.equal:
    cmp al, al
.out:
    ret

; r15 = scan frame, ebx = 1 a start tag (in SC_XML) / 2 an end tag: the
;   element table (parent, siblings, index) and the open elements kept
;   -> rax = 0 or -ENOMEM
defs_element:
    push r12
    push r13
    sub rsp, 8
    cmp ebx, 2
    je .end_tag
    mov r12, [r15 + SC_DEFS]
    mov eax, [r12 + UgfxSvgDefs_nelems]
    cmp eax, [r12 + UgfxSvgDefs_elemcap]
    jb .room
    mov ecx, [r12 + UgfxSvgDefs_elemcap]
    add ecx, ecx
    cmp ecx, 64
    jae .grow
    mov ecx, 64
.grow:
    mov r13d, ecx
    mov rdi, [r12 + UgfxSvgDefs_arena]
    imul esi, ecx, EL_SIZE
    call arena_alloc
    test rax, rax
    jz .nomem
    mov rdi, rax
    mov rsi, [r12 + UgfxSvgDefs_elems]
    mov ecx, [r12 + UgfxSvgDefs_nelems]
    imul ecx, ecx, EL_SIZE
    rep movsb
    mov [r12 + UgfxSvgDefs_elems], rax
    mov [r12 + UgfxSvgDefs_elemcap], r13d
.room:
    mov r13d, [r12 + UgfxSvgDefs_nelems]        ; its index
    inc dword [r12 + UgfxSvgDefs_nelems]
    imul rdi, r13, EL_SIZE
    add rdi, [r12 + UgfxSvgDefs_elems]
    mov rax, [r15 + SC_XML + UgfxSvgXml_name]
    dec rax
    mov [rdi + EL_TAG], rax
    mov dword [rdi + EL_NEXT], -1
    mov dword [rdi + EL_PARENT], -1
    mov dword [rdi + EL_PREV], -1
    mov dword [rdi + EL_INDEX], 1
    mov ecx, [r15 + SC_DEPTH]
    cmp ecx, SC_MAX_DEPTH
    jae .opened                         ; too deep to place
    test ecx, ecx
    jz .no_parent
    mov eax, [r15 + SC_OPEN + rcx * 4 - 4]
    mov [rdi + EL_PARENT], eax
.no_parent:
    mov eax, [r15 + SC_LAST + rcx * 4]
    mov [rdi + EL_PREV], eax
    test eax, eax
    js .first
    imul rdx, rax, EL_SIZE
    add rdx, [r12 + UgfxSvgDefs_elems]
    mov [rdx + EL_NEXT], r13d
    mov eax, [rdx + EL_INDEX]
    inc eax
    mov [rdi + EL_INDEX], eax
.first:
    mov [r15 + SC_LAST + rcx * 4], r13d
    cmp dword [r15 + SC_XML + UgfxSvgXml_self], 0
    jne .done
    mov [r15 + SC_OPEN + rcx * 4], r13d
    mov dword [r15 + SC_LAST + rcx * 4 + 4], -1
.opened:
    cmp dword [r15 + SC_XML + UgfxSvgXml_self], 0
    jne .done
    inc dword [r15 + SC_DEPTH]
    jmp .done
.end_tag:
    cmp dword [r15 + SC_DEPTH], 0
    je .done
    dec dword [r15 + SC_DEPTH]
.done:
    xor eax, eax
    jmp .out
.nomem:
    mov rax, -(ENOMEM)
.out:
    add rsp, 8
    pop r13
    pop r12
    ret

; r15 = scan frame, a start tag read: its id attribute recorded with where
;   the tag starts -> rax = 0 or -ENOMEM
defs_record_id:
    push rbx
    push r12
    sub rsp, 8
    mov qword [r15 + SC_ATTR + UgfxSvgAttr_cur], 0
.attr:
    lea rdi, [r15 + SC_XML]
    lea rsi, [r15 + SC_ATTR]
    call ugfx_svg_xml_attr
    test eax, eax
    jz .none
    mov rdi, [r15 + SC_ATTR + UgfxSvgAttr_name]
    mov rax, [r15 + SC_ATTR + UgfxSvgAttr_name_end]
    sub rax, rdi
    cmp rax, 2
    jne .attr
    cmp word [rdi], 'id'
    jne .attr
    ; room for one more
    mov rbx, [r15 + SC_DEFS]
    mov eax, [rbx + UgfxSvgDefs_nids]
    cmp eax, [rbx + UgfxSvgDefs_idcap]
    jb .room
    mov ecx, [rbx + UgfxSvgDefs_idcap]
    add ecx, ecx
    cmp ecx, 32
    jae .grow
    mov ecx, 32
.grow:
    mov r12d, ecx
    mov rdi, [rbx + UgfxSvgDefs_arena]
    imul esi, ecx, 24
    call arena_alloc
    test rax, rax
    jz .nomem
    mov [rbx + UgfxSvgDefs_idcap], r12d
    mov rdi, rax
    mov rsi, [rbx + UgfxSvgDefs_ids]
    mov ecx, [rbx + UgfxSvgDefs_nids]
    imul ecx, ecx, 24
    mov rdx, rax
    rep movsb
    mov [rbx + UgfxSvgDefs_ids], rdx
.room:
    mov eax, [rbx + UgfxSvgDefs_nids]
    inc dword [rbx + UgfxSvgDefs_nids]
    imul r12, rax, 24
    add r12, [rbx + UgfxSvgDefs_ids]
    mov rdi, [r15 + SC_ATTR + UgfxSvgAttr_val]
    mov rsi, [r15 + SC_ATTR + UgfxSvgAttr_val_end]
    call ugfx_svg_trim
    mov [r12], rdi
    mov [r12 + 8], rsi
    mov rax, [r15 + SC_XML + UgfxSvgXml_name]
    dec rax                             ; the '<'
    mov [r12 + 16], rax
.none:
    xor eax, eax
    jmp .out
.nomem:
    mov rax, -(ENOMEM)
.out:
    add rsp, 8
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ugfx_svg_defs_id — rdi = const UgfxSvgDefs*, rsi = id, rdx = id end
;   -> rax = the '<' of the first element with that id, or 0
; -----------------------------------------------------------------------------
global ugfx_svg_defs_id
ugfx_svg_defs_id:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov r12, rsi
    mov r13, rdx
    mov rbx, [rdi + UgfxSvgDefs_ids]
    mov r14d, [rdi + UgfxSvgDefs_nids]
.next:
    xor eax, eax
    test r14d, r14d
    jz .out
    mov rdi, [rbx]
    mov rsi, [rbx + 8]
    mov rdx, r12
    mov rcx, r13
    call ugfx_svg_same
    je .found
    add rbx, 24
    dec r14d
    jmp .next
.found:
    mov rax, [rbx + 16]
.out:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; r15 = scan frame -> rax = a new, empty gradient (0: out of memory)
defs_new_gradient:
    push rbx
    mov rbx, [r15 + SC_DEFS]
    mov eax, [rbx + UgfxSvgDefs_count]
    cmp eax, [rbx + UgfxSvgDefs_cap]
    jb .room
    mov ecx, [rbx + UgfxSvgDefs_cap]
    add ecx, ecx
    cmp ecx, 8
    jae .grow
    mov ecx, 8
.grow:
    push rcx
    mov rdi, [rbx + UgfxSvgDefs_arena]
    imul esi, ecx, GR_SIZE
    call arena_alloc
    pop rcx
    test rax, rax
    jz .fail
    mov [rbx + UgfxSvgDefs_cap], ecx
    mov rdi, rax
    mov rsi, [rbx + UgfxSvgDefs_grads]
    mov ecx, [rbx + UgfxSvgDefs_count]
    imul ecx, ecx, GR_SIZE
    mov rdx, rax
    rep movsb
    mov [rbx + UgfxSvgDefs_grads], rdx
.room:
    mov eax, [rbx + UgfxSvgDefs_count]
    inc dword [rbx + UgfxSvgDefs_count]
    imul rax, rax, GR_SIZE
    add rax, [rbx + UgfxSvgDefs_grads]
    mov rdi, rax
    mov rdx, rax
    xor eax, eax
    mov ecx, GR_SIZE
    rep stosb
    mov rax, rdx
    pop rbx
    ret
.fail:
    xor eax, eax
    pop rbx
    ret

; the current tag's attributes into gradient r13 (r15 = scan frame)
defs_gradient_attrs:
    push rbx
    push r12
    sub rsp, 8
    lea rdi, [r13 + GR_M]
    call umath_affine2_identity
    mov qword [r15 + SC_ATTR + UgfxSvgAttr_cur], 0
.attr:
    lea rdi, [r15 + SC_XML]
    lea rsi, [r15 + SC_ATTR]
    call ugfx_svg_xml_attr
    test eax, eax
    jz .done
    mov rdi, [r15 + SC_ATTR + UgfxSvgAttr_name]
    mov rsi, [r15 + SC_ATTR + UgfxSvgAttr_name_end]
    lea rdx, [rel defs_attributes]
    call ugfx_svg_lookup
    mov ebx, eax
    mov rdi, [r15 + SC_ATTR + UgfxSvgAttr_val]
    mov rsi, [r15 + SC_ATTR + UgfxSvgAttr_val_end]
    cmp ebx, DA_ID
    je .id
    cmp ebx, DA_HREF
    je .href
    cmp ebx, DA_UNITS
    je .keyword
    cmp ebx, DA_SPREAD
    je .keyword
    cmp ebx, DA_TRANSFORM
    je .transform
    cmp ebx, DA_VALUE
    jb .attr
    cmp ebx, DA_VALUE + V_COUNT
    jae .attr
    ; a value, maybe a percentage
    sub ebx, DA_VALUE
    mov r12, rsi
    call ugfx_svg_number
    test rax, rax
    jz .attr
    movsd [r13 + GR_VAL + rbx * 8], xmm0
    bts dword [r13 + GR_HAVE], ebx
    btr dword [r13 + GR_PCT], ebx
    cmp rax, r12
    jae .attr
    cmp byte [rax], '%'
    jne .attr
    mulsd xmm0, [rel defs_hundredth]
    movsd [r13 + GR_VAL + rbx * 8], xmm0
    bts dword [r13 + GR_PCT], ebx
    jmp .attr
.id:
    call ugfx_svg_trim
    mov [r13 + GR_ID], rdi
    mov [r13 + GR_ID_END], rsi
    jmp .attr
.href:
    call ugfx_svg_trim
    cmp rdi, rsi
    jae .attr
    cmp byte [rdi], '#'
    jne .attr
    inc rdi
    mov [r13 + GR_HREF], rdi
    mov [r13 + GR_HREF_END], rsi
    jmp .attr
.keyword:
    call ugfx_svg_trim
    lea rdx, [rel defs_keywords]
    call ugfx_svg_lookup
    cmp eax, -1
    je .attr
    cmp ebx, DA_UNITS
    jne .spread
    cmp eax, 101
    ja .attr
    cmp eax, 100
    jb .attr
    sub eax, 100
    mov [r13 + GR_UNITS], eax
    bts dword [r13 + GR_HAVE], H_UNITS
    jmp .attr
.spread:
    cmp eax, 110
    jb .attr
    cmp eax, 112
    ja .attr
    sub eax, 110
    mov [r13 + GR_SPREAD], eax
    bts dword [r13 + GR_HAVE], H_SPREAD
    jmp .attr
.transform:
    lea rdx, [r13 + GR_M]
    call ugfx_svg_transform
    test rax, rax
    jnz .attr
    bts dword [r13 + GR_HAVE], H_TRANSFORM
    jmp .attr
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret

; the current <stop> into gradient r13 -> rax = 0 or -ENOMEM
defs_stop:
    push rbx
    push r12
    push r14
    ; defaults: offset 0, black, opacity 1
    xorpd xmm0, xmm0
    movsd [r15 + SC_STOP], xmm0
    mov dword [r15 + SC_STOP + 12], 0xFF000000
    movsd xmm0, [rel defs_one]
    movsd [r15 + SC_STOP + 16], xmm0
    mov qword [r15 + SC_STOP + 24], 0   ; no style yet
    mov qword [r15 + SC_ATTR + UgfxSvgAttr_cur], 0
.attr:
    lea rdi, [r15 + SC_XML]
    lea rsi, [r15 + SC_ATTR]
    call ugfx_svg_xml_attr
    test eax, eax
    jz .attrs_done
    mov rdi, [r15 + SC_ATTR + UgfxSvgAttr_name]
    mov rsi, [r15 + SC_ATTR + UgfxSvgAttr_name_end]
    lea rdx, [rel defs_attributes]
    call ugfx_svg_lookup
    mov rdi, [r15 + SC_ATTR + UgfxSvgAttr_val]
    mov rsi, [r15 + SC_ATTR + UgfxSvgAttr_val_end]
    cmp eax, DA_STYLE
    je .style
    call defs_stop_property
    jmp .attr
.style:
    ; declarations stop-color / stop-opacity, after the attributes
    mov [r15 + SC_STOP + 24], rdi
    mov [r15 + SC_STOP + 32], rsi
    jmp .attr
.attrs_done:
    cmp qword [r15 + SC_STOP + 24], 0
    je .store
    mov r12, [r15 + SC_STOP + 24]
.decl:
    mov rsi, [r15 + SC_STOP + 32]
    cmp r12, rsi
    jae .store
    mov rdi, r12
.colon:
    cmp rdi, rsi
    jae .store
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
    mov rbx, rdi                        ; ':'
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
    mov rsi, rbx
    call ugfx_svg_trim
    lea rdx, [rel defs_attributes]
    call ugfx_svg_lookup
    lea r12, [r14 + 1]
    lea rdi, [rbx + 1]
    mov rsi, r14
    call defs_stop_property
    jmp .decl
.store:
    mov qword [r15 + SC_STOP + 24], 0
    ; room for one more stop
    mov eax, [r13 + GR_NSTOPS]
    cmp eax, [r13 + GR_STOPCAP]
    jb .room
    mov ecx, [r13 + GR_STOPCAP]
    add ecx, ecx
    cmp ecx, 8
    jae .grow
    mov ecx, 8
.grow:
    push rcx
    sub rsp, 8
    mov rax, [r15 + SC_DEFS]
    mov rdi, [rax + UgfxSvgDefs_arena]
    mov esi, ecx
    shl esi, 4                          ; UgfxStop_SIZE
    call arena_alloc
    add rsp, 8
    pop rcx
    test rax, rax
    jz .nomem
    mov [r13 + GR_STOPCAP], ecx
    mov rdi, rax
    mov rsi, [r13 + GR_STOPS]
    mov ecx, [r13 + GR_NSTOPS]
    shl ecx, 4
    mov rdx, rax
    rep movsb
    mov [r13 + GR_STOPS], rdx
.room:
    mov eax, [r13 + GR_NSTOPS]
    inc dword [r13 + GR_NSTOPS]
    shl rax, 4
    add rax, [r13 + GR_STOPS]
    movsd xmm0, [r15 + SC_STOP]
    movsd [rax + UgfxStop_offset], xmm0
    ; alpha = round(colour alpha x stop-opacity)
    mov edx, [r15 + SC_STOP + 12]
    mov ecx, edx
    shr ecx, 24
    cvtsi2sd xmm0, ecx
    mulsd xmm0, [r15 + SC_STOP + 16]
    addsd xmm0, [rel defs_half]
    cvttsd2si ecx, xmm0
    shl ecx, 24
    and edx, 0x00FFFFFF
    or edx, ecx
    mov [rax + UgfxStop_color], edx
    xor eax, eax
    jmp .out
.nomem:
    mov rax, -(ENOMEM)
.out:
    pop r14
    pop r12
    pop rbx
    ret

; eax = attribute id, rdi / rsi = value: offset, stop-color or stop-opacity
;   into the stop being read
defs_stop_property:
    push rbx
    mov ebx, eax
    cmp ebx, DA_STOP_COLOR
    je .colour
    cmp ebx, DA_OFFSET
    je .number
    cmp ebx, DA_STOP_OPACITY
    jne .out
.number:
    push rsi
    call ugfx_svg_number
    pop rsi
    test rax, rax
    jz .out
    cmp rax, rsi
    jae .clamp
    cmp byte [rax], '%'
    jne .clamp
    mulsd xmm0, [rel defs_hundredth]
.clamp:
    xorpd xmm1, xmm1
    maxsd xmm0, xmm1
    minsd xmm0, [rel defs_one]
    cmp ebx, DA_OFFSET
    jne .opacity
    movsd [r15 + SC_STOP], xmm0
    jmp .out
.opacity:
    movsd [r15 + SC_STOP + 16], xmm0
    jmp .out
.colour:
    call ugfx_svg_colour
    cmp eax, 1
    je .colour_set
    mov edx, 0xFF000000                 ; currentColor, inherit: black
    cmp eax, 2
    je .colour_set
    cmp eax, 3
    je .colour_set
    test eax, eax
    jnz .out                            ; invalid: unchanged
    xor edx, edx                        ; none: transparent
.colour_set:
    mov [r15 + SC_STOP + 12], edx
.out:
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ugfx_svg_defs_paint — rdi = const UgfxSvgDefs*, rsi = id, rdx = id end,
;   rcx = const UgfxPath* (the shape), r8 = const double viewport[2] (w, h),
;   r9 = UgfxPaint* (out), [rsp + 8] = double matrix[6] (out: paint ->
;   user space) -> eax = -1 no such gradient, 0 nothing, 1 solid colour in
;   edx, 3 a paint
; -----------------------------------------------------------------------------
%define RP_DEFS     0
%define RP_PATH     8
%define RP_VIEW     16
%define RP_PAINT    24
%define RP_MATRIX   32
%define RP_GRAD     40                  ; the gradient named
%define RP_HAVE     48                  ; u32 what is resolved
%define RP_PCT      52
%define RP_UNITS    56
%define RP_SPREAD   60
%define RP_KIND     64
%define RP_VAL      72                  ; f64[10]
%define RP_M        152                 ; f64[6]
%define RP_STOPS    200
%define RP_NSTOPS   208                 ; u32
%define RP_BOX      216                 ; f64[4]
%define RP_T        248                 ; f64[6]
%define RP_SIZE     296

global ugfx_svg_defs_paint
ugfx_svg_defs_paint:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, RP_SIZE                    ; calls stay 16-byte aligned
    mov r15, rsp
    mov [r15 + RP_DEFS], rdi
    mov [r15 + RP_PATH], rcx
    mov [r15 + RP_VIEW], r8
    mov [r15 + RP_PAINT], r9
    mov rax, [rbp + 16]
    mov [r15 + RP_MATRIX], rax
    call defs_find                      ; rsi / rdx -> rax
    test rax, rax
    jz .missing
    mov [r15 + RP_GRAD], rax
    mov r13, rax
    mov eax, [r13 + GR_KIND]
    mov [r15 + RP_KIND], eax
    mov dword [r15 + RP_HAVE], 0
    mov dword [r15 + RP_PCT], 0
    mov dword [r15 + RP_UNITS], 0
    mov dword [r15 + RP_SPREAD], UGFX_SPREAD_PAD
    mov qword [r15 + RP_STOPS], 0
    mov dword [r15 + RP_NSTOPS], 0
    lea rdi, [r15 + RP_M]
    call umath_affine2_identity
    ; walk the href chain, taking what is not yet resolved
    xor r14d, r14d
.chain:
    call defs_take
    cmp r14d, SVG_HREF_DEPTH
    jae .resolved
    inc r14d
    mov rsi, [r13 + GR_HREF]
    test rsi, rsi
    jz .resolved
    mov rdx, [r13 + GR_HREF_END]
    call defs_find
    test rax, rax
    jz .resolved
    mov r13, rax
    jmp .chain
.resolved:
    ; stops
    mov ecx, [r15 + RP_NSTOPS]
    test ecx, ecx
    jz .nothing
    cmp ecx, 1
    je .last_colour
    ; defaults for what is still missing
    xor ecx, ecx
.default:
    cmp ecx, V_COUNT
    jae .defaults_done
    bt dword [r15 + RP_HAVE], ecx
    jc .default_next
    lea rax, [rel defs_default]
    movsd xmm0, [rax + rcx * 8]
    movsd [r15 + RP_VAL + rcx * 8], xmm0
    bts dword [r15 + RP_PCT], ecx
    cmp ecx, V_FX
    jne .default_next
    ; fx / fy default to cx / cy as given
    movsd xmm0, [r15 + RP_VAL + V_CX * 8]
    movsd [r15 + RP_VAL + V_FX * 8], xmm0
    btr dword [r15 + RP_PCT], V_FX
    bt dword [r15 + RP_PCT], V_CX
    jnc .default_next
    bts dword [r15 + RP_PCT], V_FX
.default_next:
    cmp ecx, V_FY
    jne .default_inc
    bt dword [r15 + RP_HAVE], ecx
    jc .default_inc
    movsd xmm0, [r15 + RP_VAL + V_CY * 8]
    movsd [r15 + RP_VAL + V_FY * 8], xmm0
    btr dword [r15 + RP_PCT], V_FY
    bt dword [r15 + RP_PCT], V_CY
    jnc .default_inc
    bts dword [r15 + RP_PCT], V_FY
.default_inc:
    inc ecx
    jmp .default
.defaults_done:
    ; units: the box, or user space with percentages of the viewport
    cmp dword [r15 + RP_UNITS], 0
    jne .user_space
    mov rdi, [r15 + RP_PATH]
    lea rsi, [r15 + RP_BOX]
    call ugfx_path_bounds_tight
    test rax, rax
    jnz .nothing
    movsd xmm0, [r15 + RP_BOX + 16]
    subsd xmm0, [r15 + RP_BOX]          ; w
    movsd xmm1, [r15 + RP_BOX + 24]
    subsd xmm1, [r15 + RP_BOX + 8]      ; h
    xorpd xmm2, xmm2
    ucomisd xmm0, xmm2
    jbe .nothing
    ucomisd xmm1, xmm2
    jbe .nothing
    ; matrix = [w 0 0 h x0 y0] x gradientTransform
    movsd [r15 + RP_T], xmm0
    movsd [r15 + RP_T + 8], xmm2
    movsd [r15 + RP_T + 16], xmm2
    movsd [r15 + RP_T + 24], xmm1
    movsd xmm0, [r15 + RP_BOX]
    movsd [r15 + RP_T + 32], xmm0
    movsd xmm0, [r15 + RP_BOX + 8]
    movsd [r15 + RP_T + 40], xmm0
    mov rdi, [r15 + RP_MATRIX]
    lea rsi, [r15 + RP_T]
    lea rdx, [r15 + RP_M]
    call umath_affine2_multiply
    jmp .build
.user_space:
    ; percentages of the viewport: x of w, y of h, radii of sqrt((w^2+h^2)/2)
    mov rax, [r15 + RP_VIEW]
    movsd xmm3, [rax]
    movsd xmm4, [rax + 8]
    movapd xmm5, xmm3
    mulsd xmm5, xmm3
    movapd xmm6, xmm4
    mulsd xmm6, xmm4
    addsd xmm5, xmm6
    mulsd xmm5, [rel defs_half]
    sqrtsd xmm5, xmm5
    xor ecx, ecx
.pct:
    cmp ecx, V_COUNT
    jae .pct_done
    bt dword [r15 + RP_PCT], ecx
    jnc .pct_next
    movsd xmm0, [r15 + RP_VAL + rcx * 8]
    lea rax, [rel defs_axis]
    movzx edx, byte [rax + rcx]
    cmp edx, 0
    je .pct_x
    cmp edx, 1
    je .pct_y
    mulsd xmm0, xmm5
    jmp .pct_store
.pct_x:
    mulsd xmm0, xmm3
    jmp .pct_store
.pct_y:
    mulsd xmm0, xmm4
.pct_store:
    movsd [r15 + RP_VAL + rcx * 8], xmm0
.pct_next:
    inc ecx
    jmp .pct
.pct_done:
    mov rdi, [r15 + RP_MATRIX]
    lea rsi, [r15 + RP_M]
    mov ecx, 48
    rep movsb
.build:
    mov rdi, [r15 + RP_PAINT]
    mov rax, [r15 + RP_DEFS]
    mov rsi, [rax + UgfxSvgDefs_arena]
    mov rdx, [r15 + RP_STOPS]
    mov ecx, [r15 + RP_NSTOPS]
    mov r8d, [r15 + RP_SPREAD]
    cmp dword [r15 + RP_KIND], 1
    jne .radial
    movsd xmm0, [r15 + RP_VAL + V_X1 * 8]
    movsd xmm1, [r15 + RP_VAL + V_Y1 * 8]
    movsd xmm2, [r15 + RP_VAL + V_X2 * 8]
    movsd xmm3, [r15 + RP_VAL + V_Y2 * 8]
    call ugfx_paint_linear
    test rax, rax
    jnz .last_colour                    ; the ends meet: the last colour
    jmp .painted
.radial:
    movsd xmm2, [r15 + RP_VAL + V_R * 8]
    xorpd xmm7, xmm7
    ucomisd xmm2, xmm7
    jbe .last_colour                    ; no radius: the last colour
    movsd xmm0, [r15 + RP_VAL + V_FX * 8]
    ucomisd xmm0, [r15 + RP_VAL + V_CX * 8]
    jne .two_circles
    jp .two_circles
    movsd xmm0, [r15 + RP_VAL + V_FY * 8]
    ucomisd xmm0, [r15 + RP_VAL + V_CY * 8]
    jne .two_circles
    jp .two_circles
    movsd xmm0, [r15 + RP_VAL + V_FR * 8]
    ucomisd xmm0, xmm7
    jne .two_circles
    jp .two_circles
    movsd xmm0, [r15 + RP_VAL + V_CX * 8]
    movsd xmm1, [r15 + RP_VAL + V_CY * 8]
    call ugfx_paint_radial
    test rax, rax
    jnz .last_colour
    jmp .painted
.two_circles:
    movsd xmm0, [r15 + RP_VAL + V_FX * 8]
    movsd xmm1, [r15 + RP_VAL + V_FY * 8]
    movsd xmm2, [r15 + RP_VAL + V_FR * 8]
    maxsd xmm2, xmm7                    ; fr >= 0
    movsd xmm3, [r15 + RP_VAL + V_CX * 8]
    movsd xmm4, [r15 + RP_VAL + V_CY * 8]
    movsd xmm5, [r15 + RP_VAL + V_R * 8]
    call ugfx_paint_radial2
    test rax, rax
    jnz .last_colour
.painted:
    mov eax, 3
    jmp .out
.last_colour:
    mov eax, [r15 + RP_NSTOPS]
    dec eax
    shl rax, 4
    add rax, [r15 + RP_STOPS]
    mov edx, [rax + UgfxStop_color]
    mov eax, 1
    jmp .out
.nothing:
    xor eax, eax
    jmp .out
.missing:
    mov eax, -1
.out:
    lea rsp, [rbp - 40]
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; rsi / rdx = id, r15 = paint frame -> rax = the first gradient with that
;   id, or 0
defs_find:
    push rbx
    push r12
    push r13
    mov r12, rsi
    mov r13, rdx
    mov rax, [r15 + RP_DEFS]
    mov rbx, [rax + UgfxSvgDefs_grads]
    mov ecx, [rax + UgfxSvgDefs_count]
    test rbx, rbx
    jz .none
.next:
    test ecx, ecx
    jz .none
    push rcx
    mov rdi, [rbx + GR_ID]
    mov rsi, [rbx + GR_ID_END]
    mov rdx, r12
    mov rcx, r13
    test rdi, rdi
    jz .skip
    call ugfx_svg_same
    pop rcx
    je .found
    jmp .advance
.skip:
    pop rcx
.advance:
    add rbx, GR_SIZE
    dec ecx
    jmp .next
.found:
    mov rax, rbx
    jmp .out
.none:
    xor eax, eax
.out:
    pop r13
    pop r12
    pop rbx
    ret

; r13 = a gradient in the chain: what it gives and is not yet resolved
defs_take:
    ; coordinates only from gradients of the same kind
    mov eax, [r13 + GR_KIND]
    cmp eax, [r15 + RP_KIND]
    jne .common
    xor ecx, ecx
.value:
    cmp ecx, V_COUNT
    jae .common
    bt dword [r15 + RP_HAVE], ecx
    jc .value_next
    bt dword [r13 + GR_HAVE], ecx
    jnc .value_next
    movsd xmm0, [r13 + GR_VAL + rcx * 8]
    movsd [r15 + RP_VAL + rcx * 8], xmm0
    bts dword [r15 + RP_HAVE], ecx
    bt dword [r13 + GR_PCT], ecx
    jnc .value_next
    bts dword [r15 + RP_PCT], ecx
.value_next:
    inc ecx
    jmp .value
.common:
    bt dword [r15 + RP_HAVE], H_UNITS
    jc .spread
    bt dword [r13 + GR_HAVE], H_UNITS
    jnc .spread
    mov eax, [r13 + GR_UNITS]
    mov [r15 + RP_UNITS], eax
    bts dword [r15 + RP_HAVE], H_UNITS
.spread:
    bt dword [r15 + RP_HAVE], H_SPREAD
    jc .transform
    bt dword [r13 + GR_HAVE], H_SPREAD
    jnc .transform
    mov eax, [r13 + GR_SPREAD]
    mov [r15 + RP_SPREAD], eax
    bts dword [r15 + RP_HAVE], H_SPREAD
.transform:
    bt dword [r15 + RP_HAVE], H_TRANSFORM
    jc .stops
    bt dword [r13 + GR_HAVE], H_TRANSFORM
    jnc .stops
    mov ecx, 0
.copy_m:
    mov rax, [r13 + GR_M + rcx * 8]
    mov [r15 + RP_M + rcx * 8], rax
    inc ecx
    cmp ecx, 6
    jb .copy_m
    bts dword [r15 + RP_HAVE], H_TRANSFORM
.stops:
    cmp dword [r15 + RP_NSTOPS], 0
    jne .done
    mov eax, [r13 + GR_NSTOPS]
    test eax, eax
    jz .done
    mov [r15 + RP_NSTOPS], eax
    mov rax, [r13 + GR_STOPS]
    mov [r15 + RP_STOPS], rax
.done:
    ret

section .rodata
defs_style_name:    db "style"
css_class_word:     db "class"
css_id_word:        db "id"
css_pseudos:
    NAME "first-child", SK_FIRST
    NAME "last-child", SK_LAST
    NAME "only-child", SK_ONLY
    NAME "root", SK_ROOT
    NAME "nth-child", SK_NTH
    NAME "nth-last-child", SK_NTH_LAST
    db 0
; which viewport length a percentage value is of: 0 width, 1 height, 2 diagonal
defs_axis:          db 0, 1, 0, 1, 0, 1, 2, 0, 1, 2

section .data
global ugfx_svg_defs_version
ugfx_svg_defs_version: dq 0x010000
