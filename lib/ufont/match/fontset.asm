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
;   ufont_standard, ufont_standard_count    the fonts lib/ufont ships
;
; A set holds up to UFONT_SET_MAX faces: a TrueType font (sfnt.asm, its bytes
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
; the face lacks comes from Noto Sans in that style, if it has it.
; =============================================================================

%include "ugfx.inc"
%include "ufont.inc"

extern ufont_open
extern ufont_glyph
extern ufont_advance
extern ufont_outline

section .rodata
fs_noto_sans:       db "Noto Sans", 0
fs_noto_serif:      db "Noto Serif", 0
fs_noto_mono:       db "Noto Sans Mono", 0
fs_lib_sans:        db "Liberation Sans", 0
fs_lib_serif:       db "Liberation Serif", 0
fs_lib_mono:        db "Liberation Mono", 0

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
ufont_standard_count: dq 22
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
    mov esi, r13d
    call ufont_glyph
    mov r12d, eax
    test eax, eax
    jnz .have
    ; not in this face: Noto Sans in the style, if it has it
    lea rdi, [rel fs_noto_sans]
    call fs_strend
    mov rax, [rsp + SV_DESC]
    xor edx, edx
    cmp dword [rax + UgfxSvgFont_weight], 600
    jb .fb_weight
    or edx, 1
.fb_weight:
    cmp dword [rax + UgfxSvgFont_style], 0
    je .fb_style
    or edx, 2
.fb_style:
    call fs_family
    test rax, rax
    jz .have
    cmp rax, r15
    je .have
    mov r12, rax
    mov rdi, [r12 + UfontFace_font]
    mov esi, r13d
    call ufont_glyph
    test eax, eax
    jz .notdef
    mov r15, r12
    mov r12d, eax
    mov rdi, [r15 + UfontFace_font]
    cvtsi2sd xmm1, dword [rdi + UfontFont_upem]
    movsd xmm0, [rsp + SV_SIZE]
    divsd xmm0, xmm1
    movsd [rsp + SV_SCALE], xmm0
    jmp .have
.notdef:
    xor r12d, r12d
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

section .data
global ufont_set_version
ufont_set_version: dq 0x010000
