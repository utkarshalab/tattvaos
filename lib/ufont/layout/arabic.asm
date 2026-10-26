; =============================================================================
; Utkarsha OS — lib/ufont/layout/arabic.asm
; =============================================================================
; The Arabic and Hebrew shapers, as HarfBuzz's (tools/arabic.py models them).
;
; Arabic (and Syriac):
;   ufl_arabic_collect_features   stch, ccmp / locl, isol fina fin2 fin3 medi
;                                 med2 init a stage each, rlig, calt, liga,
;                                 clig, mset - ZWJ not skipped (it breaks
;                                 joining and ligatures in Arabic)
;   ufl_arabic_data_create        the form masks; for a font without the
;                                 Arabic form features (Arabic script), the
;                                 fallback lookups: single substitutions to
;                                 the initial, medial, final and isolated
;                                 presentation forms the font maps, and
;                                 lam-alef and other ligatures of them
;                                 (three letters, two, shadda with a haraka)
;   ufl_arabic_fallback_shape     the pause after rlig: those lookups, each
;                                 with its feature's mask
;   ufl_arabic_setup_masks        joining: each character's joining type
;                                 (Unicode's, transparent marks skipped) runs
;                                 the state machine that picks its form
;   ufl_arabic_reorder_marks(esi = start, edx = end)
;                                 modifier combining marks (TR53) before the
;                                 other marks of their class
; Not done: the stch stretching feature.
;
; Hebrew:
;   ufl_hebrew_data_create        does the plan position marks
;   ufl_hebrew_compose(edi = a, esi = b) -> eax = ab (0 none): canonical, else
;                                 for fonts without mark positioning the
;                                 presentation forms
;   ufl_hebrew_reorder_marks(esi, edx)  patah / qamats, sheva / hiriq, then
;                                 meteg or a below mark: the last two swap
; =============================================================================

%include "ufont.inc"
%include "shape.inc"

extern ufl_map_add_feature
extern ufl_map_enable
extern ufl_map_add_gsub_pause
extern ufl_map_get_1_mask
extern ufl_ucd_scripts
extern ufl_ucd_joining
extern ufl_ucd_joining_count
extern ufl_uc_compose
extern ufl_buf_merge_clusters
extern ufl_map_feature
extern ufl_norm_glyph
extern ufl_ap_apply_lookup
extern ufl_ucd_arforms
extern ufl_ucd_arforms_first
extern ufl_ucd_arforms_last
extern ufl_ucd_arlig3
extern ufl_ucd_arlig2
extern ufl_ucd_arligm
extern arena_alloc

; the fallback lookups' block: dd count, dd bytes used, then (dd mask, dd
; offset) per lookup, the lookups from AFB_LOOKUPS; scratch after AFB_SIZE
%define AFB_COUNT       0
%define AFB_USED        4
%define AFB_ENTRIES     8
%define AFB_LOOKUPS     64
%define AFB_SIZE        8192
%define AFB_KEYS        0               ; scratch: u32 sort keys
%define AFB_VALS        1024            ; u16 substitutes / u64 ligature records
%define AFB_COV         2048            ; u16 coverage glyphs
%define AFB_SCRATCH     4096

%define JT_U 0
%define JT_T 7
%define NONE 7

section .rodata
ar_features: dd 'isol', 'fina', 'fin2', 'fin3', 'medi', 'med2', 'init'
; (prev action, current action, next state) per state x joining type (6)
ar_states:
    db 7,7,0, 7,0,2, 7,0,1, 7,0,2, 7,0,1, 7,0,6
    db 7,7,0, 7,0,2, 7,0,1, 7,0,2, 7,2,5, 7,0,6
    db 7,7,0, 7,0,2, 6,1,1, 6,1,3, 6,1,4, 6,1,6
    db 7,7,0, 7,0,2, 4,1,1, 4,1,3, 4,1,4, 4,1,6
    db 7,7,0, 7,0,2, 5,0,1, 5,0,2, 5,2,5, 5,0,6
    db 7,7,0, 7,0,2, 0,0,1, 0,0,2, 0,2,5, 0,0,6
    db 7,7,0, 7,0,2, 7,0,1, 7,0,2, 7,3,5, 7,0,6
ar_mcm: dw 0x0654, 0x0655, 0x0658, 0x06DC, 0x06E3, 0x06E7, 0x06E8, 0x08CA, 0x08CB, 0x08CD, 0x08CE, 0x08CF
        dw 0x08D3, 0x08F3, 0
he_dagesh:
    dw 0xFB30, 0xFB31, 0xFB32, 0xFB33, 0xFB34, 0xFB35, 0xFB36, 0, 0xFB38, 0xFB39, 0xFB3A, 0xFB3B, 0xFB3C, 0
    dw 0xFB3E, 0, 0xFB40, 0xFB41, 0, 0xFB43, 0xFB44, 0, 0xFB46, 0xFB47, 0xFB48, 0xFB49, 0xFB4A
; b, a, ab: the other presentation forms
he_forms:
    dw 0x05B4, 0x05D9, 0xFB1D,  0x05B7, 0x05F2, 0xFB1F,  0x05B7, 0x05D0, 0xFB2E,  0x05B8, 0x05D0, 0xFB2F
    dw 0x05B9, 0x05D5, 0xFB4B,  0x05BC, 0xFB2A, 0xFB2C,  0x05BC, 0xFB2B, 0xFB2D,  0x05BF, 0x05D1, 0xFB4C
    dw 0x05BF, 0x05DB, 0xFB4D,  0x05BF, 0x05E4, 0xFB4E,  0x05C1, 0x05E9, 0xFB2A,  0x05C1, 0xFB49, 0xFB2C
    dw 0x05C2, 0x05E9, 0xFB2B,  0x05C2, 0xFB49, 0xFB2D,  0

section .text

; the script is Arabic -> ZF
ar_is_arab:
    mov eax, [r15 + S_SCRIPT]
    imul eax, eax, 12
    lea rcx, [rel ufl_ucd_scripts]
    cmp dword [rcx + rax], 'Arab'
    ret

; ----------------------------------------------------------------------------
; ufl_arabic_collect_features
; ----------------------------------------------------------------------------
global ufl_arabic_collect_features
ufl_arabic_collect_features:
    push rbx
    push r12
    sub rsp, 8
    mov edi, 'stch'
    xor esi, esi
    mov edx, 1
    call ufl_map_enable
    xor edi, edi
    call ufl_map_add_gsub_pause
    mov edi, 'ccmp'
    mov esi, F_MANUAL_ZWJ
    mov edx, 1
    call ufl_map_enable
    mov edi, 'locl'
    mov esi, F_MANUAL_ZWJ
    mov edx, 1
    call ufl_map_enable
    xor edi, edi
    call ufl_map_add_gsub_pause
    lea rbx, [rel ar_features]
    xor r12d, r12d
.form:
    mov edi, [rbx + r12 * 4]
    mov esi, F_MANUAL_ZWJ
    ; Arabic's own forms have a fallback (Syriac's fin2 / fin3 / med2 not)
    mov eax, edi
    shr eax, 24
    cmp eax, '2'
    je .forms_flags
    cmp eax, '3'
    je .forms_flags
    push rdi
    push rsi
    call ar_is_arab
    pop rsi
    pop rdi
    jne .forms_flags
    or esi, F_HAS_FALLBACK
.forms_flags:
    mov edx, 1
    call ufl_map_add_feature
    xor edi, edi
    call ufl_map_add_gsub_pause
    inc r12d
    cmp r12d, 7
    jb .form
    xor edi, edi
    call ufl_map_add_gsub_pause
    mov edi, 'rlig'
    mov esi, F_MANUAL_ZWJ | F_HAS_FALLBACK
    mov edx, 1
    call ufl_map_enable
    call ar_is_arab
    jne .calt
    lea rdi, [rel ufl_arabic_fallback_shape]
    call ufl_map_add_gsub_pause
.calt:
    mov edi, 'calt'
    mov esi, F_MANUAL_ZWJ
    mov edx, 1
    call ufl_map_enable
    ; a pause unless rclt is already in the plan
    mov rcx, [r15 + S_FI]
    mov edx, [r15 + S_NFI]
.rclt:
    test edx, edx
    jz .rclt_pause
    cmp dword [rcx + FI_TAG], 'rclt'
    je .liga
    add rcx, FI_SIZE
    dec edx
    jmp .rclt
.rclt_pause:
    xor edi, edi
    call ufl_map_add_gsub_pause
.liga:
    mov edi, 'liga'
    mov esi, F_MANUAL_ZWJ
    mov edx, 1
    call ufl_map_enable
    mov edi, 'clig'
    mov esi, F_MANUAL_ZWJ
    mov edx, 1
    call ufl_map_enable
    mov edi, 'mset'
    mov esi, F_MANUAL_ZWJ
    mov edx, 1
    call ufl_map_enable
    add rsp, 8
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------------
; ufl_arabic_data_create
; ----------------------------------------------------------------------------
global ufl_arabic_data_create
ufl_arabic_data_create:
    push rbx
    push r12
    sub rsp, 8
    lea rbx, [rel ar_features]
    xor r12d, r12d
.mask:
    mov edi, [rbx + r12 * 4]
    call ufl_map_get_1_mask
    mov [r15 + S_AMASK + r12 * 4], eax
    inc r12d
    cmp r12d, 7
    jb .mask
    mov dword [r15 + S_AMASK + 7 * 4], 0
    ; the fallback: Arabic, and every Arabic form feature (not Syriac's) in
    ; the plan without a lookup in the font
    mov qword [r15 + S_AFB], 0
    call ar_is_arab
    jne .out
    xor r12d, r12d
.needs:
    mov edi, [rbx + r12 * 4]
    mov eax, edi
    shr eax, 24
    cmp eax, '2'
    je .needs_next
    cmp eax, '3'
    je .needs_next
    call ufl_map_feature
    test rax, rax
    jz .out
    cmp dword [rax + FM_INDEX], -1
    jne .out
    cmp dword [rax + FM_INDEX + 4], -1
    jne .out
.needs_next:
    inc r12d
    cmp r12d, 7
    jb .needs
    call ar_fb_build
.out:
    add rsp, 8
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------------
; ar_fb_build: the fallback lookups (S_AFB)
; ----------------------------------------------------------------------------
; the forms' masks (S_AMASK index) in the order they apply: init, medi, fina, isol
ar_fb_forms: db 6, 4, 1, 0

ar_fb_build:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    sub rsp, 16
    mov rdi, [r15 + S_ARENA]
    mov esi, AFB_SIZE + AFB_SCRATCH
    call arena_alloc
    test rax, rax
    jz .out
    mov [r15 + S_AFB], rax
    mov rbx, rax
    mov dword [rbx + AFB_COUNT], 0
    lea r13, [rbx + AFB_LOOKUPS]        ; next lookup
    xor r12d, r12d
.single:
    lea rax, [rel ar_fb_forms]
    movzx eax, byte [rax + r12]
    mov ebp, [r15 + S_AMASK + rax * 4]
    test ebp, ebp
    jz .single_next
    mov edi, r12d
    mov rsi, r13
    call ar_fb_single
    call .entry
.single_next:
    inc r12d
    cmp r12d, 4
    jb .single
    mov edi, 'rlig'
    call ufl_map_get_1_mask
    mov ebp, eax
    test ebp, ebp
    jz .done
    lea rdi, [rel ufl_ucd_arlig3]
    mov esi, 8
    mov edx, 2
    mov rcx, r13
    call ar_fb_ligature
    call .entry
    lea rdi, [rel ufl_ucd_arlig2]
    mov esi, 8
    mov edx, 1
    mov rcx, r13
    call ar_fb_ligature
    call .entry
    lea rdi, [rel ufl_ucd_arligm]
    xor esi, esi
    mov edx, 1
    mov rcx, r13
    call ar_fb_ligature
    call .entry
.done:
    mov rax, r13
    sub rax, rbx
    mov [rbx + AFB_USED], eax
.out:
    add rsp, 16
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret
; rax = the lookup's end (r13: none made): listed with mask ebp
.entry:
    cmp rax, r13
    je .entry_out
    mov ecx, [rbx + AFB_COUNT]
    mov [rbx + AFB_ENTRIES + rcx * 8], ebp
    mov rdx, r13
    sub rdx, rbx
    mov [rbx + AFB_ENTRIES + rcx * 8 + 4], edx
    inc dword [rbx + AFB_COUNT]
    mov r13, rax
.entry_out:
    ret

; rdi = the next byte -> a big-endian u16 from eax written, rdi past it
ar_put16:
    xchg al, ah
    mov [rdi], ax
    add rdi, 2
    ret

; sort the u32 keys at rdi (ecx of them) ascending
ar_sort:
    mov r8d, 1
.outer:
    cmp r8d, ecx
    jae .out
    mov eax, [rdi + r8 * 4]
    mov r9d, r8d
.inner:
    test r9d, r9d
    jz .put
    mov edx, [rdi + r9 * 4 - 4]
    cmp edx, eax
    jbe .put
    mov [rdi + r9 * 4], edx
    dec r9d
    jmp .inner
.put:
    mov [rdi + r9 * 4], eax
    inc r8d
    jmp .outer
.out:
    ret

; ----------------------------------------------------------------------------
; ar_fb_single — edi = form (0 initial, 1 medial, 2 final, 3 isolated), rsi =
;   where the lookup goes -> rax = its end (rsi: the font has no such forms)
;   SingleSubst format 2 skipping marks: each letter's glyph to its form's
;   (the first letter wins a glyph two map to)
; ----------------------------------------------------------------------------
ar_fb_single:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    sub rsp, 16
    mov [rsp], rsi
    mov r14d, edi
    mov rbx, [r15 + S_AFB]
    add rbx, AFB_SIZE                   ; scratch
    xor ebp, ebp                        ; pairs
    mov r12d, [rel ufl_ucd_arforms_first]
.letter:
    cmp r12d, [rel ufl_ucd_arforms_last]
    ja .sort
    mov eax, r12d
    sub eax, [rel ufl_ucd_arforms_first]
    lea rcx, [rel ufl_ucd_arforms]
    lea rcx, [rcx + rax * 8]
    movzx r13d, word [rcx + r14 * 2]    ; the form
    test r13d, r13d
    jz .letter_next
    mov edi, r12d
    call ufl_norm_glyph
    test eax, eax
    jz .letter_next
    mov [rsp + 8], eax
    mov edi, r13d
    call ufl_norm_glyph
    test eax, eax
    jz .letter_next
    cmp eax, [rsp + 8]
    je .letter_next
    mov [rbx + AFB_VALS + rbp * 2], ax
    mov ecx, [rsp + 8]
    shl ecx, 16
    or ecx, ebp
    mov [rbx + AFB_KEYS + rbp * 4], ecx
    inc ebp
.letter_next:
    inc r12d
    jmp .letter
.sort:
    mov rax, [rsp]
    test ebp, ebp
    jz .out
    lea rdi, [rbx + AFB_KEYS]
    mov ecx, ebp
    call ar_sort
    ; one entry per glyph: the first
    xor ecx, ecx                        ; read
    xor edx, edx                        ; kept
    mov r8d, -1
.dedupe:
    cmp ecx, ebp
    jae .write
    mov eax, [rbx + AFB_KEYS + rcx * 4]
    mov r9d, eax
    shr r9d, 16
    cmp r9d, r8d
    je .dedupe_next
    mov r8d, r9d
    mov [rbx + AFB_KEYS + rdx * 4], eax
    inc edx
.dedupe_next:
    inc ecx
    jmp .dedupe
.write:
    mov ebp, edx
    mov rdi, [rsp]
    mov eax, 1                          ; Lookup: single, skipping marks, one subtable at 8
    call ar_put16
    mov eax, 8
    call ar_put16
    mov eax, 1
    call ar_put16
    mov eax, 8
    call ar_put16
    mov eax, 2                          ; format 2, the coverage after the substitutes
    call ar_put16
    lea eax, [rbp * 2 + 6]
    call ar_put16
    mov eax, ebp
    call ar_put16
    xor ecx, ecx
.substitutes:
    cmp ecx, ebp
    jae .coverage
    movzx eax, word [rbx + AFB_KEYS + rcx * 4]
    movzx eax, word [rbx + AFB_VALS + rax * 2]
    call ar_put16
    inc ecx
    jmp .substitutes
.coverage:
    mov eax, 1
    call ar_put16
    mov eax, ebp
    call ar_put16
    xor ecx, ecx
.glyphs:
    cmp ecx, ebp
    jae .written
    movzx eax, word [rbx + AFB_KEYS + rcx * 4 + 2]
    call ar_put16
    inc ecx
    jmp .glyphs
.written:
    mov rax, rdi
.out:
    add rsp, 16
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; ----------------------------------------------------------------------------
; ar_fb_ligature — rdi = ligature table (ufl_ucd_arlig*), esi = lookup flag,
;   edx = components after the first, rcx = where the lookup goes -> rax =
;   its end (rcx: none of them in the font)
;   LigatureSubst format 1: the ligature sets by the first glyph, each in the
;   table's order, those the font has every glyph of
; ----------------------------------------------------------------------------
%define FL_OUT      0
%define FL_FLAG     8
%define FL_NCOMP    12
%define FL_SUB      16                  ; the subtable
%define FL_SET      24                  ; the set being written
%define FL_N        32                  ; first glyphs found
%define FL_NSETS    36
%define FL_LIG      40                  ; the ligature being written
%define FL_K        48                  ; ligatures in the set
%define FL_G        52                  ; the set's glyph
%define FL_SIZE     64

ar_fb_ligature:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    sub rsp, FL_SIZE
    mov [rsp + FL_OUT], rcx
    mov [rsp + FL_FLAG], esi
    mov [rsp + FL_NCOMP], edx
    mov rbx, [r15 + S_AFB]
    add rbx, AFB_SIZE
    ; the records with a first glyph: keys glyph << 16 | record
    mov r12, rdi
    xor r13d, r13d                      ; records
    xor ebp, ebp                        ; keys
.record:
    movzx eax, word [r12]
    test eax, eax
    jz .sort
    mov [rbx + AFB_VALS + r13 * 8], r12
    mov edi, eax
    call ufl_norm_glyph
    test eax, eax
    jz .record_next
    shl eax, 16
    or eax, r13d
    mov [rbx + AFB_KEYS + rbp * 4], eax
    inc ebp
.record_next:
    movzx eax, word [r12 + 2]
    mov ecx, [rsp + FL_NCOMP]
    inc ecx
    imul eax, ecx
    lea r12, [r12 + rax * 2 + 4]
    inc r13d
    jmp .record
.sort:
    mov rax, [rsp + FL_OUT]
    test ebp, ebp
    jz .out
    mov [rsp + FL_N], ebp
    lea rdi, [rbx + AFB_KEYS]
    mov ecx, ebp
    call ar_sort
    ; room for a set offset per first glyph, the sets after
    mov rax, [rsp + FL_OUT]
    lea rcx, [rax + 8]
    mov [rsp + FL_SUB], rcx
    mov ecx, ebp
    lea r14, [rax + rcx * 2 + 8 + 6]    ; next byte
    mov dword [rsp + FL_NSETS], 0
    xor r12d, r12d                      ; key
.set:
    cmp r12d, [rsp + FL_N]
    jae .coverage
    mov eax, [rbx + AFB_KEYS + r12 * 4]
    shr eax, 16
    mov [rsp + FL_G], eax
    ; ligatures it could hold: the records of the glyph
    xor ecx, ecx
    mov edx, r12d
.count:
    cmp edx, [rsp + FL_N]
    jae .counted
    mov eax, [rbx + AFB_KEYS + rdx * 4]
    shr eax, 16
    cmp eax, [rsp + FL_G]
    jne .counted
    movzx eax, word [rbx + AFB_KEYS + rdx * 4]
    mov rax, [rbx + AFB_VALS + rax * 8]
    movzx eax, word [rax + 2]
    add ecx, eax
    inc edx
    jmp .count
.counted:
    mov [rsp + FL_SET], r14
    lea r14, [r14 + rcx * 2 + 2]
    mov dword [rsp + FL_K], 0
.set_record:
    cmp r12d, [rsp + FL_N]
    jae .set_done
    mov eax, [rbx + AFB_KEYS + r12 * 4]
    shr eax, 16
    cmp eax, [rsp + FL_G]
    jne .set_done
    movzx eax, word [rbx + AFB_KEYS + r12 * 4]
    mov r13, [rbx + AFB_VALS + rax * 8]
    movzx ebp, word [r13 + 2]           ; entries
    add r13, 4
.entry:
    test ebp, ebp
    jz .set_record_next
    dec ebp
    ; the ligature glyph and every component's, else skipped
    mov [rsp + FL_LIG], r14
    mov ecx, [rsp + FL_NCOMP]
    movzx edi, word [r13 + rcx * 2]
    call ufl_norm_glyph
    test eax, eax
    jz .entry_skip
    mov rdi, r14
    call ar_put16
    mov eax, [rsp + FL_NCOMP]
    inc eax
    call ar_put16
    mov r14, rdi
    xor ecx, ecx
.component:
    cmp ecx, [rsp + FL_NCOMP]
    jae .entry_made
    movzx edi, word [r13 + rcx * 2]
    test edi, edi
    jz .entry_drop
    push rcx
    sub rsp, 8
    call ufl_norm_glyph
    add rsp, 8
    pop rcx
    test eax, eax
    jz .entry_drop
    mov rdi, r14
    call ar_put16
    mov r14, rdi
    inc ecx
    jmp .component
.entry_made:
    ; its offset in the set
    mov rdi, [rsp + FL_SET]
    mov eax, [rsp + FL_K]
    lea rdi, [rdi + rax * 2 + 2]
    mov rax, [rsp + FL_LIG]
    sub rax, [rsp + FL_SET]
    call ar_put16
    inc dword [rsp + FL_K]
    jmp .entry_skip
.entry_drop:
    mov r14, [rsp + FL_LIG]
.entry_skip:
    mov ecx, [rsp + FL_NCOMP]
    lea r13, [r13 + rcx * 2 + 2]
    jmp .entry
.set_record_next:
    inc r12d
    jmp .set_record
.set_done:
    cmp dword [rsp + FL_K], 0
    jne .set_made
    mov r14, [rsp + FL_SET]             ; nothing in it: dropped
    jmp .set
.set_made:
    mov rdi, [rsp + FL_SET]
    mov eax, [rsp + FL_K]
    call ar_put16
    mov ecx, [rsp + FL_NSETS]
    mov rdi, [rsp + FL_SUB]
    lea rdi, [rdi + rcx * 2 + 6]
    mov rax, [rsp + FL_SET]
    sub rax, [rsp + FL_SUB]
    call ar_put16
    mov eax, [rsp + FL_G]
    mov [rbx + AFB_COV + rcx * 2], ax
    inc dword [rsp + FL_NSETS]
    jmp .set
.coverage:
    mov rax, [rsp + FL_OUT]
    mov ecx, [rsp + FL_NSETS]
    test ecx, ecx
    jz .out
    mov rdi, rax                        ; Lookup: ligature, the flag, one subtable at 8
    mov eax, 4
    call ar_put16
    mov eax, [rsp + FL_FLAG]
    call ar_put16
    mov eax, 1
    call ar_put16
    mov eax, 8
    call ar_put16
    mov eax, 1                          ; format 1, the coverage after the sets
    call ar_put16
    mov rax, r14
    sub rax, [rsp + FL_SUB]
    call ar_put16
    mov eax, [rsp + FL_NSETS]
    call ar_put16
    mov rdi, r14
    mov eax, 1
    call ar_put16
    mov eax, [rsp + FL_NSETS]
    call ar_put16
    xor ecx, ecx
.cov_glyphs:
    cmp ecx, [rsp + FL_NSETS]
    jae .written
    movzx eax, word [rbx + AFB_COV + rcx * 2]
    call ar_put16
    inc ecx
    jmp .cov_glyphs
.written:
    mov rax, rdi
.out:
    add rsp, FL_SIZE
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; ----------------------------------------------------------------------------
; ufl_arabic_fallback_shape: the fallback lookups over the run (a GSUB pause)
; ----------------------------------------------------------------------------
global ufl_arabic_fallback_shape
ufl_arabic_fallback_shape:
    push rbx
    push rbp
    push r12
    sub rsp, 16
    mov rbx, [r15 + S_AFB]
    test rbx, rbx
    jz .out
    mov rax, [r15 + S_TABLE]
    mov [rsp], rax
    mov rax, [r15 + S_TEND]
    mov [rsp + 8], rax
    mov [r15 + S_TABLE], rbx
    mov eax, [rbx + AFB_USED]
    add rax, rbx
    mov [r15 + S_TEND], rax
    xor ebp, ebp
.lookup:
    cmp ebp, [rbx + AFB_COUNT]
    jae .restore
    mov esi, [rbx + AFB_ENTRIES + rbp * 8]
    mov edi, [rbx + AFB_ENTRIES + rbp * 8 + 4]
    add rdi, rbx
    call ufl_ap_apply_lookup
    inc ebp
    jmp .lookup
.restore:
    mov rax, [rsp]
    mov [r15 + S_TABLE], rax
    mov rax, [rsp + 8]
    mov [r15 + S_TEND], rax
.out:
    add rsp, 16
    pop r12
    pop rbp
    pop rbx
    ret

; edi = code point, esi = general category -> eax = joining type
ar_joining_type:
    lea r8, [rel ufl_ucd_joining]
    xor r9d, r9d
    mov r10d, [rel ufl_ucd_joining_count]
.search:
    cmp r9d, r10d
    jae .derived
    lea r11d, [r9 + r10]
    shr r11d, 1
    mov eax, [r8 + r11 * 4]
    mov ecx, eax
    and ecx, 0xFFFFFF
    cmp edi, ecx
    je .found
    jb .lo
    lea r9d, [r11 + 1]
    jmp .search
.lo:
    mov r10d, r11d
    jmp .search
.found:
    shr eax, 24
    ret
.derived:
    mov eax, JT_T
    cmp esi, GC_MN
    je .out
    cmp esi, GC_ME
    je .out
    cmp esi, GC_CF
    je .out
    mov eax, JT_U
.out:
    ret

; ----------------------------------------------------------------------------
; ufl_arabic_setup_masks: joining
; ----------------------------------------------------------------------------
global ufl_arabic_setup_masks
ufl_arabic_setup_masks:
    push rbx
    push r12
    push r13
    push r14
    push rbp
    mov r12d, -1                        ; prev
    xor r13d, r13d                      ; state
    xor ebx, ebx
.char:
    cmp ebx, [r15 + S_LEN]
    jae .masks
    mov rbp, rbx
    shl rbp, 5
    add rbp, [r15 + S_INFO]
    mov edi, [rbp + GI_CP]
    movzx esi, byte [rbp + GI_GC]
    call ar_joining_type
    cmp eax, JT_T
    jne .joins
    mov byte [rbp + GI_CAT], NONE       ; the action, kept in the Indic slot
    jmp .next
.joins:
    imul ecx, r13d, 18
    lea ecx, [rcx + rax * 2]
    add ecx, eax                        ; state * 18 + type * 3
    lea rdx, [rel ar_states]
    movzx r8d, byte [rdx + rcx]         ; prev action
    movzx r9d, byte [rdx + rcx + 1]     ; current action
    movzx r13d, byte [rdx + rcx + 2]    ; next state
    cmp r8d, NONE
    je .current
    cmp r12d, -1
    je .current
    mov rax, r12
    shl rax, 5
    add rax, [r15 + S_INFO]
    mov [rax + GI_CAT], r8b
.current:
    mov [rbp + GI_CAT], r9b
    mov r12d, ebx
.next:
    inc ebx
    jmp .char
.masks:
    xor ebx, ebx
.mask:
    cmp ebx, [r15 + S_LEN]
    jae .out
    mov rax, rbx
    shl rax, 5
    add rax, [r15 + S_INFO]
    movzx ecx, byte [rax + GI_CAT]
    mov edx, [r15 + S_AMASK + rcx * 4]
    or [rax + GI_MASK], edx
    mov byte [rax + GI_CAT], 0
    inc ebx
    jmp .mask
.out:
    pop rbp
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; rax = record -> ZF set when it is a modifier combining mark
ar_is_mcm:
    mov ecx, [rax + GI_CP]
    lea rdx, [rel ar_mcm]
.loop:
    movzx r8d, word [rdx]
    test r8d, r8d
    jz .no
    cmp r8d, ecx
    je .out
    add rdx, 2
    jmp .loop
.no:
    or r8d, 1                           ; ZF clear
.out:
    ret

; ----------------------------------------------------------------------------
; ufl_arabic_reorder_marks — esi = start, edx = end
; ----------------------------------------------------------------------------
global ufl_arabic_reorder_marks
ufl_arabic_reorder_marks:
    push rbx
    push r12
    push r13
    push r14
    push rbp
    sub rsp, 32 * 33                    ; the moved marks (at most 32)
    mov r12d, esi                       ; start
    mov r13d, edx                       ; end
    mov ebx, esi                        ; i
    mov ebp, 220                        ; cc
.class:
    cmp ebp, 230
    ja .out
.find:
    cmp ebx, r13d
    jae .out
    mov rax, rbx
    shl rax, 5
    add rax, [r15 + S_INFO]
    movzx ecx, byte [rax + GI_MCC]
    cmp ecx, ebp
    jae .at
    inc ebx
    jmp .find
.at:
    cmp ecx, ebp
    ja .class_next
    mov r14d, ebx                       ; j
.mcm:
    cmp r14d, r13d
    jae .have
    mov rax, r14
    shl rax, 5
    add rax, [r15 + S_INFO]
    movzx ecx, byte [rax + GI_MCC]
    cmp ecx, ebp
    jne .have
    call ar_is_mcm
    jne .have
    inc r14d
    jmp .mcm
.have:
    cmp r14d, ebx
    je .class_next
    mov esi, r12d
    mov edx, r14d
    call ufl_buf_merge_clusters
    ; info[i, j) to the start, info[start, i) after them
    mov rsi, rbx
    shl rsi, 5
    add rsi, [r15 + S_INFO]
    mov rdi, rsp
    mov ecx, r14d
    sub ecx, ebx
    shl ecx, 5
    rep movsb
    mov ecx, ebx
    sub ecx, r12d                       ; i - start records
    mov rsi, rbx
    shl rsi, 5
    add rsi, [r15 + S_INFO]
    mov rdi, r14
    shl rdi, 5
    add rdi, [r15 + S_INFO]
    shl ecx, 5
    sub rsi, 1
    sub rdi, 1
    std
    rep movsb
    cld
    mov rdi, r12
    shl rdi, 5
    add rdi, [r15 + S_INFO]
    mov rsi, rsp
    mov ecx, r14d
    sub ecx, ebx
    shl ecx, 5
    rep movsb
    ; their classes renumbered so the run stays sorted
    mov eax, r14d
    sub eax, ebx
    add eax, r12d                       ; new start
    mov ecx, 25
    cmp ebp, 220
    je .renumber
    mov ecx, 26
.renumber:
    cmp r12d, eax
    jae .renumbered
    mov rdx, r12
    shl rdx, 5
    add rdx, [r15 + S_INFO]
    mov [rdx + GI_MCC], cl
    inc r12d
    jmp .renumber
.renumbered:
    mov ebx, r14d
.class_next:
    add ebp, 10
    jmp .class
.out:
    add rsp, 32 * 33
    pop rbp
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------------
; Hebrew
; ----------------------------------------------------------------------------
global ufl_hebrew_data_create
ufl_hebrew_data_create:
    sub rsp, 8
    mov edi, 'mark'
    call ufl_map_get_1_mask
    test eax, eax
    setnz byte [r15 + S_AMARKPOS]
    add rsp, 8
    ret

global ufl_hebrew_compose
ufl_hebrew_compose:
    push rbx
    push r12
    sub rsp, 8
    mov ebx, edi
    mov r12d, esi
    call ufl_uc_compose
    test eax, eax
    jnz .out
    cmp byte [r15 + S_AMARKPOS], 0
    jne .out
    ; presentation forms
    cmp r12d, 0x05BC
    jne .forms
    mov eax, ebx
    sub eax, 0x05D0
    cmp eax, 0x05EA - 0x05D0
    ja .forms
    lea rcx, [rel he_dagesh]
    movzx eax, word [rcx + rax * 2]
    jmp .out
.forms:
    lea rcx, [rel he_forms]
.form:
    movzx edx, word [rcx]
    test edx, edx
    jz .none
    cmp edx, r12d
    jne .form_next
    movzx edx, word [rcx + 2]
    cmp edx, ebx
    jne .form_next
    movzx eax, word [rcx + 4]
    jmp .out
.form_next:
    add rcx, 6
    jmp .form
.none:
    xor eax, eax
.out:
    add rsp, 8
    pop r12
    pop rbx
    ret

global ufl_hebrew_reorder_marks
ufl_hebrew_reorder_marks:
    push rbx
    push r12
    sub rsp, 8
    mov r12d, edx                       ; end
    lea ebx, [rsi + 2]
.loop:
    cmp ebx, r12d
    jae .out
    mov rax, rbx
    shl rax, 5
    add rax, [r15 + S_INFO]
    movzx ecx, byte [rax - 64 + GI_MCC]
    cmp ecx, 20
    je .c1
    cmp ecx, 21
    jne .next
.c1:
    movzx ecx, byte [rax - 32 + GI_MCC]
    cmp ecx, 22
    je .c2
    cmp ecx, 23
    jne .next
.c2:
    movzx ecx, byte [rax + GI_MCC]
    cmp ecx, 25
    je .swap
    cmp ecx, 220
    jne .next
.swap:
    lea esi, [rbx - 1]
    lea edx, [rbx + 1]
    call ufl_buf_merge_clusters
    mov rax, rbx
    shl rax, 5
    add rax, [r15 + S_INFO]
    movdqu xmm0, [rax - 32]
    movdqu xmm1, [rax - 16]
    movdqu xmm2, [rax]
    movdqu xmm3, [rax + 16]
    movdqu [rax - 32], xmm2
    movdqu [rax - 16], xmm3
    movdqu [rax], xmm0
    movdqu [rax + 16], xmm1
    jmp .out
.next:
    inc ebx
    jmp .loop
.out:
    add rsp, 8
    pop r12
    pop rbx
    ret
