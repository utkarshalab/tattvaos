; =============================================================================
; Utkarsha OS — lib/ufont/match/fontset.asm
; =============================================================================
; Fonts by family, weight and style, and the font callback lib/ugfx's SVG
; text asks.
;
;   ufont_set_init(set, arena)
;   ufont_set_add(set, data, length, family, weight, italic)  -> 0, -errno
;   ufont_set_face(set, UgfxSvgFont*)                       -> face or 0
;   ufont_svg_font                          ugfx's font callback (user = set)
;   ufont_svg_shape                         ugfx's shaping callback (user = set)
;   ufont_standard, ufont_standard_count    the fonts lib/ufont ships
;
; A set holds up to UFONT_SET_MAX (64) faces: a TrueType font (sfnt.asm, its bytes
; kept by the caller) with a family name, a weight and italic or not.
; font-family is read as CSS has it: a comma list of names, quoted or not,
; compared without case. The generic names and some common ones stand for
; the shipped families - sans-serif, system-ui, ui-sans-serif, cursive,
; fantasy: Noto Sans; serif, ui-serif: Noto Serif; monospace,
; ui-monospace: Noto Sans Mono; Arial, Helvetica, Helvetica Neue, Arimo:
; Liberation Sans; Times New Roman, Times, Tinos: Liberation Serif;
; Courier New, Courier, Cousine: Liberation Mono (same advances as the
; fonts those names mean). The first name with a face in the set is used,
; else Noto Sans, else the first face. Within a family the face matching
; the style first, then the weight (bold from 600), is taken. A character
; the face lacks comes from Noto Sans in that style if it has it, else from
; the first face in the set that has it (same weight and style, then same
; weight, then any).
;
; Shaping (ufont_svg_shape): a run is split where the face or the script
; changes - each character's face as above, marks and default ignorables
; staying in the face before them; characters of no script of their own
; (common, inherited) taking the script before them, at the start the
; first one after - and each part shaped by ufont_shape. Its glyphs come
; back as keys (bit 31, the face's index in the set << 16, the glyph) that
; ufont_svg_font then draws.
; =============================================================================

%include "ugfx.inc"
%include "ufont.inc"

extern ufont_open
extern ufont_glyph
extern ufont_advance
extern ufont_outline
extern ufont_shape
extern ufl_ucd_gc
extern ufl_ucd_script
extern ufl_ucd_scripts
extern ufl_uc_is_mark_gc
extern ufl_uc_is_default_ignorable
extern arena_alloc

section .rodata
fs_noto_sans:       db "Noto Sans", 0
fs_noto_serif:      db "Noto Serif", 0
fs_noto_mono:       db "Noto Sans Mono", 0
fs_lib_sans:        db "Liberation Sans", 0
fs_lib_serif:       db "Liberation Serif", 0
fs_lib_mono:        db "Liberation Mono", 0
fs_deva_sans:       db "Noto Sans Devanagari", 0
fs_deva_serif:      db "Noto Serif Devanagari", 0
fs_bengali:        db "Noto Sans Bengali", 0
fs_gurmukhi:       db "Noto Sans Gurmukhi", 0
fs_gujarati:       db "Noto Sans Gujarati", 0
fs_oriya:          db "Noto Sans Oriya", 0
fs_tamil:          db "Noto Sans Tamil", 0
fs_telugu:         db "Noto Sans Telugu", 0
fs_kannada:        db "Noto Sans Kannada", 0
fs_malayalam:      db "Noto Sans Malayalam", 0

; alias, family
align 8
fs_aliases:
    dq fsa_0, fs_noto_sans
    dq fsa_1, fs_noto_sans
    dq fsa_2, fs_noto_sans
    dq fsa_3, fs_noto_sans
    dq fsa_4, fs_noto_sans
    dq fsa_5, fs_noto_serif
    dq fsa_6, fs_noto_serif
    dq fsa_7, fs_noto_mono
    dq fsa_8, fs_noto_mono
    dq fsa_9, fs_lib_sans
    dq fsa_10, fs_lib_sans
    dq fsa_11, fs_lib_sans
    dq fsa_12, fs_lib_sans
    dq fsa_13, fs_lib_serif
    dq fsa_14, fs_lib_serif
    dq fsa_15, fs_lib_serif
    dq fsa_16, fs_lib_mono
    dq fsa_17, fs_lib_mono
    dq fsa_18, fs_lib_mono
    dq 0, 0
fsa_0:  db "sans-serif", 0
fsa_1:  db "system-ui", 0
fsa_2:  db "ui-sans-serif", 0
fsa_3:  db "cursive", 0
fsa_4:  db "fantasy", 0
fsa_5:  db "serif", 0
fsa_6:  db "ui-serif", 0
fsa_7:  db "monospace", 0
fsa_8:  db "ui-monospace", 0
fsa_9:  db "Arial", 0
fsa_10: db "Helvetica", 0
fsa_11: db "Helvetica Neue", 0
fsa_12: db "Arimo", 0
fsa_13: db "Times New Roman", 0
fsa_14: db "Times", 0
fsa_15: db "Tinos", 0
fsa_16: db "Courier New", 0
fsa_17: db "Courier", 0
fsa_18: db "Cousine", 0

; the shipped fonts: file, family, weight, italic (UfontStd)
section .data
align 8
global ufont_standard
global ufont_standard_count
ufont_standard_count: dq 42
ufont_standard:
    dq fsf_0, fs_noto_sans
    dd 400, 0
    dq fsf_1, fs_noto_sans
    dd 700, 0
    dq fsf_2, fs_noto_sans
    dd 400, 1
    dq fsf_3, fs_noto_sans
    dd 700, 1
    dq fsf_4, fs_noto_serif
    dd 400, 0
    dq fsf_5, fs_noto_serif
    dd 700, 0
    dq fsf_6, fs_noto_serif
    dd 400, 1
    dq fsf_7, fs_noto_serif
    dd 700, 1
    dq fsf_8, fs_noto_mono
    dd 400, 0
    dq fsf_9, fs_noto_mono
    dd 700, 0
    dq fsf_10, fs_lib_sans
    dd 400, 0
    dq fsf_11, fs_lib_sans
    dd 700, 0
    dq fsf_12, fs_lib_sans
    dd 400, 1
    dq fsf_13, fs_lib_sans
    dd 700, 1
    dq fsf_14, fs_lib_serif
    dd 400, 0
    dq fsf_15, fs_lib_serif
    dd 700, 0
    dq fsf_16, fs_lib_serif
    dd 400, 1
    dq fsf_17, fs_lib_serif
    dd 700, 1
    dq fsf_18, fs_lib_mono
    dd 400, 0
    dq fsf_19, fs_lib_mono
    dd 700, 0
    dq fsf_20, fs_lib_mono
    dd 400, 1
    dq fsf_21, fs_lib_mono
    dd 700, 1
    dq fsf_22, fs_deva_sans
    dd 400, 0
    dq fsf_23, fs_deva_sans
    dd 700, 0
    dq fsf_24, fs_deva_serif
    dd 400, 0
    dq fsf_25, fs_deva_serif
    dd 700, 0
    dq fsf_26, fs_bengali
    dd 400, 0
    dq fsf_27, fs_bengali
    dd 700, 0
    dq fsf_28, fs_gurmukhi
    dd 400, 0
    dq fsf_29, fs_gurmukhi
    dd 700, 0
    dq fsf_30, fs_gujarati
    dd 400, 0
    dq fsf_31, fs_gujarati
    dd 700, 0
    dq fsf_32, fs_oriya
    dd 400, 0
    dq fsf_33, fs_oriya
    dd 700, 0
    dq fsf_34, fs_tamil
    dd 400, 0
    dq fsf_35, fs_tamil
    dd 700, 0
    dq fsf_36, fs_telugu
    dd 400, 0
    dq fsf_37, fs_telugu
    dd 700, 0
    dq fsf_38, fs_kannada
    dd 400, 0
    dq fsf_39, fs_kannada
    dd 700, 0
    dq fsf_40, fs_malayalam
    dd 400, 0
    dq fsf_41, fs_malayalam
    dd 700, 0
section .rodata
fsf_0:  db "NotoSans-Regular.ttf", 0
fsf_1:  db "NotoSans-Bold.ttf", 0
fsf_2:  db "NotoSans-Italic.ttf", 0
fsf_3:  db "NotoSans-BoldItalic.ttf", 0
fsf_4:  db "NotoSerif-Regular.ttf", 0
fsf_5:  db "NotoSerif-Bold.ttf", 0
fsf_6:  db "NotoSerif-Italic.ttf", 0
fsf_7:  db "NotoSerif-BoldItalic.ttf", 0
fsf_8:  db "NotoSansMono-Regular.ttf", 0
fsf_9:  db "NotoSansMono-Bold.ttf", 0
fsf_10: db "LiberationSans-Regular.ttf", 0
fsf_11: db "LiberationSans-Bold.ttf", 0
fsf_12: db "LiberationSans-Italic.ttf", 0
fsf_13: db "LiberationSans-BoldItalic.ttf", 0
fsf_14: db "LiberationSerif-Regular.ttf", 0
fsf_15: db "LiberationSerif-Bold.ttf", 0
fsf_16: db "LiberationSerif-Italic.ttf", 0
fsf_17: db "LiberationSerif-BoldItalic.ttf", 0
fsf_18: db "LiberationMono-Regular.ttf", 0
fsf_19: db "LiberationMono-Bold.ttf", 0
fsf_20: db "LiberationMono-Italic.ttf", 0
fsf_21: db "LiberationMono-BoldItalic.ttf", 0
fsf_22: db "NotoSansDevanagari-Regular.ttf", 0
fsf_23: db "NotoSansDevanagari-Bold.ttf", 0
fsf_24: db "NotoSerifDevanagari-Regular.ttf", 0
fsf_25: db "NotoSerifDevanagari-Bold.ttf", 0
fsf_26: db "NotoSansBengali-Regular.ttf", 0
fsf_27: db "NotoSansBengali-Bold.ttf", 0
fsf_28: db "NotoSansGurmukhi-Regular.ttf", 0
fsf_29: db "NotoSansGurmukhi-Bold.ttf", 0
fsf_30: db "NotoSansGujarati-Regular.ttf", 0
fsf_31: db "NotoSansGujarati-Bold.ttf", 0
fsf_32: db "NotoSansOriya-Regular.ttf", 0
fsf_33: db "NotoSansOriya-Bold.ttf", 0
fsf_34: db "NotoSansTamil-Regular.ttf", 0
fsf_35: db "NotoSansTamil-Bold.ttf", 0
fsf_36: db "NotoSansTelugu-Regular.ttf", 0
fsf_37: db "NotoSansTelugu-Bold.ttf", 0
fsf_38: db "NotoSansKannada-Regular.ttf", 0
fsf_39: db "NotoSansKannada-Bold.ttf", 0
fsf_40: db "NotoSansMalayalam-Regular.ttf", 0
fsf_41: db "NotoSansMalayalam-Bold.ttf", 0

section .text

; ----------------------------------------------------------------------------
; ufont_set_init — rdi = UfontSet* (UfontSet_SIZE bytes), rsi = arena
; ----------------------------------------------------------------------------
global ufont_set_init
ufont_set_init:
    mov [rdi + UfontSet_arena], rsi
    mov dword [rdi + UfontSet_count], 0
    ret

; ----------------------------------------------------------------------------
; ufont_set_add — rdi = UfontSet*, rsi = data, rdx = length (kept as long as
;   the set), rcx = family (NUL-terminated, kept), r8d = weight, r9d = 1
;   italic -> rax = 0, -EINVAL (not a usable font), -ENOMEM (memory, or
;   the set is full)
; ----------------------------------------------------------------------------
global ufont_set_add
ufont_set_add:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rbx, rdi
    mov r12, rcx
    mov r13d, r8d
    mov r14d, r9d
    mov eax, [rbx + UfontSet_count]
    cmp eax, UFONT_SET_MAX
    jae .full
    mov rdi, [rbx + UfontSet_arena]
    call ufont_open                      ; (rsi, rdx as given)
    test rax, rax
    jz .bad
    mov r15, rax
    mov eax, [rbx + UfontSet_count]
    inc dword [rbx + UfontSet_count]
    imul rax, rax, UfontFace_SIZE
    lea rax, [rbx + UfontSet_faces + rax]
    mov [rax + UfontFace_family], r12
    mov [rax + UfontFace_weight], r13d
    mov [rax + UfontFace_italic], r14d
    mov [rax + UfontFace_font], r15
    xor eax, eax
    jmp .out
.full:
    mov rax, -(ENOMEM)
    jmp .out
.bad:
    mov rax, -(EINVAL)
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------------
; ufont_set_face — rdi = UfontSet*, rsi = UgfxSvgFont* -> rax = the face (UfontFace)
;   for its family list, weight and style; 0 when the set is empty
; ----------------------------------------------------------------------------
global ufont_set_face
ufont_set_face:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rbx, rdi
    ; bold and italic wanted: r15d bit 0 / bit 1
    xor r15d, r15d
    cmp dword [rsi + UgfxSvgFont_weight], 600
    jb .weight
    or r15d, 1
.weight:
    cmp dword [rsi + UgfxSvgFont_style], 0
    je .style
    or r15d, 2
.style:
    mov r12, [rsi + UgfxSvgFont_family]
    mov r13, [rsi + UgfxSvgFont_family_end]
    test r12, r12
    jz .fallback
.item:
    ; the next name: up to a comma, trimmed, unquoted
    cmp r12, r13
    jae .fallback
    mov r14, r12
.comma:
    cmp r14, r13
    jae .cut
    cmp byte [r14], ','
    je .cut
    inc r14
    jmp .comma
.cut:
    mov rdi, r12                        ; [rdi, rsi): the name
    mov rsi, r14
    lea r12, [r14 + 1]                  ; after the comma
.front:
    cmp rdi, rsi
    jae .item
    cmp byte [rdi], ' '
    ja .back
    inc rdi
    jmp .front
.back:
    cmp byte [rsi - 1], ' '
    ja .quotes
    dec rsi
    jmp .back
.quotes:
    mov rax, rsi
    sub rax, rdi
    cmp rax, 2
    jb .named
    movzx eax, byte [rdi]
    cmp al, '"'
    je .quoted
    cmp al, 39
    jne .named
.quoted:
    cmp [rsi - 1], al
    jne .named
    inc rdi
    dec rsi
.named:
    cmp rdi, rsi
    jae .item
    ; an alias names a family
    lea rcx, [rel fs_aliases]
.alias:
    mov rdx, [rcx]
    test rdx, rdx
    jz .direct
    push rcx
    push rdi
    push rsi
    call fs_same
    pop rsi
    pop rdi
    pop rcx
    je .aliased
    add rcx, 16
    jmp .alias
.aliased:
    mov rdi, [rcx + 8]
    call fs_strend
    jmp .lookup
.direct:
.lookup:
    mov edx, r15d
    call fs_family
    test rax, rax
    jz .item
    jmp .out
.fallback:
    lea rdi, [rel fs_noto_sans]
    call fs_strend
    mov edx, r15d
    call fs_family
    test rax, rax
    jnz .out
    xor eax, eax
    cmp dword [rbx + UfontSet_count], 0
    je .out
    lea rax, [rbx + UfontSet_faces]
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; rdi = a NUL-terminated string -> rsi = its end (rdi kept)
fs_strend:
    mov rsi, rdi
.byte:
    cmp byte [rsi], 0
    je .done
    inc rsi
    jmp .byte
.done:
    ret

; rdi / rsi = a name, rdx = a NUL-terminated one -> ZF = 1 when they are
;   the same ignoring ASCII case (rax, r8 clobbered)
fs_same:
.byte:
    movzx eax, byte [rdx]
    cmp rdi, rsi
    je .end
    test eax, eax
    jz .differ
    movzx r8d, byte [rdi]
    cmp r8b, 'A'
    jb .lower_a
    cmp r8b, 'Z'
    ja .lower_a
    or r8b, 0x20
.lower_a:
    cmp al, 'A'
    jb .lower_b
    cmp al, 'Z'
    ja .lower_b
    or al, 0x20
.lower_b:
    cmp al, r8b
    jne .differ
    inc rdi
    inc rdx
    jmp .byte
.end:
    test eax, eax                       ; both ended: ZF = 1
    ret
.differ:
    or eax, 1                           ; ZF = 0
    ret

; rbx = UfontSet*, rdi / rsi = a family name, edx = bold (1) | italic (2)
;   wanted -> rax = its face matching the style first, then the weight; 0
;   when the family is not in the set
fs_family:
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov r12, rdi
    mov r13, rsi
    mov r14d, edx
    xor r15d, r15d                      ; the best so far
    mov dword [rsp], -1                 ; its score
    xor ecx, ecx
.face:
    cmp ecx, [rbx + UfontSet_count]
    jae .done
    imul rax, rcx, UfontFace_SIZE
    lea r8, [rbx + UfontSet_faces + rax]
    mov rdi, r12
    mov rsi, r13
    mov rdx, [r8 + UfontFace_family]
    push rcx
    push r8
    call fs_same
    pop r8
    pop rcx
    jne .next
    ; score: style matches 2, weight matches 1
    xor eax, eax
    cmp dword [r8 + UfontFace_weight], 600
    setae al
    mov edx, [r8 + UfontFace_italic]
    and edx, 1
    shl edx, 1
    or eax, edx                         ; its bold | italic
    xor eax, r14d                       ; what differs
    xor edx, edx
    test eax, 2
    jnz .style_differs
    add edx, 2
.style_differs:
    test eax, 1
    jnz .scored
    inc edx
.scored:
    cmp edx, [rsp]
    jle .next
    mov [rsp], edx
    mov r15, r8
.next:
    inc ecx
    jmp .face
.done:
    mov rax, r15
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    ret

; ----------------------------------------------------------------------------
; ufont_svg_font — ugfx's font callback (UgfxSvg_font_fn): rdi = UfontSet*,
;   rsi = UgfxSvgFont*, edx = code point (-1: ascent / descent), xmm0 = size,
;   rcx = UgfxPath* (0: the advance only), r8 = arena -> xmm0 = advance (or
;   ascent, xmm1 descent); the outline appended at that size
; ----------------------------------------------------------------------------
%define SV_SIZE     0                   ; f64
%define SV_SCALE    8                   ; f64 pixels per font unit
%define SV_ARENA    16
%define SV_DESC     24                  ; the UgfxSvgFont
%define SV_ADV      32                  ; f64
%define SV_FRAME    48

global ufont_svg_font
ufont_svg_font:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, SV_FRAME
    mov rbx, rdi
    mov [rsp + SV_DESC], rsi
    mov r13d, edx
    movsd [rsp + SV_SIZE], xmm0
    mov r14, rcx
    mov [rsp + SV_ARENA], r8
    call ufont_set_face
    test rax, rax
    jz .nothing
    mov r15, rax
    mov rdi, [r15 + UfontFace_font]
    cvtsi2sd xmm1, dword [rdi + UfontFont_upem]
    movsd xmm0, [rsp + SV_SIZE]
    divsd xmm0, xmm1
    movsd [rsp + SV_SCALE], xmm0
    cmp r13d, -1
    jne .glyph
    cvtsi2sd xmm0, dword [rdi + UfontFont_ascent]
    mulsd xmm0, [rsp + SV_SCALE]
    cvtsi2sd xmm1, dword [rdi + UfontFont_descent]
    mulsd xmm1, [rsp + SV_SCALE]
    jmp .out
.glyph:
    test r13d, r13d
    jns .character
    ; a glyph key: the face's index, the glyph
    mov eax, r13d
    shr eax, 16
    and eax, 0x7FFF
    cmp eax, [rbx + UfontSet_count]
    jae .key_glyph
    imul rax, rax, UfontFace_SIZE
    lea r15, [rbx + UfontSet_faces + rax]
.key_glyph:
    movzx r12d, r13w
    jmp .scaled
.character:
    ; the face that has it
    mov rdi, r15
    mov esi, r13d
    mov rax, [rsp + SV_DESC]
    call fs_want
    call fs_char_face
    mov r15, rax
    mov rdi, [r15 + UfontFace_font]
    mov esi, r13d
    call ufont_glyph
    mov r12d, eax
.scaled:
    mov rdi, [r15 + UfontFace_font]
    cvtsi2sd xmm1, dword [rdi + UfontFont_upem]
    movsd xmm0, [rsp + SV_SIZE]
    divsd xmm0, xmm1
    movsd [rsp + SV_SCALE], xmm0
.have:
    mov rdi, [r15 + UfontFace_font]
    mov esi, r12d
    call ufont_advance
    cvtsi2sd xmm0, eax
    mulsd xmm0, [rsp + SV_SCALE]
    movsd [rsp + SV_ADV], xmm0
    test r14, r14
    jz .advance
    mov rdi, [r15 + UfontFace_font]
    mov esi, r12d
    mov rdx, r14
    movsd xmm0, [rsp + SV_SCALE]
    mov rcx, [rsp + SV_ARENA]
    call ufont_outline
.advance:
    movsd xmm0, [rsp + SV_ADV]
    jmp .out
.nothing:
    xorpd xmm0, xmm0
    xorpd xmm1, xmm1
.out:
    add rsp, SV_FRAME
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; rax = UgfxSvgFont* -> edx = bold (1) | italic (2) wanted
fs_want:
    xor edx, edx
    cmp dword [rax + UgfxSvgFont_weight], 600
    jb .weight
    or edx, 1
.weight:
    cmp dword [rax + UgfxSvgFont_style], 0
    je .out
    or edx, 2
.out:
    ret

; ----------------------------------------------------------------------------
; fs_char_face — rbx = UfontSet*, rdi = the face asked for, esi = a code
;   point, edx = bold | italic wanted -> rax = the face to draw it from: that
;   face if it has it, else Noto Sans in the style, else the first face with
;   it (same weight and style, then same weight, then any), else that face
; ----------------------------------------------------------------------------
fs_char_face:
    push r12
    push r13
    push r14
    push r15
    push rbp
    mov r12, rdi
    mov r13d, esi
    mov r14d, edx
    mov rdi, [r12 + UfontFace_font]
    call ufont_glyph
    test eax, eax
    jnz .asked
    lea rdi, [rel fs_noto_sans]
    call fs_strend
    mov edx, r14d
    call fs_family
    test rax, rax
    jz .scan
    cmp rax, r12
    je .scan
    mov r15, rax
    mov rdi, [r15 + UfontFace_font]
    mov esi, r13d
    call ufont_glyph
    test eax, eax
    jz .scan
    mov rax, r15
    jmp .out
.scan:
    mov ebp, 3                          ; what must match: 3, then 1, then 0
.pass:
    xor r15d, r15d
.face:
    cmp r15d, [rbx + UfontSet_count]
    jae .pass_next
    imul rax, r15, UfontFace_SIZE
    lea rdi, [rbx + UfontSet_faces + rax]
    xor eax, eax
    cmp dword [rdi + UfontFace_weight], 600
    setae al
    mov ecx, [rdi + UfontFace_italic]
    and ecx, 1
    shl ecx, 1
    or eax, ecx
    xor eax, r14d
    test eax, ebp
    jnz .face_next
    push rdi
    sub rsp, 8
    mov rdi, [rdi + UfontFace_font]
    mov esi, r13d
    call ufont_glyph
    add rsp, 8
    pop rdi
    test eax, eax
    jz .face_next
    mov rax, rdi
    jmp .out
.face_next:
    inc r15d
    jmp .face
.pass_next:
    test ebp, ebp
    jz .asked
    shr ebp, 1                          ; 3 -> 1 -> 0
    jmp .pass
.asked:
    mov rax, r12
.out:
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    ret

; ----------------------------------------------------------------------------
; ufont_svg_shape — ugfx's shaping callback (UgfxSvg_shape_fn): rdi =
;   UfontSet*, rsi = UgfxSvgFont*, rdx = code points (u32), ecx = count,
;   xmm0 = size, r8 = arena -> rax = UgfxSvgGlyph records (0: none), edx =
;   how many
; ----------------------------------------------------------------------------
%define SS_DESC     0
%define SS_CPS      8
%define SS_N        16                  ; u32
%define SS_WANT     20                  ; u32
%define SS_SIZE     24                  ; f64
%define SS_ARENA    32
%define SS_FACES    40                  ; UfontFace* per character
%define SS_SCRIPTS  48                  ; u32 script index per character
%define SS_OUT      56                  ; UgfxSvgGlyph records
%define SS_COUNT    64                  ; u32
%define SS_CAP      68                  ; u32
%define SS_A        72                  ; u32 the part's start
%define SS_B        76                  ; u32 its end
%define SS_SCALE    80                  ; f64
%define SS_KEY      88                  ; u32 the face's index << 16 | bit 31
%define SS_FRAME    96

global ufont_svg_shape
ufont_svg_shape:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, SS_FRAME
    mov rbx, rdi
    mov [rsp + SS_DESC], rsi
    mov [rsp + SS_CPS], rdx
    mov [rsp + SS_N], ecx
    movsd [rsp + SS_SIZE], xmm0
    mov [rsp + SS_ARENA], r8
    mov rax, rsi
    call fs_want
    mov [rsp + SS_WANT], edx
    test ecx, ecx
    jz .none
    call ufont_set_face
    test rax, rax
    jz .none
    mov r12, rax                        ; the face asked for
    ; arrays
    mov rdi, [rsp + SS_ARENA]
    mov esi, [rsp + SS_N]
    shl esi, 3
    call arena_alloc
    test rax, rax
    jz .none
    mov [rsp + SS_FACES], rax
    mov rdi, [rsp + SS_ARENA]
    mov esi, [rsp + SS_N]
    shl esi, 2
    call arena_alloc
    test rax, rax
    jz .none
    mov [rsp + SS_SCRIPTS], rax
    mov eax, [rsp + SS_N]
    lea eax, [rax * 2 + 16]
    mov [rsp + SS_CAP], eax
    mov dword [rsp + SS_COUNT], 0
    mov rdi, [rsp + SS_ARENA]
    mov esi, eax
    shl esi, 5
    call arena_alloc
    test rax, rax
    jz .none
    mov [rsp + SS_OUT], rax
    ; each character's face
    xor r13d, r13d
.faces:
    cmp r13d, [rsp + SS_N]
    jae .scripts
    mov rax, [rsp + SS_CPS]
    mov r14d, [rax + r13 * 4]
    test r13d, r13d
    jz .own_face
    mov edi, r14d
    call ufl_ucd_gc
    mov edi, eax
    call ufl_uc_is_mark_gc
    test eax, eax
    jnz .prev_face
    mov edi, r14d
    call ufl_uc_is_default_ignorable
    test eax, eax
    jz .own_face
.prev_face:
    mov rax, [rsp + SS_FACES]
    mov rcx, [rax + r13 * 8 - 8]
    mov [rax + r13 * 8], rcx
    jmp .faces_next
.own_face:
    mov rdi, r12
    mov esi, r14d
    mov edx, [rsp + SS_WANT]
    call fs_char_face
    mov rcx, [rsp + SS_FACES]
    mov [rcx + r13 * 8], rax
.faces_next:
    inc r13d
    jmp .faces
.scripts:
    ; strong scripts, then the weak ones resolved
    xor r13d, r13d
    xor r15d, r15d                      ; the first strong (0: none)
.strong:
    cmp r13d, [rsp + SS_N]
    jae .resolve
    mov rax, [rsp + SS_CPS]
    mov edi, [rax + r13 * 4]
    call ufl_ucd_script
    cmp eax, 3
    jae .is_strong
    xor eax, eax
    jmp .store
.is_strong:
    test r15d, r15d
    jnz .store
    mov r15d, eax
.store:
    mov rcx, [rsp + SS_SCRIPTS]
    mov [rcx + r13 * 4], eax
    inc r13d
    jmp .strong
.resolve:
    mov rcx, [rsp + SS_SCRIPTS]
    xor r13d, r13d
.res:
    cmp r13d, [rsp + SS_N]
    jae .parts
    mov eax, [rcx + r13 * 4]
    test eax, eax
    jz .weak
    mov r15d, eax
    jmp .res_next
.weak:
    mov [rcx + r13 * 4], r15d
.res_next:
    inc r13d
    jmp .res
.parts:
    mov dword [rsp + SS_A], 0
.part:
    mov eax, [rsp + SS_A]
    cmp eax, [rsp + SS_N]
    jae .done
    mov rdx, [rsp + SS_FACES]
    mov r14, [rdx + rax * 8]            ; its face
    mov rcx, [rsp + SS_SCRIPTS]
    mov r15d, [rcx + rax * 4]           ; its script
    lea r13d, [rax + 1]
.part_end:
    cmp r13d, [rsp + SS_N]
    jae .part_have
    cmp [rdx + r13 * 8], r14
    jne .part_have
    cmp [rcx + r13 * 4], r15d
    jne .part_have
    inc r13d
    jmp .part_end
.part_have:
    mov [rsp + SS_B], r13d
    ; the key's face index, the scale
    mov rax, r14
    lea rcx, [rbx + UfontSet_faces]
    sub rax, rcx
    xor edx, edx
    mov ecx, UfontFace_SIZE
    div rcx
    shl eax, 16
    or eax, 0x80000000
    mov [rsp + SS_KEY], eax
    mov rdi, [r14 + UfontFace_font]
    cvtsi2sd xmm1, dword [rdi + UfontFont_upem]
    movsd xmm0, [rsp + SS_SIZE]
    divsd xmm0, xmm1
    movsd [rsp + SS_SCALE], xmm0
    ; shaped: the script's ISO tag (none for a part of no script)
    xor r8d, r8d
    test r15d, r15d
    jz .tagged
    imul eax, r15d, 12
    lea rcx, [rel ufl_ucd_scripts]
    mov r8d, [rcx + rax]
.tagged:
    mov rdi, [r14 + UfontFace_font]
    mov rsi, [rsp + SS_ARENA]
    mov eax, [rsp + SS_A]
    mov rdx, [rsp + SS_CPS]
    lea rdx, [rdx + rax * 4]
    mov ecx, [rsp + SS_B]
    sub ecx, eax
    xor r9d, r9d
    call ufont_shape
    test rax, rax
    jz .none
    mov r12, rax                        ; its glyphs
    mov r13d, edx
    ; room for them
    mov eax, [rsp + SS_COUNT]
    add eax, r13d
    cmp eax, [rsp + SS_CAP]
    jbe .room
    lea r15d, [rax * 2]
    mov rdi, [rsp + SS_ARENA]
    mov esi, r15d
    shl esi, 5
    call arena_alloc
    test rax, rax
    jz .none
    mov rsi, [rsp + SS_OUT]
    mov rdi, rax
    mov ecx, [rsp + SS_COUNT]
    shl ecx, 5
    rep movsb
    mov [rsp + SS_OUT], rax
    mov [rsp + SS_CAP], r15d
.room:
    xor ecx, ecx
.copy:
    cmp ecx, r13d
    jae .part_next
    imul eax, ecx, UfontGlyph_SIZE
    lea rsi, [r12 + rax]
    mov eax, [rsp + SS_COUNT]
    shl rax, 5
    add rax, [rsp + SS_OUT]
    mov edx, [rsi + UfontGlyph_glyph]
    and edx, 0xFFFF
    or edx, [rsp + SS_KEY]
    mov [rax + UgfxSvgGlyph_key], edx
    mov edx, [rsi + UfontGlyph_cluster]
    add edx, [rsp + SS_A]
    mov [rax + UgfxSvgGlyph_cluster], edx
    cvtsi2sd xmm0, dword [rsi + UfontGlyph_xa]
    mulsd xmm0, [rsp + SS_SCALE]
    movsd [rax + UgfxSvgGlyph_adv], xmm0
    cvtsi2sd xmm0, dword [rsi + UfontGlyph_xo]
    mulsd xmm0, [rsp + SS_SCALE]
    movsd [rax + UgfxSvgGlyph_xo], xmm0
    cvtsi2sd xmm1, dword [rsi + UfontGlyph_yo]
    mulsd xmm1, [rsp + SS_SCALE]
    xorpd xmm0, xmm0
    subsd xmm0, xmm1
    movsd [rax + UgfxSvgGlyph_yo], xmm0
    inc dword [rsp + SS_COUNT]
    inc ecx
    jmp .copy
.part_next:
    mov eax, [rsp + SS_B]
    mov [rsp + SS_A], eax
    jmp .part
.done:
    mov rax, [rsp + SS_OUT]
    mov edx, [rsp + SS_COUNT]
    jmp .out
.none:
    xor eax, eax
    xor edx, edx
.out:
    add rsp, SS_FRAME
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

section .data
global ufont_set_version
ufont_set_version: dq 0x010000
