; =============================================================================
; Utkarsha OS — lib/ufont/layout/use.asm
; =============================================================================
; The Universal Shaping Engine, as HarfBuzz's (for the scripts it lists, and
; the Indic scripts in fonts with their xxx3 script):
;
;   ufl_use_collect_features  locl, ccmp, nukt, akhn; rphf (the substitution
;                             flags cleared before it, the substituted repha
;                             recorded as R after it); pref (likewise, recorded
;                             as VPre); rkrf / abvf / blwf / half / pstf / vatu
;                             / cjct; reordering; the syllables cleared; isol /
;                             init / medi / fina; abvs / blws / haln / pres /
;                             psts - the first ones held to the syllable
;   ufl_use_data_create       the rphf and topographical masks (the Arabic form
;                             masks for scripts that join like Arabic)
;   ufl_use_preprocess        vowel constraints: a dotted circle between a
;                             vowel and a sign that would read as another one
;   ufl_use_setup_masks       Arabic joining for the scripts that join like
;                             Arabic; every character's USE category (GI_CAT)
;
; Syllables come from the USE grammar run over the text without its
; CGJ-class characters (and without a ZWNJ a mark follows), each skipped
; character joining the syllable before it. Reordering: dotted circles in
; broken clusters (after their repha), a repha moved before the first
; post-base glyph, pre-base vowels and vowel modifiers moved back after the
; last halant. No short circuit, nothing composed onto a mark; marks zeroed
; before GPOS, no fallback positioning.
; =============================================================================

%include "ufont.inc"
%include "shape.inc"

extern ufl_map_add_feature
extern ufl_map_enable
extern ufl_map_add_gsub_pause
extern ufl_map_get_1_mask
extern ufl_buf_clear_output
extern ufl_buf_sync
extern ufl_buf_next_glyph
extern ufl_buf_out_slot
extern ufl_buf_merge_clusters
extern ufl_syl_dotted_circles
extern ufl_syl_clear
extern ufl_arabic_data_create
extern ufl_arabic_setup_masks
extern ufl_ucd_scripts
extern ufl_use_ranges
extern ufl_use_ranges_count
extern ufl_use_machine
extern ufl_use_vowels

; categories
%define U_B             1
%define U_CGJ           6
%define U_H             12
%define U_ZWNJ          14
%define U_R             18
%define U_VPRE          22
%define U_VMPRE         23
%define U_IS            44
%define U_HVM           53
; post-base categories: F*, FM*, M*, V*, VM*
%define U_POST_BASE     (0x7F << 24) | (0xE << 32) | (0xE << 36) | (0x7 << 45) | (0x3 << 22)
; syllable types
%define U_HIEROGLYPH    6
%define U_BROKEN        7
%define U_NON           8
%define U_REORDERED     0xA7            ; virama / sakot terminated, standard, symbol, broken
; masks (S_UMASK: the Indic slots): rphf, isol, init, medi, fina
%define S_UMASK         S_IMASK
; the machine (layout/syllabic.asm's layout)
%define SM_CLASSES      0
%define SM_DFA          8
%define SM_ACCEPT       16
%define SM_NCLASSES     24

section .rodata
us_basic: dd 'rkrf', 'abvf', 'blwf', 'half', 'pstf', 'vatu', 'cjct'
us_topo: dd 'isol', 'init', 'medi', 'fina'
us_other: dd 'abvs', 'blws', 'haln', 'pres', 'psts'
; the scripts that join like Arabic
us_arabic: dd 'Adlm', 'Arab', 'Chrs', 'Rohg', 'Mand', 'Mani', 'Mong', 'Nkoo', 'Ougr', 'Phag', 'Phlp', 'Sogd'
           dd 'Syrc', 0

section .text

; the record at index %2 -> %1
%macro REC 2
    mov %1, %2
    shl %1, 5
    add %1, [r15 + S_INFO]
%endmacro

; -> eax the run's script tag
us_script:
    mov eax, [r15 + S_SCRIPT]
    imul eax, eax, 12
    lea rcx, [rel ufl_ucd_scripts]
    mov eax, [rcx + rax]
    ret

; -> ZF set when the script joins like Arabic
us_is_arabic:
    call us_script
    lea rcx, [rel us_arabic]
.each:
    cmp dword [rcx], 0
    je .no
    cmp [rcx], eax
    je .out
    add rcx, 4
    jmp .each
.no:
    cmp rcx, 0                          ; rcx is not 0: ZF clear
.out:
    ret

; ----------------------------------------------------------------------------
; the plan
; ----------------------------------------------------------------------------
%macro FEATURE 3                        ; enable / add, tag, flags
    mov edi, %2
    mov esi, %3
    mov edx, 1
    call %1
%endmacro
%macro PAUSE 1
    lea rdi, [rel %1]
    call ufl_map_add_gsub_pause
%endmacro

global ufl_use_collect_features
ufl_use_collect_features:
    push rbx
    PAUSE us_setup_syllables
    FEATURE ufl_map_enable, 'locl', F_PER_SYLLABLE
    FEATURE ufl_map_enable, 'ccmp', F_PER_SYLLABLE
    FEATURE ufl_map_enable, 'nukt', F_PER_SYLLABLE
    FEATURE ufl_map_enable, 'akhn', F_MANUAL_ZWJ | F_PER_SYLLABLE
    PAUSE us_clear_substituted
    FEATURE ufl_map_add_feature, 'rphf', F_MANUAL_ZWJ | F_PER_SYLLABLE
    PAUSE us_record_rphf
    PAUSE us_clear_substituted
    FEATURE ufl_map_enable, 'pref', F_MANUAL_ZWJ | F_PER_SYLLABLE
    PAUSE us_record_pref
    xor ebx, ebx
.basic:
    lea rax, [rel us_basic]
    mov edi, [rax + rbx * 4]
    mov esi, F_MANUAL_ZWJ | F_PER_SYLLABLE
    mov edx, 1
    call ufl_map_enable
    inc ebx
    cmp ebx, 7
    jb .basic
    PAUSE us_reorder
    PAUSE ufl_syl_clear
    xor ebx, ebx
.topo:
    lea rax, [rel us_topo]
    mov edi, [rax + rbx * 4]
    xor esi, esi
    mov edx, 1
    call ufl_map_add_feature
    inc ebx
    cmp ebx, 4
    jb .topo
    xor edi, edi
    call ufl_map_add_gsub_pause
    xor ebx, ebx
.other:
    lea rax, [rel us_other]
    mov edi, [rax + rbx * 4]
    mov esi, F_MANUAL_ZWJ
    mov edx, 1
    call ufl_map_enable
    inc ebx
    cmp ebx, 5
    jb .other
    pop rbx
    ret

global ufl_use_data_create
ufl_use_data_create:
    push rbx
    mov edi, 'rphf'
    call ufl_map_get_1_mask
    mov [r15 + S_UMASK], eax
    ; the topographical masks (none where the feature is global)
    xor ebx, ebx
.topo:
    lea rax, [rel us_topo]
    mov edi, [rax + rbx * 4]
    call ufl_map_get_1_mask
    cmp eax, [r15 + S_GMASK]
    jne .topo_set
    xor eax, eax
.topo_set:
    mov [r15 + S_UMASK + 4 + rbx * 4], eax
    inc ebx
    cmp ebx, 4
    jb .topo
    call us_is_arabic
    jne .out
    call ufl_arabic_data_create
.out:
    pop rbx
    ret

; ----------------------------------------------------------------------------
; ufl_use_preprocess: vowel constraints
; ----------------------------------------------------------------------------
global ufl_use_preprocess
ufl_use_preprocess:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    call us_script
    mov r14d, eax                       ; the script
    lea rbp, [rel ufl_use_vowels]
.script:
    mov eax, [rbp]
    test eax, eax
    jz .out
    cmp eax, r14d
    je .found
    mov eax, [rbp + 4]
    lea rbp, [rbp + 8 + rax * 8]
    jmp .script
.found:
    call ufl_buf_clear_output
    mov dword [r15 + S_IDX], 0
    mov r12d, [r15 + S_LEN]             ; count
.loop:
    mov eax, [r15 + S_IDX]
    inc eax
    cmp eax, r12d
    jae .done
    xor r13d, r13d                      ; matched
    mov eax, [r15 + S_IDX]
    REC rbx, rax
    mov eax, [rbx + GI_CP]
    mov ecx, [rbx + 32 + GI_CP]
    ; Devanagari: RA, VIRAMA, I
    cmp r14d, 'Deva'
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
    lea rdx, [rbp + 8]
    mov r8d, [rbp + 4]
.pair:
    test r8d, r8d
    jz .next
    cmp [rdx], eax
    jne .pair_next
    cmp [rdx + 4], ecx
    je .yes
.pair_next:
    add rdx, 8
    dec r8d
    jmp .pair
.yes:
    mov r13d, 1
.next:
    call ufl_buf_next_glyph
    test r13d, r13d
    jz .loop
    ; a copy of the current character as a dotted circle, then the character
    call ufl_buf_out_slot
    mov eax, [r15 + S_IDX]
    REC rsi, rax
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
.out:
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; ----------------------------------------------------------------------------
; ufl_use_setup_masks: Arabic joining (for its scripts), the categories
; ----------------------------------------------------------------------------
global ufl_use_setup_masks
ufl_use_setup_masks:
    push rbx
    call us_is_arabic
    jne .categories
    call ufl_arabic_setup_masks
.categories:
    xor ebx, ebx
.each:
    cmp ebx, [r15 + S_LEN]
    jae .done
    REC rdi, rbx
    mov esi, [rdi + GI_CP]
    ; binary search the ranges
    lea r8, [rel ufl_use_ranges]
    xor r9d, r9d
    mov r10d, [rel ufl_use_ranges_count]
    xor eax, eax
.search:
    cmp r9d, r10d
    jae .set
    lea r11d, [r9 + r10]
    shr r11d, 1
    imul edx, r11d, 12
    cmp esi, [r8 + rdx]
    jb .lo
    cmp esi, [r8 + rdx + 4]
    jbe .found
    lea r9d, [r11 + 1]
    jmp .search
.lo:
    mov r10d, r11d
    jmp .search
.found:
    movzx eax, byte [r8 + rdx + 8]
.set:
    mov [rdi + GI_CAT], al
    inc ebx
    jmp .each
.done:
    pop rbx
    ret

; ----------------------------------------------------------------------------
; pause: syllables, the rphf and topographical masks
; ----------------------------------------------------------------------------
; edi = position -> eax the first position from there the grammar sees (S_LEN:
;   none): not CGJ-class, not a ZWNJ followed (past CGJ-class characters) by
;   a mark
us_seen:
    mov eax, edi
.each:
    cmp eax, [r15 + S_LEN]
    jae .out
    REC rcx, rax
    movzx edx, byte [rcx + GI_CAT]
    cmp edx, U_CGJ
    je .skip
    cmp edx, U_ZWNJ
    jne .out
    lea r8d, [rax + 1]
.after:
    cmp r8d, [r15 + S_LEN]
    jae .out
    REC rcx, r8
    cmp byte [rcx + GI_CAT], U_CGJ
    jne .mark
    inc r8d
    jmp .after
.mark:
    movzx edx, byte [rcx + GI_GC]
    sub edx, GC_MC
    cmp edx, GC_MN - GC_MC
    ja .out
.skip:
    inc eax
    jmp .each
.out:
    ret

us_setup_syllables:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    sub rsp, 16
    lea r14, [rel ufl_use_machine]
    mov dword [rsp], 1                  ; serial
    mov byte [r15 + S_IBROKEN], 0
    xor edi, edi
    call us_seen
    mov ebx, eax                        ; p
.syllable:
    cmp ebx, [r15 + S_LEN]
    jae .masks
    xor r12d, r12d                      ; state
    mov r13d, ebx                       ; q
    mov ebp, -1                         ; the match's end
    mov dword [rsp + 4], U_NON          ; its type
.step:
    REC rax, r13
    movzx eax, byte [rax + GI_CAT]
    and eax, 63
    mov rcx, [r14 + SM_CLASSES]
    movzx eax, byte [rcx + rax]
    imul r12d, [r14 + SM_NCLASSES]
    add r12d, eax
    mov rcx, [r14 + SM_DFA]
    movzx r12d, byte [rcx + r12]
    cmp r12d, 255
    je .have
    lea edi, [r13 + 1]
    call us_seen
    mov r13d, eax
    mov rcx, [r14 + SM_ACCEPT]
    movzx ecx, byte [rcx + r12]
    cmp ecx, 255
    je .step_next
    mov ebp, eax
    mov [rsp + 4], ecx
.step_next:
    cmp r13d, [r15 + S_LEN]
    jb .step
.have:
    cmp ebp, -1
    jne .mark
    lea edi, [rbx + 1]                  ; cannot happen: anything is a syllable
    call us_seen
    mov ebp, eax
.mark:
    cmp dword [rsp + 4], U_BROKEN
    jne .assign
    mov byte [r15 + S_IBROKEN], 1
.assign:
    mov eax, [rsp]
    shl eax, 4
    or eax, [rsp + 4]
.set:
    cmp ebx, ebp
    jae .serial
    REC rdx, rbx
    mov [rdx + GI_SYL], al
    inc ebx
    jmp .set
.serial:
    inc dword [rsp]
    cmp dword [rsp], 16
    jne .syllable
    mov dword [rsp], 1
    jmp .syllable
.masks:
    call us_rphf_mask
    call us_topographical_masks
    add rsp, 16
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; esi = start -> edx = the end of its syllable (the run of its GI_SYL)
us_syllable_end:
    REC rax, rsi
    movzx ecx, byte [rax + GI_SYL]
    lea edx, [rsi + 1]
.each:
    cmp edx, [r15 + S_LEN]
    jae .out
    REC rax, rdx
    cmp [rax + GI_SYL], cl
    jne .out
    inc edx
    jmp .each
.out:
    ret

; rphf on a syllable's repha, else on its first three glyphs
us_rphf_mask:
    mov r9d, [r15 + S_UMASK]
    test r9d, r9d
    jz .out
    xor esi, esi
.syllable:
    cmp esi, [r15 + S_LEN]
    jae .out
    call us_syllable_end
    mov r8d, 1
    REC rax, rsi
    cmp byte [rax + GI_CAT], U_R
    je .mask
    mov r8d, edx
    sub r8d, esi
    cmp r8d, 3
    jbe .mask
    mov r8d, 3
.mask:
    add r8d, esi                        ; start + limit
.each:
    cmp esi, r8d
    jae .next
    REC rax, rsi
    or [rax + GI_MASK], r9d
    inc esi
    jmp .each
.next:
    mov esi, edx
    jmp .syllable
.out:
    ret

; isol / init / medi / fina on whole syllables as they join (not for scripts
;   that join like Arabic)
us_topographical_masks:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    call us_is_arabic
    je .out
    mov r12d, [r15 + S_UMASK + 4]
    or r12d, [r15 + S_UMASK + 8]
    or r12d, [r15 + S_UMASK + 12]
    or r12d, [r15 + S_UMASK + 16]
    test r12d, r12d
    jz .out
    not r12d                            ; the other masks
    xor r13d, r13d                      ; last start
    mov r14d, 4                         ; last form (none)
    xor esi, esi
.syllable:
    cmp esi, [r15 + S_LEN]
    jae .out
    mov ebx, esi                        ; start
    call us_syllable_end
    mov ebp, edx                        ; end
    REC rax, rbx
    movzx eax, byte [rax + GI_SYL]
    and eax, 0x0F
    cmp eax, U_HIEROGLYPH
    je .no_join
    cmp eax, U_NON
    je .no_join
    ; joins when the last one was fina or isol: that one becomes medi / init
    xor ecx, ecx                        ; join
    cmp r14d, 3
    je .join
    test r14d, r14d
    jne .form
.join:
    mov ecx, 1
    mov eax, 2                          ; fina -> medi
    cmp r14d, 3
    je .fix
    mov eax, 1                          ; isol -> init
.fix:
    mov r14d, eax
    mov edx, [r15 + S_UMASK + 4 + rax * 4]
    mov esi, r13d
.fix_each:
    cmp esi, ebx
    jae .form
    REC rax, rsi
    and [rax + GI_MASK], r12d
    or [rax + GI_MASK], edx
    inc esi
    jmp .fix_each
.form:
    xor r14d, r14d                      ; isol
    test ecx, ecx
    jz .set
    mov r14d, 3                         ; fina
.set:
    mov edx, [r15 + S_UMASK + 4 + r14 * 4]
    mov esi, ebx
.set_each:
    cmp esi, ebp
    jae .next
    REC rax, rsi
    and [rax + GI_MASK], r12d
    or [rax + GI_MASK], edx
    inc esi
    jmp .set_each
.no_join:
    mov r14d, 4
.next:
    mov r13d, ebx
    mov esi, ebp
    jmp .syllable
.out:
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; ----------------------------------------------------------------------------
; pauses: substitution flags, the repha and pref recorded
; ----------------------------------------------------------------------------
us_clear_substituted:
    xor ecx, ecx
.each:
    cmp ecx, [r15 + S_LEN]
    jae .done
    REC rax, rcx
    and word [rax + GI_PROPS], ~GP_SUBSTITUTED
    inc ecx
    jmp .each
.done:
    ret

; a syllable's substituted repha (among its rphf glyphs) recorded as R
us_record_rphf:
    mov r9d, [r15 + S_UMASK]
    test r9d, r9d
    jz .out
    xor esi, esi
.syllable:
    cmp esi, [r15 + S_LEN]
    jae .out
    call us_syllable_end
    mov ecx, esi
.each:
    cmp ecx, edx
    jae .next
    REC rax, rcx
    test [rax + GI_MASK], r9d
    jz .next
    test word [rax + GI_PROPS], GP_SUBSTITUTED
    jz .each_next
    mov byte [rax + GI_CAT], U_R
    jmp .next
.each_next:
    inc ecx
    jmp .each
.next:
    mov esi, edx
    jmp .syllable
.out:
    ret

; a syllable's first substituted glyph recorded as VPre (a pref behaves so)
us_record_pref:
    xor esi, esi
.syllable:
    cmp esi, [r15 + S_LEN]
    jae .out
    call us_syllable_end
    mov ecx, esi
.each:
    cmp ecx, edx
    jae .next
    REC rax, rcx
    test word [rax + GI_PROPS], GP_SUBSTITUTED
    jz .each_next
    mov byte [rax + GI_CAT], U_VPRE
    jmp .next
.each_next:
    inc ecx
    jmp .each
.next:
    mov esi, edx
    jmp .syllable
.out:
    ret

; ----------------------------------------------------------------------------
; pause: reordering
; ----------------------------------------------------------------------------
us_reorder:
    push rbx
    push rbp
    sub rsp, 8
    cmp byte [r15 + S_IBROKEN], 0
    je .syllables
    mov edi, U_BROKEN
    mov esi, U_B
    mov edx, U_R
    mov ecx, -1
    call ufl_syl_dotted_circles
.syllables:
    xor esi, esi
.each:
    cmp esi, [r15 + S_LEN]
    jae .done
    call us_syllable_end
    mov ebx, esi
    mov ebp, edx
    call us_reorder_syllable
    mov esi, ebp
    jmp .each
.done:
    add rsp, 8
    pop rbp
    pop rbx
    ret

; rax = record -> ZF clear for a halant (H, HVM, IS) that did not ligate
us_is_halant:
    movzx ecx, byte [rax + GI_CAT]
    cmp ecx, U_H
    je .maybe
    cmp ecx, U_HVM
    je .maybe
    cmp ecx, U_IS
    jne .no
.maybe:
    test word [rax + GI_PROPS], GP_LIGATED
    jnz .no
    or ecx, 1                           ; ZF clear
    ret
.no:
    xor ecx, ecx                        ; ZF set
    ret

; ebx = start, ebp = end
us_reorder_syllable:
    push r12
    push r13
    push r14
    REC rax, rbx
    movzx ecx, byte [rax + GI_SYL]
    and ecx, 0x0F
    mov edx, U_REORDERED
    bt edx, ecx
    jnc .out
    ; a repha towards the end, before the first post-base glyph
    cmp byte [rax + GI_CAT], U_R
    jne .back
    lea eax, [rbx + 1]
    cmp eax, ebp
    jae .back
    lea r12d, [rbx + 1]                 ; i
.repha:
    cmp r12d, ebp
    jae .back
    REC rax, r12
    movzx ecx, byte [rax + GI_CAT]
    mov r13, U_POST_BASE
    xor r14d, r14d                      ; post-base
    cmp ecx, 64
    jae .halant
    bt r13, rcx
    jc .post
.halant:
    call us_is_halant
    jz .last
.post:
    mov r14d, 1
    dec r12d
    jmp .move
.last:
    lea eax, [rbp - 1]
    cmp r12d, eax
    je .move
    inc r12d
    jmp .repha
.move:
    mov esi, ebx
    lea edx, [r12 + 1]
    call ufl_buf_merge_clusters
    ; info[start] to i, those between down one
    REC rax, rbx
    movdqu xmm2, [rax]
    movdqu xmm3, [rax + 16]
    mov ecx, ebx
.down:
    cmp ecx, r12d
    jae .put
    REC rax, rcx
    movdqu xmm0, [rax + 32]
    movdqu xmm1, [rax + 48]
    movdqu [rax], xmm0
    movdqu [rax + 16], xmm1
    inc ecx
    jmp .down
.put:
    REC rax, r12
    movdqu [rax], xmm2
    movdqu [rax + 16], xmm3
.back:
    ; pre-base vowels and vowel modifiers back, after the last halant
    mov r13d, ebx                       ; j
    mov r12d, ebx                       ; i
.back_each:
    cmp r12d, ebp
    jae .out
    REC rax, r12
    call us_is_halant
    jz .pre
    lea r13d, [r12 + 1]
    jmp .back_next
.pre:
    movzx ecx, byte [rax + GI_CAT]
    cmp ecx, U_VPRE
    je .pre_lig
    cmp ecx, U_VMPRE
    jne .back_next
.pre_lig:
    ; only a ligature's first component (or no ligature at all)
    movzx ecx, byte [rax + GI_LIG]
    test ecx, 0x10
    jnz .pre_move
    test ecx, 0x0F
    jnz .back_next
.pre_move:
    cmp r13d, r12d
    jae .back_next
    mov esi, r13d
    lea edx, [r12 + 1]
    call ufl_buf_merge_clusters
    REC rax, r12
    movdqu xmm2, [rax]
    movdqu xmm3, [rax + 16]
    mov ecx, r12d
.up:
    cmp ecx, r13d
    jbe .up_put
    REC rax, rcx
    movdqu xmm0, [rax - 32]
    movdqu xmm1, [rax - 16]
    movdqu [rax], xmm0
    movdqu [rax + 16], xmm1
    dec ecx
    jmp .up
.up_put:
    REC rax, r13
    movdqu [rax], xmm2
    movdqu [rax + 16], xmm3
.back_next:
    inc r12d
    jmp .back_each
.out:
    pop r14
    pop r13
    pop r12
    ret
