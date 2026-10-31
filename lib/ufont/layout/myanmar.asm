; =============================================================================
; Utkarsha OS — lib/ufont/layout/myanmar.asm
; =============================================================================
; The Myanmar shaper, as HarfBuzz's (for fonts with a mym2 script; DFLT,
; latn or the old mymr take the default shaper):
;
;   ufl_myanmar_collect_features  pauses for syllables and reordering; locl
;                                 and ccmp, then rphf / pref / blwf / pstf one
;                                 at a time, held to the syllable; the
;                                 syllables cleared; pres / abvs / blws / psts
;   (categories: ufl_indic_setup_masks, the shared table)
;
; Reordering: dotted circles in broken clusters; in each syllable kinzi
; (RA + ASAT + VIRAMA) after the main part, everything before the base
; consonant pre-base, medial RA pre-base, pre-base vowels before it all,
; variation selectors with what they follow, below parts and what comes
; after them by position; sorted by position; a run of pre-base vowels
; flipped, each keeping its variation selectors after it. No short circuit;
; marks' widths zeroed before GPOS, no fallback positioning.
; =============================================================================

%include "ufont.inc"
%include "shape.inc"

extern ufl_map_enable
extern ufl_map_add_gsub_pause
extern ufl_buf_sort
extern ufl_buf_reverse
extern ufl_syl_find
extern ufl_syl_dotted_circles
extern ufl_syl_clear
extern ufl_myanmar_machine

; categories
%define M_C             1
%define M_IV            2
%define M_H             4
%define M_A             9
%define M_GB            10
%define M_DOTTEDCIRCLE  11
%define M_RA            15
%define M_CS            18
%define M_VBLW          21
%define M_VPRE          22
%define M_AS            32
%define M_MR            36
%define M_VS            40
%define M_CONSONANTS    (1 << M_C) | (1 << M_CS) | (1 << M_RA) | (1 << M_IV) | (1 << M_GB) | (1 << M_DOTTEDCIRCLE)
; positions
%define P_PRE_M         2
%define P_PRE_C         3
%define P_BASE_C        4
%define P_AFTER_MAIN    5
%define P_BEFORE_SUB    7
%define P_BELOW_C       8
%define P_AFTER_SUB     9
; syllable types
%define M_BROKEN        1

section .rodata
my_basic: dd 'rphf', 'pref', 'blwf', 'pstf'
my_other: dd 'pres', 'abvs', 'blws', 'psts'

section .text

; ----------------------------------------------------------------------------
; the plan
; ----------------------------------------------------------------------------
global ufl_myanmar_collect_features
ufl_myanmar_collect_features:
    push rbx
    lea rdi, [rel my_setup_syllables]
    call ufl_map_add_gsub_pause
    mov edi, 'locl'
    mov esi, F_PER_SYLLABLE
    mov edx, 1
    call ufl_map_enable
    mov edi, 'ccmp'
    mov esi, F_PER_SYLLABLE
    mov edx, 1
    call ufl_map_enable
    lea rdi, [rel my_reorder]
    call ufl_map_add_gsub_pause
    xor ebx, ebx
.basic:
    lea rax, [rel my_basic]
    mov edi, [rax + rbx * 4]
    mov esi, F_MANUAL_ZWJ | F_PER_SYLLABLE
    mov edx, 1
    call ufl_map_enable
    xor edi, edi
    call ufl_map_add_gsub_pause
    inc ebx
    cmp ebx, 4
    jb .basic
    lea rdi, [rel ufl_syl_clear]
    call ufl_map_add_gsub_pause
    xor ebx, ebx
.other:
    lea rax, [rel my_other]
    mov edi, [rax + rbx * 4]
    mov esi, F_MANUAL_ZWJ
    mov edx, 1
    call ufl_map_enable
    inc ebx
    cmp ebx, 4
    jb .other
    pop rbx
    ret

; ----------------------------------------------------------------------------
; pauses
; ----------------------------------------------------------------------------
my_setup_syllables:
    sub rsp, 8
    lea rdi, [rel ufl_myanmar_machine]
    call ufl_syl_find
    mov [r15 + S_IBROKEN], al
    add rsp, 8
    ret

my_reorder:
    push rbx
    push rbp
    push r12
    cmp byte [r15 + S_IBROKEN], 0
    je .syllables
    mov edi, M_BROKEN
    mov esi, M_DOTTEDCIRCLE
    mov edx, -1
    mov ecx, -1
    call ufl_syl_dotted_circles
.syllables:
    xor ebx, ebx                        ; start
.each:
    cmp ebx, [r15 + S_LEN]
    jae .done
    mov rax, rbx
    shl rax, 5
    add rax, [r15 + S_INFO]
    movzx r12d, byte [rax + GI_SYL]
    lea ebp, [rbx + 1]                  ; end
.end:
    cmp ebp, [r15 + S_LEN]
    jae .have
    mov rax, rbp
    shl rax, 5
    add rax, [r15 + S_INFO]
    cmp [rax + GI_SYL], r12b
    jne .have
    inc ebp
    jmp .end
.have:
    and r12d, 0x0F
    cmp r12d, M_BROKEN
    ja .next
    mov esi, ebx
    mov edx, ebp
    call my_reorder_syllable
.next:
    mov ebx, ebp
    jmp .each
.done:
    pop r12
    pop rbp
    pop rbx
    ret

; the record at index %2 -> %1
%macro REC 2
    mov %1, %2
    shl %1, 5
    add %1, [r15 + S_INFO]
%endmacro

; esi = start, edx = end: a consonant syllable (or broken cluster) reordered
my_reorder_syllable:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    mov r12d, esi                       ; start
    mov r13d, edx                       ; end
    mov r14d, r12d                      ; limit
    xor ebp, ebp                        ; has reph (kinzi)
    lea eax, [r12 + 3]
    cmp eax, r13d
    ja .base
    REC rax, r12
    cmp byte [rax + GI_CAT], M_RA
    jne .base
    cmp byte [rax + 32 + GI_CAT], M_AS
    jne .base
    cmp byte [rax + 64 + GI_CAT], M_H
    jne .base
    add r14d, 3
    mov ebp, 1
.base:
    ; the base: the first consonant from limit (else limit, or start with kinzi)
    mov ebx, r14d
    test ebp, ebp
    jz .find
    mov ebx, r12d
.find:
    mov ecx, r14d
.find_next:
    cmp ecx, r13d
    jae .found
    REC rax, rcx
    test word [rax + GI_PROPS], GP_LIGATED
    jnz .find_skip
    movzx edx, byte [rax + GI_CAT]
    cmp edx, 32
    jae .find_skip
    mov r8d, M_CONSONANTS
    bt r8d, edx
    jnc .find_skip
    mov ebx, ecx
    jmp .found
.find_skip:
    inc ecx
    jmp .find_next
.found:
    ; positions
    mov ecx, r12d                       ; i
    test ebp, ebp
    jz .pre
.kinzi:
    lea eax, [r12 + 3]
    cmp ecx, eax
    jae .pre
    REC rax, rcx
    mov byte [rax + GI_POS], P_AFTER_MAIN
    inc ecx
    jmp .kinzi
.pre:
    cmp ecx, ebx
    jae .at_base
    REC rax, rcx
    mov byte [rax + GI_POS], P_PRE_C
    inc ecx
    jmp .pre
.at_base:
    cmp ecx, r13d
    jae .sort
    REC rax, rcx
    mov byte [rax + GI_POS], P_BASE_C
    inc ecx
    mov r9d, P_AFTER_MAIN               ; pos
.after:
    cmp ecx, r13d
    jae .sort
    REC rax, rcx
    movzx edx, byte [rax + GI_CAT]
    cmp edx, M_MR
    jne .not_mr
    mov byte [rax + GI_POS], P_PRE_C
    jmp .after_next
.not_mr:
    cmp edx, M_VPRE
    jne .not_vpre
    mov byte [rax + GI_POS], P_PRE_M
    jmp .after_next
.not_vpre:
    cmp edx, M_VS
    jne .not_vs
    mov dl, [rax - 32 + GI_POS]
    mov [rax + GI_POS], dl
    jmp .after_next
.not_vs:
    cmp r9d, P_AFTER_MAIN
    jne .below
    cmp edx, M_VBLW
    jne .set_pos
    mov r9d, P_BELOW_C
    jmp .set_pos
.below:
    cmp r9d, P_BELOW_C
    jne .set_pos
    cmp edx, M_A
    jne .below_vblw
    mov byte [rax + GI_POS], P_BEFORE_SUB
    jmp .after_next
.below_vblw:
    cmp edx, M_VBLW
    je .set_pos
    mov r9d, P_AFTER_SUB
.set_pos:
    mov [rax + GI_POS], r9b
.after_next:
    inc ecx
    jmp .after
.sort:
    mov esi, r12d
    mov edx, r13d
    mov ecx, GI_POS
    call ufl_buf_sort
    ; a run of pre-base vowels flipped
    mov ebx, r13d                       ; first
    mov ebp, r13d                       ; last
    mov ecx, r12d
.left:
    cmp ecx, r13d
    jae .flip
    REC rax, rcx
    cmp byte [rax + GI_POS], P_PRE_M
    jne .left_next
    cmp ebx, r13d
    jne .left_last
    mov ebx, ecx
.left_last:
    mov ebp, ecx
.left_next:
    inc ecx
    jmp .left
.flip:
    cmp ebx, ebp
    jae .done
    mov esi, ebx
    lea edx, [rbp + 1]
    call ufl_buf_reverse
    ; each vowel's variation selectors back after it
    mov r12d, ebx                       ; i
    mov r14d, ebx                       ; j
.back:
    cmp r14d, ebp
    ja .done
    REC rax, r14
    cmp byte [rax + GI_CAT], M_VPRE
    jne .back_next
    mov esi, r12d
    lea edx, [r14 + 1]
    call ufl_buf_reverse
    lea r12d, [r14 + 1]
.back_next:
    inc r14d
    jmp .back
.done:
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret
