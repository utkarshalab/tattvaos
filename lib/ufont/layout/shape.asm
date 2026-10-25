; =============================================================================
; Utkarsha OS — lib/ufont/layout/shape.asm
; =============================================================================
; Text shaping: characters to positioned glyphs, as HarfBuzz shapes them.
;
;   ufont_shape(rdi = UfontFont*, rsi = arena, rdx = code points (u32), ecx =
;       count, r8d = script (ISO 15924 tag such as 'Deva'; 0: from the text),
;       r9d = OpenType language system tag (0: the default))
;       -> rax = UfontGlyph records (font units, y up; 0: out of memory),
;          edx = how many
;
; Left to right, one run. The steps: Unicode properties and grapheme
; clusters; the plan (the script's tags in the font, its features; the
; Indic shaper for the nine Indic scripts unless the font has only DFLT /
; latn for them);
; Indic vowel constraints; normalization against the font; feature masks
; (fractions around U+2044, Indic syllables later); GSUB; advances; spaces
; the font lacks widened; GPOS (or the kern table when GPOS has no kerning
; for the script); mark widths zeroed (not for Indic); default ignorables
; zero-width, drawn as the space glyph; mark and cursive offsets chained
; through the glyphs they attach to.
;
; A font cannot make shaping run away: lookups recurse at most 64 deep and
; 1024 x the text's length times in all (at least 16384), and the buffer
; grows to 64 x the text at most (then ufont_shape fails).
;
; Not done yet: right-to-left runs, fonts without GPOS
; (no fallback mark placement), Devanagari fonts made for the Universal
; Shaping Engine (dev3), the rand feature's random alternates.
; =============================================================================

%include "ufont.inc"
%include "shape.inc"

extern arena_alloc
extern ufont_glyph
extern ufont_advance
extern ufl_ucd_script
extern ufl_ucd_scripts
extern ufl_ucd_scripts_count
extern ufl_ucd_pict
extern ufl_ucd_pict_count
extern ufl_uc_set_props
extern ufl_buf_ensure
extern ufl_buf_merge_clusters
extern ufl_norm_run
extern ufl_norm_glyph
extern ufl_otl_gdef_init
extern ufl_otl_glyph_props
extern ufl_otl_select
extern ufl_otl_feature_index
extern ufl_map_init
extern ufl_map_add_feature
extern ufl_map_enable
extern ufl_map_add_gsub_pause
extern ufl_map_compile
extern ufl_map_get_mask
extern ufl_map_get_1_mask
extern ufl_ap_run_table
extern ufl_indic_collect_features
extern ufl_indic_override_features
extern ufl_indic_data_create
extern ufl_indic_preprocess
extern ufl_indic_setup_masks

section .rodata
; common and horizontal features: tag, flags
sh_features:
    dd 'abvm', F_GLOBAL
    dd 'blwm', F_GLOBAL
    dd 'ccmp', F_GLOBAL
    dd 'locl', F_GLOBAL
    dd 'mark', F_GLOBAL | F_MANUAL_JOINERS
    dd 'mkmk', F_GLOBAL | F_MANUAL_JOINERS
    dd 'rlig', F_GLOBAL
    dd 'calt', F_GLOBAL
    dd 'clig', F_GLOBAL
    dd 'curs', F_GLOBAL
    dd 'dist', F_GLOBAL
    dd 'kern', F_GLOBAL | F_HAS_FALLBACK
    dd 'liga', F_GLOBAL
    dd 'rclt', F_GLOBAL
sh_features_end:
sh_indic: dd 'Deva', 'Beng', 'Guru', 'Gujr', 'Orya', 'Taml', 'Telu', 'Knda', 'Mlym', 0

section .text

%define SP_EM_16    16
%define SP_4_EM_18  17
%define SP_FIGURE   19
%define SP_PUNCT    20
%define SP_NARROW   21

; ----------------------------------------------------------------------------
; ufont_shape
; ----------------------------------------------------------------------------
global ufont_shape
ufont_shape:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 24
    mov rbx, rdi                        ; font
    mov r12, rsi                        ; arena
    mov r13, rdx                        ; code points
    mov r14d, ecx                       ; count
    mov [rsp], r8d                      ; script
    mov [rsp + 4], r9d                  ; language
    mov rdi, r12
    mov esi, S_SIZE
    call arena_alloc
    test rax, rax
    jz .fail
    mov r15, rax
    mov rdi, rax
    xor eax, eax
    mov ecx, S_SIZE
    rep stosb
    mov [r15 + S_FONT], rbx
    mov [r15 + S_ARENA], r12
    mov eax, [rsp + 4]
    mov [r15 + S_LANG], eax
    mov dword [r15 + S_IVIRAMA], -1
    ; the characters
    lea esi, [r14 + 8]
    call ufl_buf_ensure
    test eax, eax
    jnz .fail
    xor ebp, ebp
.chars:
    cmp ebp, r14d
    jae .chars_done
    mov rdi, rbp
    shl rdi, 5
    add rdi, [r15 + S_INFO]
    push rdi
    xor eax, eax
    mov ecx, 32
    rep stosb
    pop rdi
    mov [rdi + GI_CLUSTER], ebp
    mov esi, [r13 + rbp * 4]
    call ufl_uc_set_props
    inc ebp
    jmp .chars
.chars_done:
    mov [r15 + S_LEN], r14d
    ; limits against runaway fonts: recursions 1024 x the text, length 64 x,
    ; at least 16384 each
    mov eax, r14d
    shl eax, 6
    cmp eax, 16384
    jae .maxlen
    mov eax, 16384
.maxlen:
    mov [r15 + S_MAXLEN], eax
    mov eax, r14d
    cmp eax, 0x1FFFFF
    jbe .ops
    mov eax, 0x1FFFFF
.ops:
    shl eax, 10
    cmp eax, 16384
    jae .ops_set
    mov eax, 16384
.ops_set:
    mov [r15 + S_OPS], eax
    call sh_graphemes
    ; the script
    mov eax, [rsp]
    test eax, eax
    jz .guess
    xor ecx, ecx
    lea rdx, [rel ufl_ucd_scripts]
.find_script:
    cmp ecx, [rel ufl_ucd_scripts_count]
    jae .script_done
    imul r8d, ecx, 12
    cmp [rdx + r8], eax
    je .script_found
    inc ecx
    jmp .find_script
.script_found:
    mov [r15 + S_SCRIPT], ecx
    jmp .script_done
.guess:
    xor ebp, ebp
.guess_next:
    cmp ebp, r14d
    jae .script_done
    mov edi, [r13 + rbp * 4]
    call ufl_ucd_script
    inc ebp
    cmp eax, 3
    jb .guess_next
    mov [r15 + S_SCRIPT], eax
.script_done:
    xor edi, edi
    call ufl_otl_select
    mov edi, 1
    call ufl_otl_select
    ; the shaper: Indic for the nine Indic scripts unless the font only has
    ; DFLT / latn for them
    mov eax, [r15 + S_SCRIPT]
    imul eax, eax, 12
    lea rdx, [rel ufl_ucd_scripts]
    mov eax, [rdx + rax]
    lea rdx, [rel sh_indic]
.indic_script:
    cmp dword [rdx], 0
    je .plan
    cmp [rdx], eax
    je .indic
    add rdx, 4
    jmp .indic_script
.indic:
    mov eax, [r15 + S_CHOSEN]
    cmp eax, 'DFLT'
    je .plan
    cmp eax, 'latn'
    je .plan
    mov ecx, eax
    shr ecx, 24
    cmp ecx, '3'
    je .plan                            ; Universal Shaping Engine fonts: not yet
    mov byte [r15 + S_SHAPER], 1
.plan:
    call ufl_map_init
    test eax, eax
    jnz .fail
    mov edi, 'rvrn'
    xor esi, esi
    mov edx, 1
    call ufl_map_enable
    xor edi, edi
    call ufl_map_add_gsub_pause
    mov edi, 'ltra'
    xor esi, esi
    mov edx, 1
    call ufl_map_enable
    mov edi, 'ltrm'
    xor esi, esi
    mov edx, 1
    call ufl_map_enable
    mov edi, 'frac'
    xor esi, esi
    mov edx, 1
    call ufl_map_add_feature
    mov edi, 'numr'
    xor esi, esi
    mov edx, 1
    call ufl_map_add_feature
    mov edi, 'dnom'
    xor esi, esi
    mov edx, 1
    call ufl_map_add_feature
    mov edi, 'rand'
    mov esi, F_RANDOM
    mov edx, 255
    call ufl_map_enable
    mov edi, 'Harf'
    xor esi, esi
    mov edx, 1
    call ufl_map_enable
    mov edi, 'HARF'
    xor esi, esi
    mov edx, 1
    call ufl_map_enable
    cmp byte [r15 + S_SHAPER], 1
    jne .common
    call ufl_indic_collect_features
.common:
    mov edi, 'Buzz'
    xor esi, esi
    mov edx, 1
    call ufl_map_enable
    mov edi, 'BUZZ'
    xor esi, esi
    mov edx, 1
    call ufl_map_enable
    lea rbp, [rel sh_features]
.feat:
    lea rax, [rel sh_features_end]
    cmp rbp, rax
    jae .feat_done
    mov edi, [rbp]
    mov esi, [rbp + 4]
    mov edx, 1
    call ufl_map_add_feature
    add rbp, 8
    jmp .feat
.feat_done:
    cmp byte [r15 + S_SHAPER], 1
    jne .compile
    call ufl_indic_override_features
.compile:
    call ufl_map_compile
    test eax, eax
    jnz .fail
    call ufl_otl_gdef_init
    cmp byte [r15 + S_SHAPER], 1
    jne .normalize
    call ufl_indic_data_create
    call ufl_indic_preprocess
.normalize:
    call ufl_norm_run
    ; masks
    mov eax, [r15 + S_GMASK]
    xor ecx, ecx
.mask:
    cmp ecx, [r15 + S_LEN]
    jae .masked
    mov rdx, rcx
    shl rdx, 5
    add rdx, [r15 + S_INFO]
    mov [rdx + GI_MASK], eax
    inc ecx
    jmp .mask
.masked:
    call sh_fractions
    cmp byte [r15 + S_SHAPER], 1
    jne .gsub
    call ufl_indic_setup_masks
.gsub:
    ; glyph classes: GDEF's, else from Unicode (nonspacing marks are marks)
    xor ebp, ebp
.props:
    cmp ebp, [r15 + S_LEN]
    jae .props_done
    mov r12, rbp
    shl r12, 5
    add r12, [r15 + S_INFO]
    mov byte [r12 + GI_LIG], 0
    cmp qword [r15 + S_CLASSDEF], 0
    je .synth
    mov edi, [r12 + GI_GLYPH]
    call ufl_otl_glyph_props
    jmp .set_props
.synth:
    mov eax, GP_BASE
    cmp byte [r12 + GI_GC], GC_MN
    jne .set_props
    test byte [r12 + GI_UF], UF_IGN
    jnz .set_props
    mov eax, GP_MARK
.set_props:
    mov [r12 + GI_PROPS], ax
    inc ebp
    jmp .props
.props_done:
    xor edi, edi
    call ufl_ap_run_table
    cmp byte [r15 + S_ERR], 0
    jne .fail
    ; advances
    mov eax, [r15 + S_LEN]
    imul eax, eax, GPOS_SIZE
    lea rsi, [rax + 8]
    mov rdi, [r15 + S_ARENA]
    call arena_alloc
    test rax, rax
    jz .fail
    mov [r15 + S_POS], rax
    mov rdi, rax
    mov ecx, [r15 + S_LEN]
    imul ecx, ecx, GPOS_SIZE
    xor eax, eax
    rep stosb
    xor ebp, ebp
.adv:
    cmp ebp, [r15 + S_LEN]
    jae .adv_done
    mov rax, rbp
    shl rax, 5
    add rax, [r15 + S_INFO]
    mov esi, [rax + GI_GLYPH]
    mov rdi, [r15 + S_FONT]
    call ufont_advance
    imul ecx, ebp, GPOS_SIZE
    add rcx, [r15 + S_POS]
    mov [rcx + GPOS_XA], eax
    inc ebp
    jmp .adv
.adv_done:
    call sh_fallback_spaces
    ; GPOS, or the kern table
    mov edi, 1
    mov esi, 'kern'
    call ufl_otl_feature_index
    mov ebp, eax                        ; GPOS kern feature (-1 none)
    mov byte [r15 + S_HASATTACH], 0
    mov edi, 1
    call ufl_ap_run_table
    mov rax, [r15 + S_FONT]
    cmp qword [rax + UfontFont_gpos], 0
    je .kern
    cmp ebp, -1
    jne .zero_marks
.kern:
    mov edi, 'kern'
    call ufl_map_get_mask
    mov [r15 + S_KERNMASK], eax
    call sh_kern_table
.zero_marks:
    cmp byte [r15 + S_SHAPER], 1
    je .ignorables
    xor ebp, ebp
.zm:
    cmp ebp, [r15 + S_LEN]
    jae .ignorables
    mov rax, rbp
    shl rax, 5
    add rax, [r15 + S_INFO]
    test word [rax + GI_PROPS], GP_MARK
    jz .zm_next
    imul ecx, ebp, GPOS_SIZE
    add rcx, [r15 + S_POS]
    mov dword [rcx + GPOS_XA], 0
    mov dword [rcx + GPOS_YA], 0
.zm_next:
    inc ebp
    jmp .zm
.ignorables:
    xor ebp, ebp
.ig:
    cmp ebp, [r15 + S_LEN]
    jae .ig_done
    mov rax, rbp
    shl rax, 5
    add rax, [r15 + S_INFO]
    call sh_is_ignorable
    test ecx, ecx
    jz .ig_next
    imul ecx, ebp, GPOS_SIZE
    add rcx, [r15 + S_POS]
    xor eax, eax
    mov [rcx + GPOS_XA], eax
    mov [rcx + GPOS_YA], eax
    mov [rcx + GPOS_XO], eax
    mov [rcx + GPOS_YO], eax
.ig_next:
    inc ebp
    jmp .ig
.ig_done:
    cmp byte [r15 + S_HASATTACH], 0
    je .output
    xor ebp, ebp
.prop:
    cmp ebp, [r15 + S_LEN]
    jae .output
    mov edi, ebp
    mov esi, MAX_NESTING
    call sh_propagate
    inc ebp
    jmp .prop
.output:
    ; ignorables drawn as the space glyph (dropped without one)
    mov edi, 0x20
    call ufl_norm_glyph
    mov [rsp + 8], eax
    mov eax, [r15 + S_LEN]
    imul eax, eax, UfontGlyph_SIZE
    lea rsi, [rax + 8]
    mov rdi, [r15 + S_ARENA]
    call arena_alloc
    test rax, rax
    jz .fail
    mov [rsp + 16], rax
    mov rdi, rax                        ; next out
    xor ebp, ebp
    xor r12d, r12d                      ; written
.out:
    cmp ebp, [r15 + S_LEN]
    jae .done
    mov rax, rbp
    shl rax, 5
    add rax, [r15 + S_INFO]
    mov r8d, [rax + GI_GLYPH]
    mov r9d, [rax + GI_CLUSTER]
    call sh_is_ignorable
    test ecx, ecx
    jz .put
    mov r8d, [rsp + 8]
    test r8d, r8d
    jz .out_next
.put:
    imul ecx, ebp, GPOS_SIZE
    add rcx, [r15 + S_POS]
    mov [rdi + UfontGlyph_glyph], r8d
    mov [rdi + UfontGlyph_cluster], r9d
    mov eax, [rcx + GPOS_XA]
    mov [rdi + UfontGlyph_xa], eax
    mov eax, [rcx + GPOS_YA]
    mov [rdi + UfontGlyph_ya], eax
    mov eax, [rcx + GPOS_XO]
    mov [rdi + UfontGlyph_xo], eax
    mov eax, [rcx + GPOS_YO]
    mov [rdi + UfontGlyph_yo], eax
    add rdi, UfontGlyph_SIZE
    inc r12d
.out_next:
    inc ebp
    jmp .out
.done:
    mov rax, [rsp + 16]
    mov edx, r12d
    jmp .ret
.fail:
    xor eax, eax
    xor edx, edx
.ret:
    add rsp, 24
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; rax = record -> ecx 1 for a default ignorable not substituted
sh_is_ignorable:
    xor ecx, ecx
    test byte [rax + GI_UF], UF_IGN
    jz .out
    test word [rax + GI_PROPS], GP_SUBSTITUTED
    jnz .out
    mov ecx, 1
.out:
    ret

; ----------------------------------------------------------------------------
; sh_graphemes: continuation flags beyond marks, then one cluster per grapheme
; ----------------------------------------------------------------------------
sh_graphemes:
    push rbx
    push r12
    push r13
    mov r12, [r15 + S_INFO]
    xor ebx, ebx
    xor r13d, r13d                      ; anything past ASCII
.each:
    cmp ebx, [r15 + S_LEN]
    jae .clusters
    mov rdi, rbx
    shl rdi, 5
    add rdi, r12
    mov eax, [rdi + GI_CP]
    cmp eax, 0x80
    jb .next
    mov r13d, 1
    movzx ecx, byte [rdi + GI_GC]
    cmp ecx, 5                          ; Ll
    je .next
    cmp ecx, 7                          ; Lo
    je .next
    cmp ecx, 8                          ; Lt
    je .next
    cmp ecx, 9                          ; Lu
    je .next
    cmp ecx, GC_ZS
    je .next
    ; emoji modifiers
    cmp ecx, 24                         ; Sk
    jne .ri
    mov edx, eax
    sub edx, 0x1F3FB
    cmp edx, 4
    jbe .cont
.ri:
    mov edx, eax
    sub edx, 0x1F1E6
    cmp edx, 25
    ja .zwj
    test ebx, ebx
    jz .zwj
    mov edx, [rdi - 32 + GI_CP]
    sub edx, 0x1F1E6
    cmp edx, 25
    ja .next
    test byte [rdi - 32 + GI_UF], UF_CONT
    jnz .next
    jmp .cont
.zwj:
    test byte [rdi + GI_UF], UF_ZWJ
    jz .katakana
    or byte [rdi + GI_UF], UF_CONT
    lea edx, [rbx + 1]
    cmp edx, [r15 + S_LEN]
    jae .next
    push rdi
    sub rsp, 8
    mov edi, [rdi + 32 + GI_CP]
    call sh_is_pict
    add rsp, 8
    pop rdi
    test eax, eax
    jz .next
    inc ebx
    or byte [rdi + 32 + GI_UF], UF_CONT
    jmp .next
.katakana:
    mov edx, eax
    sub edx, 0xFF9E
    cmp edx, 1
    jbe .cont
    mov edx, eax
    sub edx, 0xE0020
    cmp edx, 0x5F
    ja .next
.cont:
    or byte [rdi + GI_UF], UF_CONT
.next:
    inc ebx
    jmp .each
.clusters:
    test r13d, r13d
    jz .out
    xor r13d, r13d                      ; start
    mov ebx, 1
.g:
    cmp ebx, [r15 + S_LEN]
    jae .last
    mov rax, rbx
    shl rax, 5
    add rax, [r15 + S_INFO]
    test byte [rax + GI_UF], UF_CONT
    jnz .g_next
    mov esi, r13d
    mov edx, ebx
    call ufl_buf_merge_clusters
    mov r13d, ebx
.g_next:
    inc ebx
    jmp .g
.last:
    mov esi, r13d
    mov edx, [r15 + S_LEN]
    call ufl_buf_merge_clusters
.out:
    pop r13
    pop r12
    pop rbx
    ret

; edi = code point -> eax 1 when Extended_Pictographic
sh_is_pict:
    lea r8, [rel ufl_ucd_pict]
    xor r9d, r9d
    mov r10d, [rel ufl_ucd_pict_count]
.search:
    cmp r9d, r10d
    jae .no
    lea r11d, [r9 + r10]
    shr r11d, 1
    cmp edi, [r8 + r11 * 8]
    jb .lo
    cmp edi, [r8 + r11 * 8 + 4]
    jbe .yes
    lea r9d, [r11 + 1]
    jmp .search
.lo:
    mov r10d, r11d
    jmp .search
.yes:
    mov eax, 1
    ret
.no:
    xor eax, eax
    ret

; ----------------------------------------------------------------------------
; sh_fractions: digits around U+2044 take numr / frac / dnom
; ----------------------------------------------------------------------------
sh_fractions:
    push rbx
    push r12
    push r13
    push r14
    push rbp
    mov edi, 'frac'
    call ufl_map_get_1_mask
    mov r12d, eax
    mov edi, 'numr'
    call ufl_map_get_1_mask
    mov r13d, eax
    mov edi, 'dnom'
    call ufl_map_get_1_mask
    mov r14d, eax
    test r12d, r12d
    jnz .go
    test r13d, r13d
    jz .out
    test r14d, r14d
    jz .out
.go:
    mov r8, [r15 + S_INFO]
    xor ebx, ebx
.each:
    cmp ebx, [r15 + S_LEN]
    jae .out
    mov rax, rbx
    shl rax, 5
    cmp dword [r8 + rax + GI_CP], 0x2044
    jne .next
    mov ecx, ebx                        ; start
.back:
    test ecx, ecx
    jz .fwd0
    mov rax, rcx
    shl rax, 5
    cmp byte [r8 + rax - 32 + GI_GC], 13    ; Nd
    jne .fwd0
    dec ecx
    jmp .back
.fwd0:
    lea edx, [rbx + 1]                  ; end
.fwd:
    cmp edx, [r15 + S_LEN]
    jae .have
    mov rax, rdx
    shl rax, 5
    cmp byte [r8 + rax + GI_GC], 13
    jne .have
    inc edx
    jmp .fwd
.have:
    cmp ecx, ebx
    je .next
    lea eax, [rbx + 1]
    cmp edx, eax
    je .next
    mov r9d, r13d
    or r9d, r12d                        ; before
    mov r10d, r12d
    or r10d, r14d                       ; after
.pre:
    cmp ecx, ebx
    jae .slash
    mov rax, rcx
    shl rax, 5
    or [r8 + rax + GI_MASK], r9d
    inc ecx
    jmp .pre
.slash:
    mov rax, rbx
    shl rax, 5
    or [r8 + rax + GI_MASK], r12d
    lea ecx, [rbx + 1]
.post:
    cmp ecx, edx
    jae .skip
    mov rax, rcx
    shl rax, 5
    or [r8 + rax + GI_MASK], r10d
    inc ecx
    jmp .post
.skip:
    mov ebx, edx
    jmp .each
.next:
    inc ebx
    jmp .each
.out:
    pop rbp
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------------
; sh_fallback_spaces: spaces drawn with the space glyph get their own width
; ----------------------------------------------------------------------------
sh_fallback_spaces:
    push rbx
    push r12
    push r13
    mov rax, [r15 + S_FONT]
    mov r13d, [rax + UfontFont_upem]
    xor ebx, ebx
.each:
    cmp ebx, [r15 + S_LEN]
    jae .out
    mov rax, rbx
    shl rax, 5
    add rax, [r15 + S_INFO]
    cmp byte [rax + GI_GC], GC_ZS
    jne .next
    test word [rax + GI_PROPS], GP_LIGATED
    jnz .next
    movzx ecx, byte [rax + GI_SPACE]
    imul r12d, ebx, GPOS_SIZE
    add r12, [r15 + S_POS]
    test ecx, ecx
    jz .next
    cmp ecx, 6
    jbe .em
    cmp ecx, SP_EM_16
    je .em
    cmp ecx, SP_4_EM_18
    je .e418
    cmp ecx, SP_FIGURE
    je .figure
    cmp ecx, SP_PUNCT
    je .punct
    cmp ecx, SP_NARROW
    je .narrow
    jmp .next
.em:
    mov eax, ecx
    shr eax, 1
    add eax, r13d
    xor edx, edx
    div ecx
    mov [r12 + GPOS_XA], eax
    jmp .next
.e418:
    mov eax, r13d
    shl eax, 2
    xor edx, edx
    mov ecx, 18
    div ecx
    mov [r12 + GPOS_XA], eax
    jmp .next
.figure:
    mov edi, 0x30
.digit:
    cmp edi, 0x3A
    jae .next
    push rdi
    sub rsp, 8
    call ufl_norm_glyph
    add rsp, 8
    pop rdi
    test eax, eax
    jnz .width
    inc edi
    jmp .digit
.punct:
    mov edi, 0x2E
    call ufl_norm_glyph
    test eax, eax
    jnz .width
    mov edi, 0x2C
    call ufl_norm_glyph
    test eax, eax
    jz .next
.width:
    mov rdi, [r15 + S_FONT]
    mov esi, eax
    call ufont_advance
    mov [r12 + GPOS_XA], eax
    jmp .next
.narrow:
    mov eax, [r12 + GPOS_XA]
    cdq
    sub eax, edx
    sar eax, 1                          ; toward zero
    mov [r12 + GPOS_XA], eax
.next:
    inc ebx
    jmp .each
.out:
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------------
; sh_kern_table: the legacy kern table (version 0, format 0 horizontal
;   subtables) over the run, marks skipped; half the value on the first
;   glyph's advance, the rest on the second's advance and offset
; ----------------------------------------------------------------------------
extern ufl_sk_init
extern ufl_sk_reset
extern ufl_sk_next

sh_kern_table:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    sub rsp, SK_SIZE + 24
    mov rax, [r15 + S_FONT]
    mov r12, [rax + UfontFont_kern]
    test r12, r12
    jz .out
    mov r13, [rax + UfontFont_kern_len]
    add r13, r12                        ; end
    lea rax, [r12 + 4]
    cmp rax, r13
    ja .out
    cmp word [r12], 0                   ; version 0
    jne .out
    BE16 ebp, [r12 + 2]                 ; subtables
    lea r14, [r12 + 4]
    ; the iterator: marks ignored, in the kern mask
    mov dword [r15 + S_LPROPS], 8
    mov eax, [r15 + S_KERNMASK]
    mov [r15 + S_LMASK], eax
    mov byte [r15 + S_GPOS], 1
    mov byte [r15 + S_AZWNJ], 1
    mov byte [r15 + S_AZWJ], 1
    mov byte [r15 + S_PERSYL], 0
    mov byte [r15 + S_HAVEOUT], 0
.subtable:
    test ebp, ebp
    jz .out
    dec ebp
    lea rax, [r14 + 6]
    cmp rax, r13
    ja .out
    BE16 ebx, [r14 + 2]                 ; length
    BE16 ecx, [r14 + 4]                 ; coverage
    mov [rsp + SK_SIZE], r14
    add r14, rbx
    cmp ebx, 6
    jb .out
    ; format 0, horizontal, not cross-stream, not variation
    mov eax, ecx
    shr eax, 8
    jnz .subtable
    test ecx, 1
    jz .subtable
    test ecx, 0x0C
    jnz .subtable
    mov rsi, [rsp + SK_SIZE]
    lea rax, [rsi + 14]
    cmp rax, r13
    ja .subtable
    BE16 eax, [rsi + 6]                 ; pairs
    imul rax, rax, 6
    lea rax, [rsi + rax + 14]
    cmp rax, r13
    ja .subtable
    xor ebx, ebx                        ; idx
.pair:
    cmp ebx, [r15 + S_LEN]
    jae .subtable
    mov rax, rbx
    shl rax, 5
    add rax, [r15 + S_INFO]
    mov ecx, [rax + GI_MASK]
    test ecx, [r15 + S_KERNMASK]
    jz .pair_next
    mov [r15 + S_IDX], ebx
    mov rdi, rsp
    xor esi, esi
    call ufl_sk_init
    mov rdi, rsp
    mov esi, ebx
    mov edx, 1
    call ufl_sk_reset
    mov rdi, rsp
    xor esi, esi
    call ufl_sk_next
    test eax, eax
    jz .pair_next
    ; the pair's value
    mov rax, rbx
    shl rax, 5
    add rax, [r15 + S_INFO]
    mov edi, [rax + GI_GLYPH]
    mov eax, [rsp + SK_IDX]
    shl rax, 5
    add rax, [r15 + S_INFO]
    mov esi, [rax + GI_GLYPH]
    mov rdx, [rsp + SK_SIZE]
    call sh_kern_pair
    test eax, eax
    jz .pair_skip
    mov ecx, eax
    sar ecx, 1                          ; k1
    sub eax, ecx                        ; k2
    imul edx, ebx, GPOS_SIZE
    add rdx, [r15 + S_POS]
    add [rdx + GPOS_XA], ecx
    imul edx, [rsp + SK_IDX], GPOS_SIZE
    add rdx, [r15 + S_POS]
    add [rdx + GPOS_XA], eax
    add [rdx + GPOS_XO], eax
.pair_skip:
    mov ebx, [rsp + SK_IDX]
    jmp .pair
.pair_next:
    inc ebx
    jmp .pair
.out:
    add rsp, SK_SIZE + 24
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; edi = left, esi = right, rdx = subtable -> eax = value (0: none)
sh_kern_pair:
    shl edi, 16
    or edi, esi
    BE16 r8d, [rdx + 6]                 ; pairs
    xor r9d, r9d
.search:
    cmp r9d, r8d
    jae .none
    lea r10d, [r9 + r8]
    shr r10d, 1
    imul eax, r10d, 6
    BE32 ecx, [rdx + rax + 14]          ; left << 16 | right
    cmp edi, ecx
    je .found
    jb .lo
    lea r9d, [r10 + 1]
    jmp .search
.lo:
    mov r8d, r10d
    jmp .search
.found:
    movzx eax, word [rdx + rax + 18]
    xchg al, ah
    movsx eax, ax
    ret
.none:
    xor eax, eax
    ret

; ----------------------------------------------------------------------------
; sh_propagate — edi = glyph, esi = nesting: a mark's offset made relative
;   to the glyphs before it through the chain of attachments
; ----------------------------------------------------------------------------
sh_propagate:
    push rbx
    push r12
    push r13
    mov ebx, edi
    imul eax, ebx, GPOS_SIZE
    mov r12, [r15 + S_POS]
    add r12, rax                        ; pos[i]
    mov ecx, [r12 + GPOS_CHAIN]
    test ecx, ecx
    jz .out
    mov dword [r12 + GPOS_CHAIN], 0
    lea r13d, [rbx + rcx]               ; j
    cmp r13d, [r15 + S_LEN]
    jae .out
    test esi, esi
    jz .out
    mov edi, r13d
    dec esi
    call sh_propagate
    test dword [r12 + GPOS_TYPE], 2
    jz .mark
    ; cursive: the vertical offset of the glyph it hangs from
    imul eax, r13d, GPOS_SIZE
    add rax, [r15 + S_POS]
    mov ecx, [rax + GPOS_YO]
    add [r12 + GPOS_YO], ecx
    jmp .out
.mark:
    test dword [r12 + GPOS_TYPE], 1
    jz .out
    imul eax, r13d, GPOS_SIZE
    add rax, [r15 + S_POS]
    mov ecx, [rax + GPOS_XO]
    add [r12 + GPOS_XO], ecx
    mov ecx, [rax + GPOS_YO]
    add [r12 + GPOS_YO], ecx
.k:
    cmp r13d, ebx
    jae .out
    imul eax, r13d, GPOS_SIZE
    add rax, [r15 + S_POS]
    mov ecx, [rax + GPOS_XA]
    sub [r12 + GPOS_XO], ecx
    mov ecx, [rax + GPOS_YA]
    sub [r12 + GPOS_YO], ecx
    inc r13d
    jmp .k
.out:
    pop r13
    pop r12
    pop rbx
    ret
