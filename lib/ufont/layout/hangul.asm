; =============================================================================
; Utkarsha OS — lib/ufont/layout/hangul.asm
; =============================================================================
; The Hangul shaper, as HarfBuzz's:
;
;   ufl_hangul_collect_features   ljmo, vjmo, tjmo
;   ufl_hangul_override_features  calt off
;   ufl_hangul_data_create        the three features' masks
;   ufl_hangul_preprocess         a syllable precomposed when the font has the
;                                 precomposed glyph (<L,V>, <L,V,T>, <LV,T>),
;                                 otherwise decomposed into jamo when the font
;                                 has them, the jamo marked for their feature
;                                 (GI_CAT) and one cluster; a tone mark after
;                                 a syllable moved in front of it unless its
;                                 glyph is zero-width, one with no syllable
;                                 before it given a dotted circle
;   ufl_hangul_setup_masks        the jamo features' masks
;
; Normalization only short-circuits (nothing recomposed); marks keep their
; widths.
; =============================================================================

%include "ufont.inc"
%include "shape.inc"

extern ufl_map_add_feature
extern ufl_map_disable
extern ufl_map_get_1_mask
extern ufl_buf_clear_output
extern ufl_buf_sync
extern ufl_buf_cur
extern ufl_buf_next_glyph
extern ufl_buf_out_slot
extern ufl_buf_merge_clusters
extern ufl_buf_merge_out_clusters
extern ufl_norm_glyph
extern ufont_advance

%define LBASE   0x1100
%define VBASE   0x1161
%define TBASE   0x11A7
%define SBASE   0xAC00
%define LCOUNT  19
%define VCOUNT  21
%define TCOUNT  28
%define NCOUNT  588
%define SCOUNT  11172
%define LJMO    1
%define VJMO    2
%define TJMO    3
%define S_HMASK S_AMASK                 ; [4] u32 (none, ljmo, vjmo, tjmo): the Arabic slots

; the preprocessing frame
%define HF_CPS      0                   ; [3] u32 characters to write
%define HF_T        16                  ; the trailing jamo (0: none)
%define HF_TINDEX   20
%define HF_HAS      24                  ; the font has the syllable
%define HF_LINDEX   28
%define HF_VINDEX   32
%define HF_SIZE     48

section .rodata
hg_features: dd 'ljmo', 'vjmo', 'tjmo'

section .text

global ufl_hangul_collect_features
ufl_hangul_collect_features:
    push rbx
    xor ebx, ebx
.each:
    lea rax, [rel hg_features]
    mov edi, [rax + rbx * 4]
    xor esi, esi
    mov edx, 1
    call ufl_map_add_feature
    inc ebx
    cmp ebx, 3
    jb .each
    pop rbx
    ret

global ufl_hangul_override_features
ufl_hangul_override_features:
    mov edi, 'calt'
    jmp ufl_map_disable

global ufl_hangul_data_create
ufl_hangul_data_create:
    push rbx
    mov dword [r15 + S_HMASK], 0
    xor ebx, ebx
.each:
    lea rax, [rel hg_features]
    mov edi, [rax + rbx * 4]
    call ufl_map_get_1_mask
    mov [r15 + S_HMASK + 4 + rbx * 4], eax
    inc ebx
    cmp ebx, 3
    jb .each
    pop rbx
    ret

global ufl_hangul_setup_masks
ufl_hangul_setup_masks:
    xor ecx, ecx
.each:
    cmp ecx, [r15 + S_LEN]
    jae .done
    mov rax, rcx
    shl rax, 5
    add rax, [r15 + S_INFO]
    movzx edx, byte [rax + GI_CAT]
    and edx, 3
    mov edx, [r15 + S_HMASK + rdx * 4]
    or [rax + GI_MASK], edx
    inc ecx
    jmp .each
.done:
    ret

; edi = code point -> eax the font's glyph (0: none)
hg_has:
    jmp ufl_norm_glyph

; edi = code point -> eax 1 when the font's glyph for it has no advance
hg_zero_width:
    sub rsp, 8
    call ufl_norm_glyph
    test eax, eax
    jz .no
    mov esi, eax
    mov rdi, [r15 + S_FONT]
    call ufont_advance
    test eax, eax
    jnz .no
    mov eax, 1
    add rsp, 8
    ret
.no:
    xor eax, eax
    add rsp, 8
    ret

; esi = characters in, rdx = characters out (u32), ecx = how many: HarfBuzz's
;   replace_glyphs - the clusters merged, each written a copy of the first
hg_replace:
    push rbx
    push r12
    push r13
    mov ebx, esi
    mov r12, rdx
    mov r13d, ecx
    mov esi, [r15 + S_IDX]
    lea edx, [rsi + rbx]
    call ufl_buf_merge_clusters
.out:
    test r13d, r13d
    jz .done
    call ufl_buf_out_slot
    mov esi, [r15 + S_IDX]
    shl rsi, 5
    add rsi, [r15 + S_INFO]
    movdqu xmm0, [rsi]
    movdqu xmm1, [rsi + 16]
    movdqu [rdi], xmm0
    movdqu [rdi + 16], xmm1
    mov eax, [r12]
    mov [rdi + GI_CP], eax
    add r12, 4
    dec r13d
    jmp .out
.done:
    add [r15 + S_IDX], ebx
    pop r13
    pop r12
    pop rbx
    ret

; edi = position -> eax the input's code point there
%macro CP_AT 1
    mov eax, %1
    shl rax, 5
    add rax, [r15 + S_INFO]
    mov eax, [rax + GI_CP]
%endmacro

; ----------------------------------------------------------------------------
; ufl_hangul_preprocess
; ----------------------------------------------------------------------------
global ufl_hangul_preprocess
ufl_hangul_preprocess:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    sub rsp, HF_SIZE
    call ufl_buf_clear_output
    xor r12d, r12d                      ; start
    xor r13d, r13d                      ; end (a syllable when start < end)
    mov r14d, [r15 + S_LEN]
.loop:
    cmp byte [r15 + S_ERR], 0
    jne .sync
    mov eax, [r15 + S_IDX]
    cmp eax, r14d
    jae .sync
    call ufl_buf_cur
    mov ebx, [rax + GI_CP]
    lea eax, [rbx - 0x302E]
    cmp eax, 1
    ja .syllable
    ; a tone mark
    cmp r12d, r13d
    jae .tone_alone
    cmp r13d, [r15 + S_OUTLEN]
    jne .tone_alone
    call ufl_buf_next_glyph
    mov edi, ebx
    call hg_zero_width
    test eax, eax
    jnz .tone_done
    ; in front of the syllable
    mov esi, r12d
    lea edx, [r13 + 1]
    call ufl_buf_merge_out_clusters
    mov rcx, [r15 + S_OUT]
    mov eax, r13d
    shl rax, 5
    movdqu xmm2, [rcx + rax]
    movdqu xmm3, [rcx + rax + 16]
.tone_shift:
    mov edx, eax
    shr edx, 5
    cmp edx, r12d
    jbe .tone_put
    movdqu xmm0, [rcx + rax - 32]
    movdqu xmm1, [rcx + rax - 16]
    movdqu [rcx + rax], xmm0
    movdqu [rcx + rax + 16], xmm1
    sub rax, 32
    jmp .tone_shift
.tone_put:
    movdqu [rcx + rax], xmm2
    movdqu [rcx + rax + 16], xmm3
    jmp .tone_done
.tone_alone:
    mov edi, 0x25CC
    call hg_has
    test eax, eax
    jz .tone_plain
    mov edi, ebx
    call hg_zero_width
    mov dword [rsp + HF_CPS], ebx
    mov dword [rsp + HF_CPS + 4], 0x25CC
    test eax, eax
    jz .tone_circle
    mov dword [rsp + HF_CPS], 0x25CC
    mov dword [rsp + HF_CPS + 4], ebx
.tone_circle:
    mov esi, 1
    lea rdx, [rsp + HF_CPS]
    mov ecx, 2
    call hg_replace
    jmp .tone_done
.tone_plain:
    call ufl_buf_next_glyph
.tone_done:
    mov r12d, [r15 + S_OUTLEN]
    mov r13d, r12d
    jmp .loop

.syllable:
    mov r12d, [r15 + S_OUTLEN]
    ; <L,V> or <L,V,T>?
    lea eax, [rbx - 0x1100]
    cmp eax, 0x5F
    jbe .is_l
    lea eax, [rbx - 0xA960]
    cmp eax, 0x1C
    ja .combined
.is_l:
    mov ebp, [r15 + S_IDX]
    lea eax, [rbp + 1]
    cmp eax, r14d
    jae .plain
    CP_AT eax
    mov edi, eax
    call hg_is_v
    test ecx, ecx
    jz .plain
    mov ebp, edi                        ; v
    mov dword [rsp + HF_T], 0
    mov dword [rsp + HF_TINDEX], 0
    mov eax, [r15 + S_IDX]
    add eax, 2
    cmp eax, r14d
    jae .lv_have
    CP_AT eax
    mov edi, eax
    call hg_is_t
    test ecx, ecx
    jz .lv_have
    mov [rsp + HF_T], edi
    lea eax, [rdi - TBASE]
    mov [rsp + HF_TINDEX], eax
.lv_have:
    ; composable?
    lea eax, [rbx - LBASE]
    cmp eax, LCOUNT
    jae .jamo
    lea eax, [rbp - VBASE]
    cmp eax, VCOUNT
    jae .jamo
    mov eax, [rsp + HF_T]
    test eax, eax
    jz .compose
    sub eax, TBASE + 1
    cmp eax, TCOUNT - 1
    jae .jamo
.compose:
    lea eax, [rbx - LBASE]
    imul eax, eax, NCOUNT
    lea ecx, [rbp - VBASE]
    imul ecx, ecx, TCOUNT
    add eax, ecx
    add eax, [rsp + HF_TINDEX]
    add eax, SBASE
    mov [rsp + HF_CPS], eax
    mov edi, eax
    call hg_has
    test eax, eax
    jz .jamo
    mov esi, 2
    cmp dword [rsp + HF_T], 0
    je .compose_2
    mov esi, 3
.compose_2:
    lea rdx, [rsp + HF_CPS]
    mov ecx, 1
    call hg_replace
    lea r13d, [r12 + 1]
    jmp .loop
.jamo:
    ; not composed: the jamo features, one cluster
    call ufl_buf_cur
    mov byte [rax + GI_CAT], LJMO
    call ufl_buf_next_glyph
    call ufl_buf_cur
    mov byte [rax + GI_CAT], VJMO
    call ufl_buf_next_glyph
    lea r13d, [r12 + 2]
    cmp dword [rsp + HF_T], 0
    je .jamo_merge
    call ufl_buf_cur
    mov byte [rax + GI_CAT], TJMO
    call ufl_buf_next_glyph
    lea r13d, [r12 + 3]
.jamo_merge:
    cmp byte [r15 + S_ERR], 0
    jne .sync
    mov esi, r12d
    mov edx, r13d
    call ufl_buf_merge_out_clusters
    jmp .loop

.combined:
    ; <LV>, <LVT> or <LV,T>
    lea eax, [rbx - SBASE]
    cmp eax, SCOUNT
    jae .plain
    xor edx, edx
    mov ecx, NCOUNT
    div ecx
    mov [rsp + HF_LINDEX], eax
    mov eax, edx
    xor edx, edx
    mov ecx, TCOUNT
    div ecx
    mov [rsp + HF_VINDEX], eax
    mov [rsp + HF_TINDEX], edx
    mov edi, ebx
    call hg_has
    mov [rsp + HF_HAS], eax
    ; the code point after (0: none)
    xor ebp, ebp
    mov eax, [r15 + S_IDX]
    inc eax
    cmp eax, r14d
    jae .have_next
    CP_AT eax
    mov ebp, eax
.have_next:
    cmp dword [rsp + HF_TINDEX], 0
    jne .decompose
    lea eax, [rbp - TBASE - 1]
    cmp eax, TCOUNT - 1
    jae .decompose
    ; <LV,T>: combined when the font has it
    lea edi, [rbx + rbp - TBASE]
    mov [rsp + HF_CPS], edi
    call hg_has
    test eax, eax
    jz .decompose
    mov esi, 2
    lea rdx, [rsp + HF_CPS]
    mov ecx, 1
    call hg_replace
    lea r13d, [r12 + 1]
    jmp .loop
.decompose:
    ; decomposed when the font lacks the syllable, or an LV is followed by a
    ; trailing jamo that does not combine
    cmp dword [rsp + HF_HAS], 0
    je .decompose_try
    cmp dword [rsp + HF_TINDEX], 0
    jne .kept
    mov edi, ebp
    call hg_is_t
    test ecx, ecx
    jz .kept
.decompose_try:
    mov eax, [rsp + HF_LINDEX]
    add eax, LBASE
    mov [rsp + HF_CPS], eax
    mov eax, [rsp + HF_VINDEX]
    add eax, VBASE
    mov [rsp + HF_CPS + 4], eax
    mov eax, [rsp + HF_TINDEX]
    add eax, TBASE
    mov [rsp + HF_CPS + 8], eax
    mov edi, [rsp + HF_CPS]
    call hg_has
    test eax, eax
    jz .kept
    mov edi, [rsp + HF_CPS + 4]
    call hg_has
    test eax, eax
    jz .kept
    cmp dword [rsp + HF_TINDEX], 0
    je .decompose_do
    mov edi, [rsp + HF_CPS + 8]
    call hg_has
    test eax, eax
    jz .kept
.decompose_do:
    mov ecx, 2
    cmp dword [rsp + HF_TINDEX], 0
    je .decompose_n
    mov ecx, 3
.decompose_n:
    mov ebp, ecx                        ; s_len
    mov esi, 1
    lea rdx, [rsp + HF_CPS]
    call hg_replace
    cmp dword [rsp + HF_HAS], 0
    je .decompose_marks
    cmp dword [rsp + HF_TINDEX], 0
    jne .decompose_marks
    ; the LV decomposed for the trailing jamo after it: that one joins
    call ufl_buf_next_glyph
    inc ebp
.decompose_marks:
    cmp byte [r15 + S_ERR], 0
    jne .sync
    lea r13d, [r12 + rbp]
    mov rax, r12
    shl rax, 5
    add rax, [r15 + S_OUT]
    mov byte [rax + GI_CAT], LJMO
    mov byte [rax + 32 + GI_CAT], VJMO
    cmp ebp, 2
    jbe .decompose_merge
    mov byte [rax + 64 + GI_CAT], TJMO
.decompose_merge:
    mov esi, r12d
    mov edx, r13d
    call ufl_buf_merge_out_clusters
    jmp .loop
.kept:
    cmp dword [rsp + HF_HAS], 0
    je .plain
    lea r13d, [r12 + 1]
.plain:
    call ufl_buf_next_glyph
    jmp .loop
.sync:
    call ufl_buf_sync
    add rsp, HF_SIZE
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; edi = code point -> ecx 1 for a vowel jamo (edi kept)
hg_is_v:
    xor ecx, ecx
    lea eax, [rdi - 0x1160]
    cmp eax, 0x47
    jbe .yes
    lea eax, [rdi - 0xD7B0]
    cmp eax, 0x16
    ja .out
.yes:
    mov ecx, 1
.out:
    ret

; edi = code point -> ecx 1 for a trailing jamo (edi kept)
hg_is_t:
    xor ecx, ecx
    lea eax, [rdi - 0x11A8]
    cmp eax, 0x57
    jbe .yes
    lea eax, [rdi - 0xD7CB]
    cmp eax, 0x30
    ja .out
.yes:
    mov ecx, 1
.out:
    ret
