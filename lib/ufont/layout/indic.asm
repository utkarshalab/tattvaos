; =============================================================================
; Utkarsha OS — lib/ufont/layout/indic.asm
; =============================================================================
; The Indic shaper - Devanagari, Bengali, Gurmukhi, Gujarati, Oriya, Tamil,
; Telugu, Kannada, Malayalam - as HarfBuzz's: tools/indic.py models it step
; for step.
;
;   ufl_indic_collect_features    locl / ccmp, then nukt, akhn, rphf, rkrf, pref,
;                             blwf, abvf, half, pstf, vatu, cjct a stage each
;                             between initial and final reordering, then init,
;                             pres, abvs, blws, psts, haln; all per syllable
;   ufl_indic_override_features   liga off
;   ufl_indic_data_create         old or new spec (deva / dev2), feature masks
;   ufl_indic_preprocess          vowel constraints: a dotted circle between a
;                             vowel and a sign that would read as another vowel
;   ufl_indic_setup_masks         each character's category and position
;   pauses: syllables (the generated automaton), initial reordering
;   (consonant positions from the font, dotted circles for broken clusters,
;   base, reph, positions, sort, masks), final reordering (pre-base matra,
;   reph, pref, init)
;
; Each script's configuration (in_configs): its virama; where reph goes
; (Devanagari, Gujarati before post-base consonants; Bengali after the
; subjoined ones; Gurmukhi before them; Oriya, Malayalam after the main
; consonant; Tamil, Telugu, Kannada after post-base consonants); how it is
; formed (Ra + halant; Telugu Ra + halant + ZWJ; Malayalam a repha
; character); below forms before and after the base, or after only
; (Telugu, Kannada); its vowel constraints.
; =============================================================================

%include "ufont.inc"
%include "shape.inc"

extern ufl_indic_chars
extern ufl_indic_chars_count
extern ufl_indic_classes
extern ufl_indic_dfa
extern ufl_indic_dfa_classes
extern ufl_indic_accept
extern ufl_ucd_scripts
extern ufl_map_add_feature
extern ufl_map_enable
extern ufl_map_disable
extern ufl_map_add_gsub_pause
extern ufl_map_get_1_mask
extern ufl_map_stage_lookups
extern ufl_ap_would_apply
extern ufl_norm_glyph
extern ufl_buf_clear_output
extern ufl_buf_sync
extern ufl_buf_next_glyph
extern ufl_buf_out_slot
extern ufl_buf_output_info
extern ufl_buf_merge_clusters
extern ufl_buf_move_record
extern ufl_buf_reverse

; categories
%define X 0
%define C 1
%define V 2
%define N 3
%define H 4
%define ZWNJ 5
%define ZWJ 6
%define M 7
%define SM 8
%define A 9
%define PLACEHOLDER 10
%define DOTTEDCIRCLE 11
%define RS 12
%define MPST 13
%define REPHA 14
%define RA 15
%define CM 16
%define SYMBOL 17
%define CS 18
; positions
%define START 0
%define RA_TO_BECOME_REPH 1
%define BEFORE_SUB 7
%define AFTER_SUB 9
%define BEFORE_POST 10
%define AFTER_POST 12
; reph modes, script kinds
%define REPH_IMPLICIT 0
%define REPH_EXPLICIT 1
%define REPH_LOG 2
%define KIND_KNDA 1
%define KIND_MLYM 2
%define KIND_TAML 3
%define KIND_DEVA 4
%define PRE_M 2
%define PRE_C 3
%define BASE_C 4
%define AFTER_MAIN 5
%define BELOW_C 8
%define POST_C 11
%define SMVD 13
%define END_POS 14
; syllable types
%define CONSONANT_SYLLABLE 0
%define VOWEL_SYLLABLE 1
%define STANDALONE_CLUSTER 2
%define BROKEN_CLUSTER 4

%define CONSONANT_FLAGS ((1 << C) | (1 << CS) | (1 << RA) | (1 << CM) | (1 << V) | (1 << PLACEHOLDER) | (1 << DOTTEDCIRCLE))
%define JOINER_FLAGS ((1 << ZWJ) | (1 << ZWNJ))
%define MATRA_FLAGS ((1 << M) | (1 << MPST))

; mask_array slots (S_IMASK + 4 * n)
%define IM_RPHF 2
%define IM_PREF 4
%define IM_BLWF 5
%define IM_ABVF 6
%define IM_HALF 7
%define IM_PSTF 8
%define IM_INIT 11

section .rodata
in_features:                            ; tag, flags (the first eleven: a stage each)
    dd 'nukt', F_GLOBAL | F_MANUAL_JOINERS | F_PER_SYLLABLE
    dd 'akhn', F_GLOBAL | F_MANUAL_JOINERS | F_PER_SYLLABLE
    dd 'rphf', F_MANUAL_JOINERS | F_PER_SYLLABLE
    dd 'rkrf', F_GLOBAL | F_MANUAL_JOINERS | F_PER_SYLLABLE
    dd 'pref', F_MANUAL_JOINERS | F_PER_SYLLABLE
    dd 'blwf', F_MANUAL_JOINERS | F_PER_SYLLABLE
    dd 'abvf', F_MANUAL_JOINERS | F_PER_SYLLABLE
    dd 'half', F_MANUAL_JOINERS | F_PER_SYLLABLE
    dd 'pstf', F_MANUAL_JOINERS | F_PER_SYLLABLE
    dd 'vatu', F_GLOBAL | F_MANUAL_JOINERS | F_PER_SYLLABLE
    dd 'cjct', F_GLOBAL | F_MANUAL_JOINERS | F_PER_SYLLABLE
    dd 'init', F_MANUAL_JOINERS | F_PER_SYLLABLE
    dd 'pres', F_GLOBAL | F_MANUAL_JOINERS | F_PER_SYLLABLE
    dd 'abvs', F_GLOBAL | F_MANUAL_JOINERS | F_PER_SYLLABLE
    dd 'blws', F_GLOBAL | F_MANUAL_JOINERS | F_PER_SYLLABLE
    dd 'psts', F_GLOBAL | F_MANUAL_JOINERS | F_PER_SYLLABLE
    dd 'haln', F_GLOBAL | F_MANUAL_JOINERS | F_PER_SYLLABLE
%define IN_FEATURES 17
%define IN_BASIC 11

; per script: ISO tag, virama, reph position, reph mode, below-forms mode,
; kind, vowel constraint count, the pairs
%define IC_TAG      0
%define IC_VIRAMA   4
%define IC_REPHPOS  8
%define IC_REPHMODE 9
%define IC_BLWF     10
%define IC_KIND     11
%define IC_VCN      12
%define IC_VC       16
%define IC_SIZE     24
align 8
in_configs:
    dd 'Deva', 0x094D
    db BEFORE_POST, REPH_IMPLICIT, 0, KIND_DEVA
    dd (vc_deva_end - vc_deva) / 4
    dq vc_deva
    dd 'Beng', 0x09CD
    db AFTER_SUB, REPH_IMPLICIT, 0, 0
    dd (vc_beng_end - vc_beng) / 4
    dq vc_beng
    dd 'Guru', 0x0A4D
    db BEFORE_SUB, REPH_IMPLICIT, 0, 0
    dd (vc_guru_end - vc_guru) / 4
    dq vc_guru
    dd 'Gujr', 0x0ACD
    db BEFORE_POST, REPH_IMPLICIT, 0, 0
    dd (vc_gujr_end - vc_gujr) / 4
    dq vc_gujr
    dd 'Orya', 0x0B4D
    db AFTER_MAIN, REPH_IMPLICIT, 0, 0
    dd (vc_orya_end - vc_orya) / 4
    dq vc_orya
    dd 'Taml', 0x0BCD
    db AFTER_POST, REPH_IMPLICIT, 0, KIND_TAML
    dd (vc_taml_end - vc_taml) / 4
    dq vc_taml
    dd 'Telu', 0x0C4D
    db AFTER_POST, REPH_EXPLICIT, 1, 0
    dd (vc_telu_end - vc_telu) / 4
    dq vc_telu
    dd 'Knda', 0x0CCD
    db AFTER_POST, REPH_IMPLICIT, 1, KIND_KNDA
    dd (vc_knda_end - vc_knda) / 4
    dq vc_knda
    dd 'Mlym', 0x0D4D
    db AFTER_MAIN, REPH_LOG, 0, KIND_MLYM
    dd (vc_mlym_end - vc_mlym) / 4
    dq vc_mlym
in_configs_end:

; vowel constraints: (vowel, sign) pairs that read as another vowel
vc_deva:
    dw 0x0905, 0x093A, 0x0905, 0x093B, 0x0905, 0x093E, 0x0905, 0x0945, 0x0905, 0x0946, 0x0905, 0x0949
    dw 0x0905, 0x094A, 0x0905, 0x094B, 0x0905, 0x094C, 0x0905, 0x094F, 0x0905, 0x0956, 0x0905, 0x0957
    dw 0x0906, 0x093A, 0x0906, 0x0945, 0x0906, 0x0946, 0x0906, 0x0947, 0x0906, 0x0948
    dw 0x0909, 0x0941, 0x090F, 0x0945, 0x090F, 0x0946, 0x090F, 0x0947
vc_deva_end:
vc_beng: dw 0x0985, 0x09BE, 0x098B, 0x09C3, 0x098C, 0x09E2
vc_beng_end:
vc_guru:
    dw 0x0A05, 0x0A3E, 0x0A05, 0x0A48, 0x0A05, 0x0A4C, 0x0A72, 0x0A3F, 0x0A72, 0x0A40, 0x0A72, 0x0A47
    dw 0x0A73, 0x0A41, 0x0A73, 0x0A42, 0x0A73, 0x0A4B
vc_guru_end:
vc_gujr:
    dw 0x0A85, 0x0ABE, 0x0A85, 0x0AC5, 0x0A85, 0x0AC7, 0x0A85, 0x0AC8, 0x0A85, 0x0AC9, 0x0A85, 0x0ACB
    dw 0x0A85, 0x0ACC, 0x0AC5, 0x0ABE
vc_gujr_end:
vc_orya: dw 0x0B05, 0x0B3E, 0x0B0F, 0x0B57, 0x0B13, 0x0B57
vc_orya_end:
vc_taml: dw 0x0B85, 0x0BC2
vc_taml_end:
vc_telu: dw 0x0C12, 0x0C4C, 0x0C12, 0x0C55, 0x0C3F, 0x0C55, 0x0C46, 0x0C55, 0x0C4A, 0x0C55
vc_telu_end:
vc_knda: dw 0x0C89, 0x0CBE, 0x0C8B, 0x0CBE, 0x0C92, 0x0CCC
vc_knda_end:
vc_mlym: dw 0x0D07, 0x0D57, 0x0D09, 0x0D57, 0x0D0E, 0x0D46, 0x0D12, 0x0D3E, 0x0D12, 0x0D57
vc_mlym_end:

section .text

; the record at index %2 (a 64-bit register holding it) -> %1
%macro REC 2
    mov %1, %2
    shl %1, 5
    add %1, [r15 + S_INFO]
%endmacro
; the record at the index in memory dword %2 -> %1
%macro RECM 2
    movsxd %1, dword %2
    shl %1, 5
    add %1, [r15 + S_INFO]
%endmacro

; is_one_of: rdi = record, esi = flags -> eax 1 / 0 (never for a ligature)
in_is:
    xor eax, eax
    test word [rdi + GI_PROPS], GP_LIGATED
    jnz .out
    movzx ecx, byte [rdi + GI_CAT]
    cmp ecx, 32
    jae .out
    bt esi, ecx
    setc al
.out:
    ret

; FLAG(category) of rdi -> eax (ligation not considered)
in_flag:
    xor eax, eax
    movzx ecx, byte [rdi + GI_CAT]
    cmp ecx, 32
    jae .out
    mov eax, 1
    shl eax, cl
.out:
    ret

; ----------------------------------------------------------------------------
; the plan
; ----------------------------------------------------------------------------
global ufl_indic_collect_features
ufl_indic_collect_features:
    push rbx
    push r12
    sub rsp, 8
    lea rdi, [rel in_setup_syllables]
    call ufl_map_add_gsub_pause
    mov edi, 'locl'
    mov esi, F_PER_SYLLABLE
    mov edx, 1
    call ufl_map_enable
    mov edi, 'ccmp'
    mov esi, F_PER_SYLLABLE
    mov edx, 1
    call ufl_map_enable
    lea rdi, [rel in_initial_reordering]
    call ufl_map_add_gsub_pause
    lea rbx, [rel in_features]
    xor r12d, r12d
.basic:
    mov edi, [rbx + r12 * 8]
    mov esi, [rbx + r12 * 8 + 4]
    mov edx, 1
    call ufl_map_add_feature
    xor edi, edi
    call ufl_map_add_gsub_pause
    inc r12d
    cmp r12d, IN_BASIC
    jb .basic
    lea rdi, [rel in_final_reordering]
    call ufl_map_add_gsub_pause
.other:
    mov edi, [rbx + r12 * 8]
    mov esi, [rbx + r12 * 8 + 4]
    mov edx, 1
    call ufl_map_add_feature
    inc r12d
    cmp r12d, IN_FEATURES
    jb .other
    add rsp, 8
    pop r12
    pop rbx
    ret

global ufl_indic_override_features
ufl_indic_override_features:
    sub rsp, 8
    mov edi, 'liga'
    call ufl_map_disable
    xor edi, edi
    call ufl_map_add_gsub_pause
    add rsp, 8
    ret

global ufl_indic_data_create
ufl_indic_data_create:
    push rbx
    push r12
    sub rsp, 8
    ; old spec unless the script tag found ends in '2'
    mov eax, [r15 + S_CHOSEN]
    shr eax, 24
    cmp eax, '2'
    setne byte [r15 + S_IOLD]
    mov dword [r15 + S_IVIRAMA], -1
    ; the script's configuration (Devanagari's when it has none)
    mov eax, [r15 + S_SCRIPT]
    imul eax, eax, 12
    lea rcx, [rel ufl_ucd_scripts]
    mov eax, [rcx + rax]
    lea rbx, [rel in_configs]
.config:
    lea rcx, [rel in_configs_end]
    cmp rbx, rcx
    jae .config_default
    cmp [rbx + IC_TAG], eax
    je .config_found
    add rbx, IC_SIZE
    jmp .config
.config_default:
    lea rbx, [rel in_configs]
.config_found:
    mov eax, [rbx + IC_VIRAMA]
    mov [r15 + S_ICP], eax
    mov al, [rbx + IC_REPHPOS]
    mov [r15 + S_IREPHPOS], al
    mov al, [rbx + IC_REPHMODE]
    mov [r15 + S_IREPHMODE], al
    mov al, [rbx + IC_BLWF]
    mov [r15 + S_IBLWF], al
    mov al, [rbx + IC_KIND]
    mov [r15 + S_IKIND], al
    mov eax, [rbx + IC_VCN]
    mov [r15 + S_IVCN], eax
    mov rax, [rbx + IC_VC]
    mov [r15 + S_IVC], rax
    ; zero-context would-substitute in the new spec (not Malayalam)
    xor eax, eax
    cmp byte [r15 + S_IOLD], 0
    jne .zero
    cmp byte [r15 + S_IKIND], KIND_MLYM
    je .zero
    inc eax
.zero:
    mov [r15 + S_IZERO], al
    lea rbx, [rel in_features]
    xor r12d, r12d
.mask:
    xor eax, eax
    test dword [rbx + r12 * 8 + 4], F_GLOBAL
    jnz .set
    mov edi, [rbx + r12 * 8]
    call ufl_map_get_1_mask
.set:
    mov [r15 + S_IMASK + r12 * 4], eax
    inc r12d
    cmp r12d, IN_FEATURES
    jb .mask
    add rsp, 8
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------------
; would_substitute — edi = feature tag, rsi = glyphs (u32), edx = count ->
;   eax 1 when a lookup of the feature's stage would substitute them
; ----------------------------------------------------------------------------
in_would:
    push rbx
    push r12
    push r13
    push r14
    push rbp
    mov r13, rsi
    mov r14d, edx
    mov esi, edi
    xor edi, edi
    call ufl_map_stage_lookups
    mov rbx, rax
    mov r12d, ecx
.each:
    test r12d, r12d
    jz .no
    mov edi, [rbx + LK_INDEX]
    mov rsi, r13
    mov edx, r14d
    movzx ecx, byte [r15 + S_IZERO]
    call ufl_ap_would_apply
    add rbx, LK_SIZE
    dec r12d
    test eax, eax
    jz .each
    mov eax, 1
    jmp .out
.no:
    xor eax, eax
.out:
    pop rbp
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------------
; ufl_indic_preprocess: vowel constraints
; ----------------------------------------------------------------------------
global ufl_indic_preprocess
ufl_indic_preprocess:
    push rbx
    push r12
    push r13
    call ufl_buf_clear_output
    mov dword [r15 + S_IDX], 0
    mov r12d, [r15 + S_LEN]             ; count
.loop:
    mov eax, [r15 + S_IDX]
    inc eax
    cmp eax, r12d
    jae .done
    xor r13d, r13d                      ; matched
    RECM rbx, [r15 + S_IDX]
    mov eax, [rbx + GI_CP]
    mov ecx, [rbx + 32 + GI_CP]
    ; Devanagari: Ra, halant, I
    cmp byte [r15 + S_IKIND], KIND_DEVA
    jne .pairs
    cmp eax, 0x0930
    jne .pairs
    cmp ecx, 0x094D
    jne .pairs
    mov edx, [r15 + S_IDX]
    add edx, 2
    cmp edx, r12d
    jae .pairs
    cmp dword [rbx + 64 + GI_CP], 0x0907
    jne .pairs
    call ufl_buf_next_glyph
    jmp .yes
.pairs:
    mov rdx, [r15 + S_IVC]
    mov r8d, [r15 + S_IVCN]
.pair:
    test r8d, r8d
    jz .next
    movzx r9d, word [rdx]
    movzx r10d, word [rdx + 2]
    add rdx, 4
    dec r8d
    cmp r9d, eax
    jne .pair
    cmp r10d, ecx
    jne .pair
.yes:
    mov r13d, 1
.next:
    call ufl_buf_next_glyph
    test r13d, r13d
    jz .loop
    ; a copy of the current character as a dotted circle, then the character
    call ufl_buf_out_slot
    RECM rsi, [r15 + S_IDX]
    movdqu xmm0, [rsi]
    movdqu xmm1, [rsi + 16]
    movdqu [rdi], xmm0
    movdqu [rdi + 16], xmm1
    mov dword [rdi + GI_CP], 0x25CC
    and byte [rdi + GI_UF], ~UF_CONT
    call ufl_buf_next_glyph
    jmp .loop
.done:
    call ufl_buf_sync
    pop r13
    pop r12
    pop rbx
    ret


; ----------------------------------------------------------------------------
; ufl_indic_setup_masks: categories and positions
; ----------------------------------------------------------------------------
global ufl_indic_setup_masks
ufl_indic_setup_masks:
    push rbx
    xor ebx, ebx
.each:
    cmp ebx, [r15 + S_LEN]
    jae .done
    REC rdi, rbx
    mov esi, [rdi + GI_CP]
    call in_lookup
    mov [rdi + GI_CAT], al
    mov [rdi + GI_POS], dl
    inc ebx
    jmp .each
.done:
    pop rbx
    ret

; esi = code point -> al = category, dl = position (keeps rdi)
in_lookup:
    lea r8, [rel ufl_indic_chars]
    xor r9d, r9d
    mov r10d, [rel ufl_indic_chars_count]
.search:
    cmp r9d, r10d
    jae .none
    lea r11d, [r9 + r10]
    shr r11d, 1
    cmp esi, [r8 + r11 * 8]
    je .found
    jb .lo
    lea r9d, [r11 + 1]
    jmp .search
.lo:
    mov r10d, r11d
    jmp .search
.found:
    mov al, [r8 + r11 * 8 + 4]
    mov dl, [r8 + r11 * 8 + 5]
    ret
.none:
    xor eax, eax
    mov edx, END_POS
    ret

; ----------------------------------------------------------------------------
; pause: syllables
; ----------------------------------------------------------------------------
in_setup_syllables:
    push rbx
    push r12
    push r13
    push r14
    push rbp
    lea r12, [rel ufl_indic_classes]
    lea r13, [rel ufl_indic_dfa]
    mov ebp, 1                          ; serial
    xor ebx, ebx                        ; p
.syllable:
    cmp ebx, [r15 + S_LEN]
    jae .done
    xor ecx, ecx                        ; state
    mov r8d, ebx                        ; q
    mov r9d, -1                         ; best end
    xor r10d, r10d                      ; its type
.step:
    cmp r8d, [r15 + S_LEN]
    jae .have
    REC rax, r8
    movzx eax, byte [rax + GI_CAT]
    and eax, 63
    movzx eax, byte [r12 + rax]         ; class
    imul ecx, [rel ufl_indic_dfa_classes]
    add ecx, eax
    movzx ecx, byte [r13 + rcx]
    cmp ecx, 255
    je .have
    inc r8d
    lea rax, [rel ufl_indic_accept]
    movzx eax, byte [rax + rcx]
    cmp eax, 255
    je .step
    mov r9d, r8d
    mov r10d, eax
    jmp .step
.have:
    cmp r9d, -1
    jne .mark
    lea r9d, [rbx + 1]                  ; cannot happen: anything is a syllable
    mov r10d, 5
.mark:
    mov eax, ebp
    shl eax, 4
    or eax, r10d
.set:
    cmp ebx, r9d
    jae .marked
    REC rdx, rbx
    mov [rdx + GI_SYL], al
    inc ebx
    jmp .set
.marked:
    cmp r10d, BROKEN_CLUSTER
    jne .serial
    mov byte [r15 + S_IBROKEN], 1
.serial:
    inc ebp
    cmp ebp, 16
    jne .syllable
    mov ebp, 1
    jmp .syllable
.done:
    pop rbp
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; esi = start -> eax = the end of its syllable
in_syllable_end:
    REC rdx, rsi
    mov cl, [rdx + GI_SYL]
    lea eax, [rsi + 1]
.more:
    cmp eax, [r15 + S_LEN]
    jae .out
    REC rdx, rax
    cmp [rdx + GI_SYL], cl
    jne .out
    inc eax
    jmp .more
.out:
    ret

; ----------------------------------------------------------------------------
; pause: initial reordering
; ----------------------------------------------------------------------------
in_initial_reordering:
    push rbx
    push r12
    sub rsp, 8
    call in_consonant_positions
    call in_dotted_circles
    xor ebx, ebx
.each:
    cmp ebx, [r15 + S_LEN]
    jae .done
    mov esi, ebx
    call in_syllable_end
    mov r12d, eax
    REC rax, rbx
    movzx eax, byte [rax + GI_SYL]
    and eax, 0x0F
    cmp eax, BROKEN_CLUSTER
    je .reorder
    cmp eax, STANDALONE_CLUSTER
    ja .next
.reorder:
    mov edi, ebx
    mov esi, r12d
    call in_initial_syllable
.next:
    mov ebx, r12d
    jmp .each
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret

; the virama glyph, looked up once -> eax (0 none)
in_virama:
    mov eax, [r15 + S_IVIRAMA]
    cmp eax, -1
    jne .out
    sub rsp, 8
    mov edi, [r15 + S_ICP]
    call ufl_norm_glyph
    add rsp, 8
    mov [r15 + S_IVIRAMA], eax
.out:
    ret

in_consonant_positions:
    push rbx
    push r12
    push r13
    sub rsp, 16
    call in_virama
    test eax, eax
    jz .out
    mov r13d, eax
    xor ebx, ebx
.each:
    cmp ebx, [r15 + S_LEN]
    jae .out
    REC r12, rbx
    cmp byte [r12 + GI_POS], BASE_C
    jne .next
    ; virama, consonant, virama
    mov [rsp], r13d
    mov eax, [r12 + GI_GLYPH]
    mov [rsp + 4], eax
    mov [rsp + 8], r13d
    mov ecx, BELOW_C
    mov edi, 'blwf'
    call .both
    jnz .set
    mov edi, 'vatu'
    call .both
    jnz .set
    mov ecx, POST_C
    mov edi, 'pstf'
    call .both
    jnz .set
    mov edi, 'pref'
    call .both
    jnz .set
    mov ecx, BASE_C
.set:
    REC r12, rbx
    mov [r12 + GI_POS], cl
.next:
    inc ebx
    jmp .each
.out:
    add rsp, 16
    pop r13
    pop r12
    pop rbx
    ret
; edi = tag, ecx = position to keep -> ZF clear when (virama, c) or (c,
;   virama) would substitute; ecx kept
.both:
    push rcx
    push rdi
    sub rsp, 8
    lea rsi, [rsp + 32]                 ; the caller's [rsp]
    mov edx, 2
    call in_would
    test eax, eax
    jnz .both_out
    mov edi, [rsp + 8]
    lea rsi, [rsp + 36]
    mov edx, 2
    call in_would
.both_out:
    add rsp, 8
    pop rdi
    pop rcx
    test eax, eax
    ret

in_dotted_circles:
    push rbx
    push r12
    push r13
    sub rsp, 32                         ; the dotted circle record
    cmp byte [r15 + S_IBROKEN], 0
    je .out
    mov edi, 0x25CC
    call ufl_norm_glyph
    test eax, eax
    jz .out
    mov r13d, eax
    call ufl_buf_clear_output
    mov dword [r15 + S_IDX], 0
    xor r12d, r12d                      ; last syllable
.each:
    mov eax, [r15 + S_IDX]
    cmp eax, [r15 + S_LEN]
    jae .done
    REC rbx, rax
    movzx eax, byte [rbx + GI_SYL]
    cmp eax, r12d
    je .next
    mov ecx, eax
    and ecx, 0x0F
    cmp ecx, BROKEN_CLUSTER
    jne .next
    mov r12d, eax
    ; a record of zeros but for these
    xor eax, eax
    mov [rsp], rax
    mov [rsp + 8], rax
    mov [rsp + 16], rax
    mov [rsp + 24], rax
    mov dword [rsp + GI_CP], 0x25CC
    mov [rsp + GI_GLYPH], r13d
    mov eax, [rbx + GI_CLUSTER]
    mov [rsp + GI_CLUSTER], eax
    mov eax, [rbx + GI_MASK]
    mov [rsp + GI_MASK], eax
    mov [rsp + GI_SYL], r12b
    mov byte [rsp + GI_GC], GC_CC
    mov byte [rsp + GI_CAT], DOTTEDCIRCLE
    mov byte [rsp + GI_POS], END_POS
.repha:
    mov eax, [r15 + S_IDX]
    cmp eax, [r15 + S_LEN]
    jae .put
    REC rbx, rax
    movzx eax, byte [rbx + GI_SYL]
    cmp eax, r12d
    jne .put
    cmp byte [rbx + GI_CAT], REPHA
    jne .put
    call ufl_buf_next_glyph
    jmp .repha
.put:
    mov rsi, rsp
    call ufl_buf_output_info
    jmp .each
.next:
    call ufl_buf_next_glyph
    jmp .each
.done:
    call ufl_buf_sync
.out:
    add rsp, 32
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------------
; initial reordering of a consonant syllable — edi = start, esi = end
; ----------------------------------------------------------------------------
%define IR_START   0
%define IR_END     4
%define IR_BASE    8
%define IR_LIMIT   12
%define IR_REPH    16
%define IR_SEEN    20
%define IR_SYL     24
%define IR_FLM     28
%define IR_LLM     32
%define IR_LAST    36
%define IR_G       40                   ; glyphs for would_substitute (u32 x 3)
%define IR_SIZE    64

in_initial_syllable:
    push rbx
    push r12
    push r13
    push r14
    push rbp
    sub rsp, IR_SIZE
    mov [rsp + IR_START], edi
    mov [rsp + IR_END], esi
    mov [rsp + IR_BASE], esi
    mov dword [rsp + IR_REPH], 0
    mov [rsp + IR_LIMIT], edi
    ; Kannada: Ra, halant, ZWJ become Ra, ZWJ, halant (no reph)
    cmp byte [r15 + S_IKIND], KIND_KNDA
    jne .reph
    lea eax, [rdi + 3]
    cmp eax, esi
    ja .reph
    REC rbx, rdi
    mov rdi, rbx
    mov esi, 1 << RA
    call in_is
    test eax, eax
    jz .reph
    lea rdi, [rbx + 32]
    mov esi, 1 << H
    call in_is
    test eax, eax
    jz .reph
    lea rdi, [rbx + 64]
    mov esi, 1 << ZWJ
    call in_is
    test eax, eax
    jz .reph
    mov esi, [rsp + IR_START]
    inc esi
    lea edx, [rsi + 2]
    call ufl_buf_merge_clusters
    RECM rbx, [rsp + IR_START]
    movdqu xmm0, [rbx + 32]
    movdqu xmm1, [rbx + 48]
    movdqu xmm2, [rbx + 64]
    movdqu xmm3, [rbx + 80]
    movdqu [rbx + 32], xmm2
    movdqu [rbx + 48], xmm3
    movdqu [rbx + 64], xmm0
    movdqu [rbx + 80], xmm1
.reph:
    ; reph: Ra, halant (not followed by a joiner; Telugu: followed by ZWJ)
    ; that rphf would substitute; Malayalam: a repha character
    mov edi, [rsp + IR_START]
    mov esi, [rsp + IR_END]
    cmp byte [r15 + S_IREPHMODE], REPH_LOG
    je .log_repha
    cmp dword [r15 + S_IMASK + IM_RPHF * 4], 0
    je .base_search
    lea eax, [rdi + 3]
    cmp eax, esi
    ja .base_search
    REC rbx, rdi
    mov dword [rsp + IR_G + 8], 0
    cmp byte [r15 + S_IREPHMODE], REPH_EXPLICIT
    je .explicit
    lea rdi, [rbx + 64]
    mov esi, JOINER_FLAGS
    call in_is
    test eax, eax
    jnz .base_search
    jmp .reph_glyphs
.explicit:
    cmp byte [rbx + 64 + GI_CAT], ZWJ
    jne .base_search
    mov eax, [rbx + 64 + GI_GLYPH]
    mov [rsp + IR_G + 8], eax
.reph_glyphs:
    mov eax, [rbx + GI_GLYPH]
    mov [rsp + IR_G], eax
    mov eax, [rbx + 32 + GI_GLYPH]
    mov [rsp + IR_G + 4], eax
    mov edi, 'rphf'
    lea rsi, [rsp + IR_G]
    mov edx, 2
    call in_would
    test eax, eax
    jnz .reph_found
    cmp byte [r15 + S_IREPHMODE], REPH_EXPLICIT
    jne .base_search
    mov edi, 'rphf'
    lea rsi, [rsp + IR_G]
    mov edx, 3
    call in_would
    test eax, eax
    jz .base_search
.reph_found:
    mov eax, [rsp + IR_START]
    add eax, 2
    jmp .lim
.log_repha:
    REC rbx, rdi
    cmp byte [rbx + GI_CAT], REPHA
    jne .base_search
    lea eax, [rdi + 1]
.lim:
    cmp eax, [rsp + IR_END]
    jae .lim_done
    REC rdi, rax
    push rax
    sub rsp, 8
    mov esi, JOINER_FLAGS
    call in_is
    add rsp, 8
    mov ecx, eax
    pop rax
    test ecx, ecx
    jz .lim_done
    inc eax
    jmp .lim
.lim_done:
    mov [rsp + IR_LIMIT], eax
    mov eax, [rsp + IR_START]
    mov [rsp + IR_BASE], eax
    mov dword [rsp + IR_REPH], 1
.base_search:
    mov ebx, [rsp + IR_END]             ; i
    mov dword [rsp + IR_SEEN], 0
.bs:
    dec ebx
    REC r12, rbx
    mov rdi, r12
    mov esi, CONSONANT_FLAGS
    call in_is
    test eax, eax
    jz .bs_other
    movzx eax, byte [r12 + GI_POS]
    cmp eax, BELOW_C
    je .bs_below
    cmp eax, POST_C
    jne .bs_base
    cmp dword [rsp + IR_SEEN], 0
    je .bs_set
.bs_base:
    mov [rsp + IR_BASE], ebx
    jmp .bs_done
.bs_below:
    mov dword [rsp + IR_SEEN], 1
.bs_set:
    mov [rsp + IR_BASE], ebx
    jmp .bs_cond
.bs_other:
    cmp ebx, [rsp + IR_START]
    jbe .bs_cond
    cmp byte [r12 + GI_CAT], ZWJ
    jne .bs_cond
    cmp byte [r12 - 32 + GI_CAT], H
    je .bs_done
.bs_cond:
    cmp ebx, [rsp + IR_LIMIT]
    ja .bs
.bs_done:
    cmp dword [rsp + IR_REPH], 0
    je .positions
    mov eax, [rsp + IR_BASE]
    cmp eax, [rsp + IR_START]
    jne .positions
    mov ecx, [rsp + IR_LIMIT]
    sub ecx, eax
    cmp ecx, 2
    ja .positions
    mov dword [rsp + IR_REPH], 0
.positions:
    ; before the base: at most pre-base consonants
    mov ebx, [rsp + IR_START]
.pre:
    cmp ebx, [rsp + IR_BASE]
    jae .pre_done
    REC rax, rbx
    cmp byte [rax + GI_POS], PRE_C
    jbe .pre_next
    mov byte [rax + GI_POS], PRE_C
.pre_next:
    inc ebx
    jmp .pre
.pre_done:
    mov eax, [rsp + IR_BASE]
    cmp eax, [rsp + IR_END]
    jae .no_base
    REC rcx, rax
    mov byte [rcx + GI_POS], BASE_C
.no_base:
    cmp dword [rsp + IR_REPH], 0
    je .old_spec
    RECM rcx, [rsp + IR_START]
    mov byte [rcx + GI_POS], RA_TO_BECOME_REPH
.old_spec:
    ; old spec: the first halant after the base goes after the last consonant
    cmp byte [r15 + S_IOLD], 0
    je .attach
    mov ebx, [rsp + IR_BASE]
    inc ebx
.os:
    cmp ebx, [rsp + IR_END]
    jae .attach
    REC rax, rbx
    cmp byte [rax + GI_CAT], H
    je .os_halant
    inc ebx
    jmp .os
.os_halant:
    mov r12d, [rsp + IR_END]
    dec r12d                            ; j
.os_j:
    cmp r12d, ebx
    jbe .os_check
    REC rdi, r12
    mov esi, CONSONANT_FLAGS
    call in_is
    test eax, eax
    jnz .os_check
    cmp byte [r15 + S_IKIND], KIND_KNDA
    jne .os_j_next
    REC rax, r12
    cmp byte [rax + GI_CAT], H
    je .os_check
.os_j_next:
    dec r12d
    jmp .os_j
.os_check:
    REC rax, r12
    cmp byte [rax + GI_CAT], H
    je .attach
    cmp r12d, ebx
    jbe .attach
    mov esi, ebx
    mov edx, r12d
    call ufl_buf_move_record
.attach:
    ; joiners, nuktas, register shifters, medials and halants take the
    ; position before them
    xor r13d, r13d                      ; last position
    mov ebx, [rsp + IR_START]
.at:
    cmp ebx, [rsp + IR_END]
    jae .at_done
    REC r12, rbx
    mov rdi, r12
    call in_flag
    test eax, JOINER_FLAGS | (1 << N) | (1 << RS) | (1 << CM) | (1 << H)
    jz .at_other
    mov [r12 + GI_POS], r13b
    cmp byte [r12 + GI_CAT], H
    jne .at_next
    cmp r13d, PRE_M
    jne .at_next
    ; a halant after a pre-base matra takes the position before the matras
    mov ecx, ebx
.at_back:
    cmp ecx, [rsp + IR_START]
    jbe .at_next
    REC rax, rcx
    movzx edx, byte [rax - 32 + GI_POS]
    cmp edx, PRE_M
    je .at_back_next
    mov [r12 + GI_POS], dl
    jmp .at_next
.at_back_next:
    dec ecx
    jmp .at_back
.at_other:
    movzx eax, byte [r12 + GI_POS]
    cmp eax, SMVD
    je .at_next
    cmp byte [r12 + GI_CAT], MPST
    jne .at_last
    cmp ebx, [rsp + IR_START]
    jbe .at_last
    cmp byte [r12 - 32 + GI_CAT], SM
    jne .at_last
    mov [r12 - 32 + GI_POS], al
.at_last:
    mov r13d, eax
.at_next:
    inc ebx
    jmp .at
.at_done:
    ; what follows the base belongs to the next consonant
    mov eax, [rsp + IR_BASE]
    mov [rsp + IR_LAST], eax
    lea ebx, [rax + 1]
.own:
    cmp ebx, [rsp + IR_END]
    jae .own_done
    REC r12, rbx
    mov rdi, r12
    mov esi, CONSONANT_FLAGS
    call in_is
    test eax, eax
    jz .own_matra
    mov ecx, [rsp + IR_LAST]
    inc ecx
    mov dl, [r12 + GI_POS]
.own_fill:
    cmp ecx, ebx
    jae .own_fill_done
    REC rax, rcx
    cmp byte [rax + GI_POS], SMVD
    jae .own_fill_next
    mov [rax + GI_POS], dl
.own_fill_next:
    inc ecx
    jmp .own_fill
.own_fill_done:
    mov [rsp + IR_LAST], ebx
    jmp .own_next
.own_matra:
    mov rdi, r12
    call in_flag
    test eax, MATRA_FLAGS
    jz .own_next
    mov [rsp + IR_LAST], ebx
.own_next:
    inc ebx
    jmp .own
.own_done:
    ; sort by position, remembering where each came from
    RECM rax, [rsp + IR_START]
    movzx eax, byte [rax + GI_SYL]
    mov [rsp + IR_SYL], eax
    mov ebx, [rsp + IR_START]
.orig:
    cmp ebx, [rsp + IR_END]
    jae .sort
    REC rax, rbx
    mov ecx, ebx
    sub ecx, [rsp + IR_START]
    mov [rax + GI_SYL], cl
    inc ebx
    jmp .orig
.sort:
    mov ebx, [rsp + IR_START]
    inc ebx
.sort_i:
    cmp ebx, [rsp + IR_END]
    jae .sorted
    REC rax, rbx
    movzx r8d, byte [rax + GI_POS]
    mov edx, ebx                        ; j
.sort_j:
    cmp edx, [rsp + IR_START]
    jbe .sort_put
    REC rax, rdx
    cmp [rax - 32 + GI_POS], r8b
    jbe .sort_put
    dec edx
    jmp .sort_j
.sort_put:
    cmp edx, ebx
    je .sort_next
    mov esi, ebx
    call ufl_buf_move_record
.sort_next:
    inc ebx
    jmp .sort_i
.sorted:
    ; the base again, and the run of pre-base matras
    mov eax, [rsp + IR_END]
    mov [rsp + IR_FLM], eax
    mov [rsp + IR_LLM], eax
    mov [rsp + IR_BASE], eax
    mov ebx, [rsp + IR_START]
.find:
    cmp ebx, [rsp + IR_END]
    jae .found
    REC rax, rbx
    movzx ecx, byte [rax + GI_POS]
    cmp ecx, BASE_C
    jne .find_lm
    mov [rsp + IR_BASE], ebx
    jmp .found
.find_lm:
    cmp ecx, PRE_M
    jne .find_next
    mov eax, [rsp + IR_END]
    cmp [rsp + IR_FLM], eax
    jne .find_last
    mov [rsp + IR_FLM], ebx
.find_last:
    mov [rsp + IR_LLM], ebx
.find_next:
    inc ebx
    jmp .find
.found:
    ; several left matras: their order reversed, each with its own marks
    mov eax, [rsp + IR_FLM]
    cmp eax, [rsp + IR_LLM]
    jae .merge
    mov esi, eax
    mov edx, [rsp + IR_LLM]
    inc edx
    call ufl_buf_reverse
    mov r13d, [rsp + IR_FLM]            ; i
    mov ebx, r13d                       ; j
.lm:
    cmp ebx, [rsp + IR_LLM]
    ja .merge
    REC rdi, rbx
    call in_flag
    test eax, MATRA_FLAGS
    jz .lm_next
    mov esi, r13d
    lea edx, [rbx + 1]
    call ufl_buf_reverse
    lea r13d, [rbx + 1]
.lm_next:
    inc ebx
    jmp .lm
.merge:
    ; clusters: merged over what moved (old spec: from the base on)
    cmp byte [r15 + S_IOLD], 0
    jne .merge_all
    mov eax, [rsp + IR_END]
    sub eax, [rsp + IR_START]
    cmp eax, 127
    ja .merge_all
    mov ebx, [rsp + IR_BASE]
.cyc:
    cmp ebx, [rsp + IR_END]
    jae .restore
    REC rax, rbx
    movzx ecx, byte [rax + GI_SYL]
    cmp ecx, 255
    je .cyc_next
    mov r12d, ebx                       ; min
    mov r13d, ebx                       ; max
    lea edx, [rcx]
    add edx, [rsp + IR_START]           ; j
.cyc_walk:
    cmp edx, ebx
    je .cyc_merge
    cmp edx, r12d
    jae .cyc_max
    mov r12d, edx
.cyc_max:
    cmp edx, r13d
    jbe .cyc_go
    mov r13d, edx
.cyc_go:
    REC rax, rdx
    movzx ecx, byte [rax + GI_SYL]
    mov byte [rax + GI_SYL], 255
    lea edx, [rcx]
    add edx, [rsp + IR_START]
    jmp .cyc_walk
.cyc_merge:
    mov esi, r12d
    cmp esi, [rsp + IR_BASE]
    jae .cyc_lo
    mov esi, [rsp + IR_BASE]
.cyc_lo:
    lea edx, [r13 + 1]
    call ufl_buf_merge_clusters
.cyc_next:
    inc ebx
    jmp .cyc
.merge_all:
    mov esi, [rsp + IR_BASE]
    mov edx, [rsp + IR_END]
    call ufl_buf_merge_clusters
.restore:
    mov ebx, [rsp + IR_START]
    mov eax, [rsp + IR_SYL]
.rs:
    cmp ebx, [rsp + IR_END]
    jae .masks
    REC rcx, rbx
    mov [rcx + GI_SYL], al
    inc ebx
    jmp .rs
.masks:
    ; reph
    mov ebx, [rsp + IR_START]
    mov eax, [r15 + S_IMASK + IM_RPHF * 4]
.m_reph:
    cmp ebx, [rsp + IR_END]
    jae .m_pre
    REC rcx, rbx
    cmp byte [rcx + GI_POS], RA_TO_BECOME_REPH
    jne .m_pre
    or [rcx + GI_MASK], eax
    inc ebx
    jmp .m_reph
.m_pre:
    ; before the base: half (and below forms in the new spec)
    mov eax, [r15 + S_IMASK + IM_HALF * 4]
    cmp byte [r15 + S_IOLD], 0
    jne .m_pre_mask
    cmp byte [r15 + S_IBLWF], 0
    jne .m_pre_mask
    or eax, [r15 + S_IMASK + IM_BLWF * 4]
.m_pre_mask:
    mov ebx, [rsp + IR_START]
.m_pre_loop:
    cmp ebx, [rsp + IR_BASE]
    jae .m_post
    REC rcx, rbx
    or [rcx + GI_MASK], eax
    inc ebx
    jmp .m_pre_loop
.m_post:
    mov eax, [r15 + S_IMASK + IM_BLWF * 4]
    or eax, [r15 + S_IMASK + IM_ABVF * 4]
    or eax, [r15 + S_IMASK + IM_PSTF * 4]
    mov ebx, [rsp + IR_BASE]
    inc ebx
.m_post_loop:
    cmp ebx, [rsp + IR_END]
    jae .m_old
    REC rcx, rbx
    or [rcx + GI_MASK], eax
    inc ebx
    jmp .m_post_loop
.m_old:
    ; old-spec Devanagari: Ra, halant before the base take below forms
    cmp byte [r15 + S_IOLD], 0
    je .m_pref
    cmp byte [r15 + S_IKIND], KIND_DEVA
    jne .m_pref
    mov ebx, [rsp + IR_START]
.mo:
    lea eax, [rbx + 1]
    cmp eax, [rsp + IR_BASE]
    jae .m_pref
    REC rcx, rbx
    cmp byte [rcx + GI_CAT], RA
    jne .mo_next
    cmp byte [rcx + 32 + GI_CAT], H
    jne .mo_next
    lea eax, [rbx + 2]
    cmp eax, [rsp + IR_BASE]
    je .mo_set
    cmp byte [rcx + 64 + GI_CAT], ZWJ
    je .mo_next
.mo_set:
    mov eax, [r15 + S_IMASK + IM_BLWF * 4]
    or [rcx + GI_MASK], eax
    or [rcx + 32 + GI_MASK], eax
.mo_next:
    inc ebx
    jmp .mo
.m_pref:
    ; the first pair after the base pref would substitute
    cmp dword [r15 + S_IMASK + IM_PREF * 4], 0
    je .m_zwnj
    mov eax, [rsp + IR_BASE]
    add eax, 2
    cmp eax, [rsp + IR_END]
    jae .m_zwnj
    mov ebx, [rsp + IR_BASE]
    inc ebx
.mp:
    lea eax, [rbx + 1]
    cmp eax, [rsp + IR_END]
    jae .m_zwnj
    REC rcx, rbx
    mov eax, [rcx + GI_GLYPH]
    mov [rsp + IR_G], eax
    mov eax, [rcx + 32 + GI_GLYPH]
    mov [rsp + IR_G + 4], eax
    mov edi, 'pref'
    lea rsi, [rsp + IR_G]
    mov edx, 2
    call in_would
    test eax, eax
    jz .mp_next
    REC rcx, rbx
    mov eax, [r15 + S_IMASK + IM_PREF * 4]
    or [rcx + GI_MASK], eax
    or [rcx + 32 + GI_MASK], eax
    jmp .m_zwnj
.mp_next:
    inc ebx
    jmp .mp
.m_zwnj:
    ; a ZWNJ keeps the consonants before it from half forms
    mov ebx, [rsp + IR_START]
    inc ebx
.zw:
    cmp ebx, [rsp + IR_END]
    jae .out
    REC rdi, rbx
    mov esi, JOINER_FLAGS
    call in_is
    test eax, eax
    jz .zw_next
    REC rax, rbx
    xor r13d, r13d
    cmp byte [rax + GI_CAT], ZWNJ
    sete r13b
    mov r12d, ebx                       ; j
.zw_back:
    dec r12d
    test r13d, r13d
    jz .zw_cond
    REC rax, r12
    mov ecx, [r15 + S_IMASK + IM_HALF * 4]
    not ecx
    and [rax + GI_MASK], ecx
.zw_cond:
    cmp r12d, [rsp + IR_START]
    jbe .zw_next
    REC rdi, r12
    mov esi, CONSONANT_FLAGS
    call in_is
    test eax, eax
    jz .zw_back
.zw_next:
    inc ebx
    jmp .zw
.out:
    add rsp, IR_SIZE
    pop rbp
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------------
; pause: final reordering
; ----------------------------------------------------------------------------
in_final_reordering:
    push rbx
    push r12
    sub rsp, 8
    xor ebx, ebx
.each:
    cmp ebx, [r15 + S_LEN]
    jae .done
    mov esi, ebx
    call in_syllable_end
    mov r12d, eax
    mov edi, ebx
    mov esi, r12d
    call in_final_syllable
    mov ebx, r12d
    jmp .each
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret

%define FR_START   0
%define FR_END     4
%define FR_BASE    8
%define FR_PREF    12                   ; try pref
%define FR_NEW     16
%define FR_SIZE    32

in_final_syllable:
    push rbx
    push r12
    push r13
    push r14
    push rbp
    sub rsp, FR_SIZE
    mov [rsp + FR_START], edi
    mov [rsp + FR_END], esi
    ; a virama that ligated and multiplied is a halant again
    mov r13d, [r15 + S_IVIRAMA]
    cmp r13d, -1
    je .base
    test r13d, r13d
    jz .base
    mov ebx, edi
.vir:
    cmp ebx, [rsp + FR_END]
    jae .base
    REC rax, rbx
    cmp [rax + GI_GLYPH], r13d
    jne .vir_next
    movzx ecx, word [rax + GI_PROPS]
    and ecx, GP_LIGATED | GP_MULTIPLIED
    cmp ecx, GP_LIGATED | GP_MULTIPLIED
    jne .vir_next
    mov byte [rax + GI_CAT], H
    and word [rax + GI_PROPS], ~(GP_LIGATED | GP_MULTIPLIED)
.vir_next:
    inc ebx
    jmp .vir
.base:
    xor eax, eax
    cmp dword [r15 + S_IMASK + IM_PREF * 4], 0
    setne al
    mov [rsp + FR_PREF], eax
    mov ebx, [rsp + FR_START]           ; base
.b:
    cmp ebx, [rsp + FR_END]
    jae .b_done
    REC rax, rbx
    cmp byte [rax + GI_POS], BASE_C
    jae .b_found
    inc ebx
    jmp .b
.b_found:
    cmp dword [rsp + FR_PREF], 0
    je .b_back
    lea eax, [rbx + 1]
    cmp eax, [rsp + FR_END]
    jae .b_back
    lea r12d, [rbx + 1]
.b_pref:
    cmp r12d, [rsp + FR_END]
    jae .b_pref_end
    REC rax, r12
    mov ecx, [rax + GI_MASK]
    test ecx, [r15 + S_IMASK + IM_PREF * 4]
    jz .b_pref_next
    ; unless it substituted into a ligature
    movzx ecx, word [rax + GI_PROPS]
    test ecx, GP_SUBSTITUTED
    jz .b_take
    and ecx, GP_LIGATED | GP_MULTIPLIED
    cmp ecx, GP_LIGATED
    je .b_pref_end
.b_take:
    mov ebx, r12d
.b_halants:
    cmp ebx, [rsp + FR_END]
    jae .b_taken
    REC rdi, rbx
    mov esi, 1 << H
    call in_is
    test eax, eax
    jz .b_taken
    inc ebx
    jmp .b_halants
.b_taken:
    cmp ebx, [rsp + FR_END]
    jae .b_nopos
    REC rax, rbx
    mov byte [rax + GI_POS], BASE_C
.b_nopos:
    mov dword [rsp + FR_PREF], 0
    jmp .b_pref_end
.b_pref_next:
    inc r12d
    jmp .b_pref
.b_pref_end:
    cmp ebx, [rsp + FR_END]
    je .b_done
.b_back:
    ; Malayalam: a below-base consonant after halants is the base
    cmp byte [r15 + S_IKIND], KIND_MLYM
    jne .b_back2
    lea r12d, [rbx + 1]
.ml:
    cmp r12d, [rsp + FR_END]
    jae .b_back2
.ml_j1:
    cmp r12d, [rsp + FR_END]
    jae .b_back2
    REC rdi, r12
    mov esi, JOINER_FLAGS
    call in_is
    test eax, eax
    jz .ml_h
    inc r12d
    jmp .ml_j1
.ml_h:
    REC rdi, r12
    mov esi, 1 << H
    call in_is
    test eax, eax
    jz .b_back2
    inc r12d
.ml_j2:
    cmp r12d, [rsp + FR_END]
    jae .ml_next
    REC rdi, r12
    mov esi, JOINER_FLAGS
    call in_is
    test eax, eax
    jz .ml_c
    inc r12d
    jmp .ml_j2
.ml_c:
    REC rdi, r12
    mov esi, CONSONANT_FLAGS
    call in_is
    test eax, eax
    jz .ml_next
    REC rax, r12
    cmp byte [rax + GI_POS], BELOW_C
    jne .ml_next
    mov ebx, r12d
    mov byte [rax + GI_POS], BASE_C
.ml_next:
    inc r12d
    jmp .ml
.b_back2:
    cmp ebx, [rsp + FR_START]
    jbe .b_done
    REC rax, rbx
    cmp byte [rax + GI_POS], BASE_C
    jbe .b_done
    dec ebx
.b_done:
    ; no base: a final ZWJ may stand for it
    cmp ebx, [rsp + FR_END]
    jne .b_nh
    cmp ebx, [rsp + FR_START]
    jbe .b_nh
    lea eax, [rbx - 1]
    REC rdi, rax
    mov esi, 1 << ZWJ
    call in_is
    test eax, eax
    jz .b_nh
    dec ebx
.b_nh:
    cmp ebx, [rsp + FR_END]
    jae .b_set
.b_nh_loop:
    cmp ebx, [rsp + FR_START]
    jbe .b_set
    REC rdi, rbx
    mov esi, (1 << N) | (1 << H)
    call in_is
    test eax, eax
    jz .b_set
    dec ebx
    jmp .b_nh_loop
.b_set:
    mov [rsp + FR_BASE], ebx
    ; a pre-base matra goes before the base, after a halant left of it
    mov eax, [rsp + FR_START]
    inc eax
    cmp eax, [rsp + FR_END]
    jae .reph
    mov eax, [rsp + FR_START]
    cmp eax, [rsp + FR_BASE]
    jae .reph
    mov r12d, [rsp + FR_BASE]
    dec r12d                            ; new pos
    mov eax, [rsp + FR_BASE]
    cmp eax, [rsp + FR_END]
    jne .search_kind
    dec r12d
.search_kind:
    cmp byte [r15 + S_IKIND], KIND_MLYM
    je .s_done
    cmp byte [r15 + S_IKIND], KIND_TAML
    je .s_done
.search:
    cmp r12d, [rsp + FR_START]
    jbe .s_have
    REC rdi, r12
    mov esi, MATRA_FLAGS | (1 << H)
    call in_is
    test eax, eax
    jnz .s_have
    dec r12d
    jmp .search
.s_have:
    REC rdi, r12
    mov esi, 1 << H
    call in_is
    test eax, eax
    jz .s_none
    REC rax, r12
    cmp byte [rax + GI_POS], PRE_M
    je .s_none
    lea eax, [r12 + 1]
    cmp eax, [rsp + FR_END]
    jae .s_done
    REC rax, r12
    cmp byte [rax + 32 + GI_CAT], ZWJ
    jne .s_done
    cmp r12d, [rsp + FR_START]
    jbe .s_done
    dec r12d
    jmp .search
.s_none:
    mov r12d, [rsp + FR_START]
.s_done:
    cmp r12d, [rsp + FR_START]
    jbe .pm_merge_only
    REC rax, r12
    cmp byte [rax + GI_POS], PRE_M
    je .pm_merge_only
    mov ebx, r12d                       ; i
.pm:
    cmp ebx, [rsp + FR_START]
    jbe .reph
    REC rax, rbx
    cmp byte [rax - 32 + GI_POS], PRE_M
    jne .pm_next
    lea r13d, [rbx - 1]                 ; old pos
    mov eax, [rsp + FR_BASE]
    cmp r13d, eax
    jae .pm_move
    cmp eax, r12d
    ja .pm_move
    dec dword [rsp + FR_BASE]
.pm_move:
    mov esi, r13d
    mov edx, r12d
    call ufl_buf_move_record
    mov esi, r12d
    mov edx, [rsp + FR_BASE]
    inc edx
    cmp edx, [rsp + FR_END]
    jbe .pm_m
    mov edx, [rsp + FR_END]
.pm_m:
    call ufl_buf_merge_clusters
    dec r12d
.pm_next:
    dec ebx
    jmp .pm
.pm_merge_only:
    mov ebx, [rsp + FR_START]
.pmo:
    cmp ebx, [rsp + FR_BASE]
    jae .reph
    REC rax, rbx
    cmp byte [rax + GI_POS], PRE_M
    jne .pmo_next
    mov esi, ebx
    mov edx, [rsp + FR_BASE]
    inc edx
    cmp edx, [rsp + FR_END]
    jbe .pmo_m
    mov edx, [rsp + FR_END]
.pmo_m:
    call ufl_buf_merge_clusters
    jmp .reph
.pmo_next:
    inc ebx
    jmp .pmo
.reph:
    ; reph moves after the first halant before the base, else to the end
    ; (before syllable modifiers)
    mov eax, [rsp + FR_START]
    inc eax
    cmp eax, [rsp + FR_END]
    jae .pref
    RECM rbx, [rsp + FR_START]
    cmp byte [rbx + GI_POS], RA_TO_BECOME_REPH
    jne .pref
    xor eax, eax
    cmp byte [rbx + GI_CAT], REPHA
    sete al
    movzx ecx, word [rbx + GI_PROPS]
    and ecx, GP_LIGATED | GP_MULTIPLIED
    xor edx, edx
    cmp ecx, GP_LIGATED
    sete dl
    xor eax, edx
    jz .pref
    ; after a halant before the base (steps 2 and 5)
    mov r12d, [rsp + FR_START]
    inc r12d
.rh:
    cmp r12d, [rsp + FR_BASE]
    jae .rh_end
    REC rdi, r12
    mov esi, 1 << H
    call in_is
    test eax, eax
    jnz .rh_found
    inc r12d
    jmp .rh
.rh_found:
    lea eax, [r12 + 1]
    cmp eax, [rsp + FR_BASE]
    jae .reph_move
    REC rdi, rax
    mov esi, JOINER_FLAGS
    call in_is
    test eax, eax
    jz .reph_move
    inc r12d
    jmp .reph_move
.rh_end:
    ; after the main consonant (step 3), after the subjoined ones (step 4)
    movzx eax, byte [r15 + S_IREPHPOS]
    cmp eax, AFTER_MAIN
    je .after_main
    cmp eax, AFTER_SUB
    je .after_sub
    jmp .reph_end
.after_main:
    mov r12d, [rsp + FR_BASE]
.am:
    lea eax, [r12 + 1]
    cmp eax, [rsp + FR_END]
    jae .am_done
    REC rcx, rax
    cmp byte [rcx + GI_POS], AFTER_MAIN
    ja .am_done
    inc r12d
    jmp .am
.am_done:
    cmp r12d, [rsp + FR_END]
    jb .reph_move
    jmp .reph_end
.after_sub:
    mov r12d, [rsp + FR_BASE]
.as:
    lea eax, [r12 + 1]
    cmp eax, [rsp + FR_END]
    jae .as_done
    REC rcx, rax
    movzx ecx, byte [rcx + GI_POS]
    cmp ecx, POST_C
    je .as_done
    cmp ecx, AFTER_POST
    je .as_done
    cmp ecx, SMVD
    je .as_done
    inc r12d
    jmp .as
.as_done:
    cmp r12d, [rsp + FR_END]
    jb .reph_move
.reph_end:
    ; at the end, before syllable modifiers and Vedic signs (step 6)
    mov r12d, [rsp + FR_END]
    dec r12d
.rs:
    cmp r12d, [rsp + FR_START]
    jbe .rs_done
    REC rax, r12
    cmp byte [rax + GI_POS], SMVD
    jne .rs_done
    dec r12d
    jmp .rs
.rs_done:
    REC rdi, r12
    mov esi, 1 << H
    call in_is
    test eax, eax
    jz .reph_move
    ; a halant last: before the matras after the base
    mov ebx, [rsp + FR_BASE]
    inc ebx
.rm:
    cmp ebx, r12d
    jae .reph_move
    REC rdi, rbx
    call in_flag
    test eax, MATRA_FLAGS
    jz .rm_next
    dec r12d
.rm_next:
    inc ebx
    jmp .rm
.reph_move:
    mov esi, [rsp + FR_START]
    lea edx, [r12 + 1]
    call ufl_buf_merge_clusters
    mov esi, [rsp + FR_START]
    mov edx, r12d
    call ufl_buf_move_record
    mov eax, [rsp + FR_BASE]
    cmp [rsp + FR_START], eax
    jae .pref
    cmp eax, r12d
    ja .pref
    dec dword [rsp + FR_BASE]
.pref:
    ; a pre-base reordering consonant that ligated goes before the base
    cmp dword [rsp + FR_PREF], 0
    je .init
    mov eax, [rsp + FR_BASE]
    inc eax
    cmp eax, [rsp + FR_END]
    jae .init
    mov ebx, eax
.pf:
    cmp ebx, [rsp + FR_END]
    jae .init
    REC rax, rbx
    mov ecx, [rax + GI_MASK]
    test ecx, [r15 + S_IMASK + IM_PREF * 4]
    jnz .pf_found
    inc ebx
    jmp .pf
.pf_found:
    movzx ecx, word [rax + GI_PROPS]
    and ecx, GP_LIGATED | GP_MULTIPLIED
    cmp ecx, GP_LIGATED
    jne .init
    mov r12d, [rsp + FR_BASE]           ; new pos
    cmp byte [r15 + S_IKIND], KIND_MLYM
    je .pf_halant
    cmp byte [r15 + S_IKIND], KIND_TAML
    je .pf_halant
.pf_back:
    cmp r12d, [rsp + FR_START]
    jbe .pf_halant
    lea eax, [r12 - 1]
    REC rdi, rax
    mov esi, MATRA_FLAGS | (1 << H)
    call in_is
    test eax, eax
    jnz .pf_halant
    dec r12d
    jmp .pf_back
.pf_halant:
    cmp r12d, [rsp + FR_START]
    jbe .pf_move
    lea eax, [r12 - 1]
    REC rdi, rax
    mov esi, 1 << H
    call in_is
    test eax, eax
    jz .pf_move
    cmp r12d, [rsp + FR_END]
    jae .pf_move
    REC rdi, r12
    mov esi, JOINER_FLAGS
    call in_is
    test eax, eax
    jz .pf_move
    inc r12d
.pf_move:
    mov esi, r12d
    lea edx, [rbx + 1]
    call ufl_buf_merge_clusters
    mov esi, ebx
    mov edx, r12d
    call ufl_buf_move_record
    mov eax, [rsp + FR_BASE]
    cmp r12d, eax
    ja .init
    cmp eax, ebx
    jae .init
    inc dword [rsp + FR_BASE]
.init:
    ; a pre-base matra at the start of a word takes init
    RECM rax, [rsp + FR_START]
    cmp byte [rax + GI_POS], PRE_M
    jne .out
    mov ecx, [rsp + FR_START]
    test ecx, ecx
    jz .init_set
    movzx ecx, byte [rax - 32 + GI_GC]
    cmp ecx, GC_CF
    jb .init_set
    cmp ecx, GC_MN
    jbe .out
.init_set:
    mov ecx, [r15 + S_IMASK + IM_INIT * 4]
    or [rax + GI_MASK], ecx
.out:
    add rsp, FR_SIZE
    pop rbp
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
