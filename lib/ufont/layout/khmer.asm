; =============================================================================
; Utkarsha OS — lib/ufont/layout/khmer.asm
; =============================================================================
; The Khmer shaper, as HarfBuzz's:
;
;   ufl_khmer_collect_features    pauses for syllables and reordering; locl,
;                                 ccmp and pref / blwf / abvf / pstf / cfar
;                                 held to the syllable; the syllables cleared;
;                                 pres / abvs / blws / psts
;   ufl_khmer_override_features   clig on, liga off
;   ufl_khmer_data_create         the basic features' masks
;   (categories: ufl_indic_setup_masks, the shared table)
;
; Reordering: dotted circles in broken clusters; in each syllable blwf /
; abvf / pstf on everything after the base, a COENG + RO (of the first two
; coengs) moved before the base with pref and cfar after it, a pre-base
; vowel moved to the start. Split vowels decompose into U+17C1 + the vowel
; (layout/normalize.asm), nothing composes onto a mark, no short circuit;
; marks keep their widths, no fallback positioning.
; =============================================================================

%include "ufont.inc"
%include "shape.inc"

extern ufl_map_add_feature
extern ufl_map_enable
extern ufl_map_disable
extern ufl_map_add_gsub_pause
extern ufl_map_get_1_mask
extern ufl_buf_merge_clusters
extern ufl_syl_find
extern ufl_syl_dotted_circles
extern ufl_syl_clear
extern ufl_khmer_machine

; categories
%define K_H             4
%define K_DOTTEDCIRCLE  11
%define K_RA            15
%define K_VPRE          22
; syllable types
%define K_CONSONANT     0
%define K_BROKEN        1
; masks (S_KMASK: the Indic slots)
%define S_KMASK         S_IMASK
%define KM_PREF         0
%define KM_BLWF         4
%define KM_ABVF         8
%define KM_PSTF         12
%define KM_CFAR         16

section .rodata
kh_basic: dd 'pref', 'blwf', 'abvf', 'pstf', 'cfar'
kh_other: dd 'pres', 'abvs', 'blws', 'psts'

section .text

; ----------------------------------------------------------------------------
; the plan
; ----------------------------------------------------------------------------
global ufl_khmer_collect_features
ufl_khmer_collect_features:
    push rbx
    lea rdi, [rel kh_setup_syllables]
    call ufl_map_add_gsub_pause
    lea rdi, [rel kh_reorder]
    call ufl_map_add_gsub_pause
    mov edi, 'locl'
    mov esi, F_PER_SYLLABLE
    mov edx, 1
    call ufl_map_enable
    mov edi, 'ccmp'
    mov esi, F_PER_SYLLABLE
    mov edx, 1
    call ufl_map_enable
    xor ebx, ebx
.basic:
    lea rax, [rel kh_basic]
    mov edi, [rax + rbx * 4]
    mov esi, F_MANUAL_JOINERS | F_PER_SYLLABLE
    mov edx, 1
    call ufl_map_add_feature
    inc ebx
    cmp ebx, 5
    jb .basic
    lea rdi, [rel ufl_syl_clear]
    call ufl_map_add_gsub_pause
    xor ebx, ebx
.other:
    lea rax, [rel kh_other]
    mov edi, [rax + rbx * 4]
    mov esi, F_GLOBAL | F_MANUAL_JOINERS
    mov edx, 1
    call ufl_map_add_feature
    inc ebx
    cmp ebx, 4
    jb .other
    pop rbx
    ret

global ufl_khmer_override_features
ufl_khmer_override_features:
    sub rsp, 8
    mov edi, 'clig'
    xor esi, esi
    mov edx, 1
    call ufl_map_enable
    mov edi, 'liga'
    call ufl_map_disable
    add rsp, 8
    ret

global ufl_khmer_data_create
ufl_khmer_data_create:
    push rbx
    xor ebx, ebx
.each:
    lea rax, [rel kh_basic]
    mov edi, [rax + rbx * 4]
    call ufl_map_get_1_mask
    mov [r15 + S_KMASK + rbx * 4], eax
    inc ebx
    cmp ebx, 5
    jb .each
    pop rbx
    ret

; ----------------------------------------------------------------------------
; pauses
; ----------------------------------------------------------------------------
kh_setup_syllables:
    sub rsp, 8
    lea rdi, [rel ufl_khmer_machine]
    call ufl_syl_find
    mov [r15 + S_IBROKEN], al
    add rsp, 8
    ret

kh_reorder:
    push rbx
    push rbp
    push r12
    cmp byte [r15 + S_IBROKEN], 0
    je .syllables
    mov edi, K_BROKEN
    mov esi, K_DOTTEDCIRCLE
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
    cmp r12d, K_BROKEN
    ja .next
    mov esi, ebx
    mov edx, ebp
    call kh_reorder_syllable
.next:
    mov ebx, ebp
    jmp .each
.done:
    pop r12
    pop rbp
    pop rbx
    ret

; esi = start, edx = end: a consonant syllable (or broken cluster) reordered
kh_reorder_syllable:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    mov r12d, esi                       ; start
    mov r13d, edx                       ; end
    ; blwf / abvf / pstf after the base
    mov eax, [r15 + S_KMASK + KM_BLWF]
    or eax, [r15 + S_KMASK + KM_ABVF]
    or eax, [r15 + S_KMASK + KM_PSTF]
    lea ecx, [r12 + 1]
.post:
    cmp ecx, r13d
    jae .post_done
    mov rdx, rcx
    shl rdx, 5
    add rdx, [r15 + S_INFO]
    or [rdx + GI_MASK], eax
    inc ecx
    jmp .post
.post_done:
    xor r14d, r14d                      ; coengs
    lea ebx, [r12 + 1]                  ; i
.each:
    cmp ebx, r13d
    jae .done
    mov rbp, rbx
    shl rbp, 5
    add rbp, [r15 + S_INFO]
    movzx eax, byte [rbp + GI_CAT]
    cmp eax, K_H
    jne .vpre
    cmp r14d, 2
    ja .next
    lea ecx, [rbx + 1]
    cmp ecx, r13d
    jae .next
    inc r14d
    cmp byte [rbp + 32 + GI_CAT], K_RA
    jne .next
    ; COENG + RO: pref, then before the base
    mov eax, [r15 + S_KMASK + KM_PREF]
    or [rbp + GI_MASK], eax
    or [rbp + 32 + GI_MASK], eax
    mov esi, r12d
    lea edx, [rbx + 2]
    call ufl_buf_merge_clusters
    mov rbp, rbx
    shl rbp, 5
    add rbp, [r15 + S_INFO]
    movdqu xmm2, [rbp]
    movdqu xmm3, [rbp + 16]
    movdqu xmm4, [rbp + 32]
    movdqu xmm5, [rbp + 48]
    ; info[start .. i) up by two
    mov rcx, rbp
.coeng_shift:
    mov rax, r12
    shl rax, 5
    add rax, [r15 + S_INFO]
    cmp rcx, rax
    jbe .coeng_put
    movdqu xmm0, [rcx - 32]
    movdqu xmm1, [rcx - 16]
    movdqu [rcx + 32], xmm0
    movdqu [rcx + 48], xmm1
    sub rcx, 32
    jmp .coeng_shift
.coeng_put:
    movdqu [rax], xmm2
    movdqu [rax + 16], xmm3
    movdqu [rax + 32], xmm4
    movdqu [rax + 48], xmm5
    ; cfar on what follows
    mov eax, [r15 + S_KMASK + KM_CFAR]
    test eax, eax
    jz .coeng_done
    lea ecx, [rbx + 2]
.cfar:
    cmp ecx, r13d
    jae .coeng_done
    mov rdx, rcx
    shl rdx, 5
    add rdx, [r15 + S_INFO]
    or [rdx + GI_MASK], eax
    inc ecx
    jmp .cfar
.coeng_done:
    mov r14d, 2
    jmp .next
.vpre:
    cmp eax, K_VPRE
    jne .next
    ; a pre-base vowel to the start
    mov esi, r12d
    lea edx, [rbx + 1]
    call ufl_buf_merge_clusters
    mov rbp, rbx
    shl rbp, 5
    add rbp, [r15 + S_INFO]
    movdqu xmm2, [rbp]
    movdqu xmm3, [rbp + 16]
    mov rcx, rbp
.vpre_shift:
    mov rax, r12
    shl rax, 5
    add rax, [r15 + S_INFO]
    cmp rcx, rax
    jbe .vpre_put
    movdqu xmm0, [rcx - 32]
    movdqu xmm1, [rcx - 16]
    movdqu [rcx], xmm0
    movdqu [rcx + 16], xmm1
    sub rcx, 32
    jmp .vpre_shift
.vpre_put:
    movdqu [rax], xmm2
    movdqu [rax + 16], xmm3
.next:
    inc ebx
    jmp .each
.done:
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret
