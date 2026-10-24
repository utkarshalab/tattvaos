; =============================================================================
; Utkarsha OS — lib/ugfx/2d/svg_defs.asm
; =============================================================================
; SVG definitions found before drawing: gradients, looked up by id when a
; fill or stroke says url(#id), and the CSS rules of <style> elements.
;
;   ugfx_svg_defs_scan(defs, arena, data, size)
;       every linearGradient / radialGradient in the document with its
;       stops (wherever it is: defs or not)
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
; CSS: rules "selectors { declarations }" from every <style> (comments,
; CDATA and HTML comment markers skipped; at-rules skipped with their
; blocks). Selectors: element, .class, #id, element.class, * and lists of
; them; any other selector (combinators, attributes, pseudo-classes) is
; left out. Rules are kept in cascade order: by specificity (id 100,
; class 10, element 1, element.class 11, * 0), then document order.
; =============================================================================

%include "ugfx.inc"

extern arena_alloc
extern ugfx_svg_xml_next
extern ugfx_svg_xml_attr
extern ugfx_svg_xml_text_end
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
%define RL_KIND         0               ; u32 1 element, 2 class, 3 id, 4 element.class, 5 *
%define RL_SPEC         4               ; u32 specificity
%define RL_NAME         8               ; element name / class / id
%define RL_NAME_END     16
%define RL_ELEM         24              ; element.class: the element
%define RL_ELEM_END     32
%define RL_DECL         40              ; the declarations
%define RL_DECL_END     48
%define RL_SIZE         56

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
%define SC_SIZE     (((SC_ATTR + UgfxSvgAttr_SIZE + 15) & ~15) + 8)

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
    mov qword [r15 + SC_GRAD], 0
    mov [r15 + SC_XML + UgfxSvgXml_cur], rdx
    add rdx, rcx
    mov [r15 + SC_XML + UgfxSvgXml_end], rdx
.token:
    lea rdi, [r15 + SC_XML]
    call ugfx_svg_xml_next
    test eax, eax
    jz .done
    mov ebx, eax
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

; rdi / rsi = one selector (untrimmed), rdx / rcx = declarations, r15 =
;   scan frame -> rax = 0 or -ENOMEM; unsupported selectors are left out
css_add_rule:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 24
    mov [rsp], rdx
    mov [rsp + 8], rcx
    call ugfx_svg_trim
    mov r12, rdi
    mov r13, rsi
    cmp r12, r13
    jae .skip
    xor r14d, r14d                      ; the element.class split, if any
    movzx eax, byte [r12]
    cmp al, '*'
    je .universal
    cmp al, '.'
    je .class
    cmp al, '#'
    je .id
    ; element, or element.class
    mov rdi, r12
.elem_scan:
    cmp rdi, r13
    jae .element
    mov al, [rdi]
    cmp al, '.'
    je .elem_class
    call css_ident
    jne .skip
    inc rdi
    jmp .elem_scan
.element:
    mov ebx, 1                          ; kind
    mov ecx, 1                          ; specificity
    mov rdx, r12
    mov r8, r13
    jmp .push
.elem_class:
    cmp rdi, r12
    je .skip
    mov r14, rdi                        ; '.'
    lea rdi, [r14 + 1]
    mov rsi, r13
    call css_ident_run
    jne .skip
    mov ebx, 4
    mov ecx, 11
    lea rdx, [r14 + 1]
    mov r8, r13
    jmp .push
.universal:
    lea rax, [r12 + 1]
    cmp rax, r13
    jne .skip
    mov ebx, 5
    xor ecx, ecx
    mov rdx, r12
    mov r8, r13
    jmp .push
.class:
    mov ebx, 2
    mov ecx, 10
    jmp .named
.id:
    mov ebx, 3
    mov ecx, 100
.named:
    lea rdi, [r12 + 1]
    mov rsi, r13
    push rcx
    call css_ident_run
    pop rcx
    jne .skip
    lea rdx, [r12 + 1]
    mov r8, r13
.push:
    mov [rsp + 16], rdx
    push rcx
    push r8
    call defs_new_rule
    pop r8
    pop rcx
    test rax, rax
    jz .nomem
    mov [rax + RL_KIND], ebx
    mov [rax + RL_SPEC], ecx
    mov rdx, [rsp + 16]
    mov [rax + RL_NAME], rdx
    mov [rax + RL_NAME_END], r8
    mov [rax + RL_ELEM], r12
    mov [rax + RL_ELEM_END], r14
    mov rdx, [rsp]
    mov [rax + RL_DECL], rdx
    mov rdx, [rsp + 8]
    mov [rax + RL_DECL_END], rdx
.skip:
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
;   -> rax = the rule's declarations and rdx their end if it applies to the
;   element, else rax = 0
; -----------------------------------------------------------------------------
global ugfx_svg_defs_rule
ugfx_svg_defs_rule:
    push rbx
    push r12
    push r13
    mov r12, rdx
    xor eax, eax
    cmp esi, [rdi + UgfxSvgDefs_nrules]
    jae .out
    imul rbx, rsi, RL_SIZE
    add rbx, [rdi + UgfxSvgDefs_rules]
    mov eax, [rbx + RL_KIND]
    cmp eax, 5
    je .match
    cmp eax, 1
    je .element
    cmp eax, 3
    je .id
    cmp eax, 4
    jne .class
    ; element.class: the element first
    mov rdi, [rbx + RL_ELEM]
    mov rsi, [rbx + RL_ELEM_END]
    mov rdx, [r12 + UgfxSvgSel_name]
    mov rcx, [r12 + UgfxSvgSel_name_end]
    call ugfx_svg_same
    jne .no
.class:
    ; one of the element's classes (space separated)
    mov r13, [r12 + UgfxSvgSel_class]
    test r13, r13
    jz .no
.token:
    mov rsi, [r12 + UgfxSvgSel_class_end]
.token_ws:
    cmp r13, rsi
    jae .no
    cmp byte [r13], ' '
    ja .token_start
    inc r13
    jmp .token_ws
.token_start:
    mov rdi, r13
.token_end:
    cmp r13, rsi
    jae .compare
    cmp byte [r13], ' '
    jbe .compare
    inc r13
    jmp .token_end
.compare:
    mov rsi, r13
    mov rdx, [rbx + RL_NAME]
    mov rcx, [rbx + RL_NAME_END]
    call ugfx_svg_same
    je .match
    jmp .token
.element:
    mov rdi, [rbx + RL_NAME]
    mov rsi, [rbx + RL_NAME_END]
    mov rdx, [r12 + UgfxSvgSel_name]
    mov rcx, [r12 + UgfxSvgSel_name_end]
    call ugfx_svg_same
    je .match
    jmp .no
.id:
    mov rdi, [r12 + UgfxSvgSel_id]
    test rdi, rdi
    jz .no
    mov rsi, [r12 + UgfxSvgSel_id_end]
    mov rdx, [rbx + RL_NAME]
    mov rcx, [rbx + RL_NAME_END]
    call ugfx_svg_same
    je .match
.no:
    xor eax, eax
    jmp .out
.match:
    mov rax, [rbx + RL_DECL]
    mov rdx, [rbx + RL_DECL_END]
.out:
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
; which viewport length a percentage value is of: 0 width, 1 height, 2 diagonal
defs_axis:          db 0, 1, 0, 1, 0, 1, 2, 0, 1, 2

section .data
global ugfx_svg_defs_version
ugfx_svg_defs_version: dq 0x010000
