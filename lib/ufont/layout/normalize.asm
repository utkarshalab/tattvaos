; =============================================================================
; Utkarsha OS — lib/ufont/layout/normalize.asm
; =============================================================================
; Normalization against the font, as HarfBuzz does it before shaping
; ("composed diacritics"): characters the font lacks are decomposed into
; ones it has (the shortest way for runs without marks, fully under marks),
; marks are put in combining-class order, then marks are composed back
; onto their base where the font has the composite. A base with a
; variation selector takes the font's variant glyph (cmap format 14) and
; is not normalized. Spaces the font lacks become its space glyph (widened
; later); a non-breaking hyphen it lacks, its hyphen. The Indic shaper
; decomposes every character first (no short cut), keeps U+0931 / U+09DC /
; U+09DD / U+0B94 whole and composes nothing onto a mark.
;
;   norm_run                  the buffer normalized; GI_GLYPH set for every record
;   norm_glyph(edi = cp)      -> eax the font's glyph, 0 none
;   norm_variation(edi = cp, esi = selector) -> eax glyph, 0 none
; =============================================================================

%include "ufont.inc"
%include "shape.inc"

extern ufont_glyph
extern uc_set_props
extern uc_decompose
extern uc_compose
extern uc_space_type
extern uc_is_vs
extern uc_is_mark_gc
extern ucd_gc
extern buf_clear_output
extern buf_sync
extern buf_next_glyph
extern buf_skip_glyph
extern buf_out_slot
extern buf_sort
extern buf_merge_out_clusters

section .text

; ----------------------------------------------------------------------------
; norm_glyph — edi = code point -> eax = glyph (0: the font has none)
; ----------------------------------------------------------------------------
global norm_glyph
norm_glyph:
    mov esi, edi
    mov rdi, [r15 + S_FONT]
    jmp ufont_glyph

; ----------------------------------------------------------------------------
; norm_variation — edi = code point, esi = variation selector -> eax = glyph
;   (0: no variant; the default variant is the nominal glyph)
; ----------------------------------------------------------------------------
global norm_variation
norm_variation:
    push rbx
    push r12
    push r13
    mov r12d, edi
    mov r13d, esi
    mov rax, [r15 + S_FONT]
    mov rbx, [rax + UfontFont_cmap14]
    mov r8, [rax + UfontFont_cmap14_len]
    test rbx, rbx
    jz .none
    cmp r8, 10
    jb .none
    BE32 ecx, [rbx + 6]                 ; records
    mov rax, rcx
    imul rax, rax, 11
    add rax, 10
    cmp rax, r8
    ja .none
    ; binary search the selector (u24)
    xor r9d, r9d
    mov r10d, ecx
.sel:
    cmp r9d, r10d
    jae .none
    lea r11d, [r9 + r10]
    shr r11d, 1
    imul eax, r11d, 11
    lea rdx, [rbx + rax + 10]
    call .u24
    cmp r13d, eax
    je .record
    jb .sel_lo
    lea r9d, [r11 + 1]
    jmp .sel
.sel_lo:
    mov r10d, r11d
    jmp .sel
.record:
    ; default variations: ranges (u24 start, u8 extra)
    BE32 eax, [rdx + 3]
    test eax, eax
    jz .nondefault
    lea rcx, [rax + 4]
    cmp rcx, r8
    ja .nondefault
    lea rsi, [rbx + rax]
    BE32 ecx, [rsi]
    mov rax, rcx
    shl rax, 2
    add rax, 4
    add rax, rsi
    sub rax, rbx
    cmp rax, r8
    ja .nondefault
    push rdx
    xor r9d, r9d
    mov r10d, ecx
.def:
    cmp r9d, r10d
    jae .def_none
    lea r11d, [r9 + r10]
    shr r11d, 1
    lea rdx, [rsi + r11 * 4 + 4]
    call .u24
    cmp r12d, eax
    jb .def_lo
    movzx ecx, byte [rdx + 3]
    add eax, ecx
    cmp r12d, eax
    jbe .default
    lea r9d, [r11 + 1]
    jmp .def
.def_lo:
    mov r10d, r11d
    jmp .def
.default:
    pop rdx
    mov edi, r12d
    call norm_glyph
    jmp .out
.def_none:
    pop rdx
.nondefault:
    BE32 eax, [rdx + 7]
    test eax, eax
    jz .none
    lea rcx, [rax + 4]
    cmp rcx, r8
    ja .none
    lea rsi, [rbx + rax]
    BE32 ecx, [rsi]
    mov rax, rcx
    imul rax, rax, 5
    add rax, 4
    add rax, rsi
    sub rax, rbx
    cmp rax, r8
    ja .none
    xor r9d, r9d
    mov r10d, ecx
.nd:
    cmp r9d, r10d
    jae .none
    lea r11d, [r9 + r10]
    shr r11d, 1
    imul eax, r11d, 5
    lea rdx, [rsi + rax + 4]
    call .u24
    cmp r12d, eax
    je .nd_found
    jb .nd_lo
    lea r9d, [r11 + 1]
    jmp .nd
.nd_lo:
    mov r10d, r11d
    jmp .nd
.nd_found:
    BE16 eax, [rdx + 3]
    jmp .out
.none:
    xor eax, eax
.out:
    pop r13
    pop r12
    pop rbx
    ret
; rdx -> eax = the big-endian u24 there
.u24:
    movzx eax, byte [rdx]
    shl eax, 16
    movzx ecx, byte [rdx + 1]
    shl ecx, 8
    or eax, ecx
    movzx ecx, byte [rdx + 2]
    or eax, ecx
    ret

; the shaper's decomposition: edi = ab -> eax 1 / 0, edx = a, ecx = b
nm_decompose:
    cmp byte [r15 + S_SHAPER], 1
    jne uc_decompose
    cmp edi, 0x0931
    je .no
    cmp edi, 0x09DC
    je .no
    cmp edi, 0x09DD
    je .no
    cmp edi, 0x0B94
    je .no
    jmp uc_decompose
.no:
    xor eax, eax
    ret

; the shaper's composition: edi = a, esi = b -> eax = ab, 0 none
nm_compose:
    cmp byte [r15 + S_SHAPER], 1
    jne uc_compose
    push rdi
    push rsi
    sub rsp, 8
    call ucd_gc
    mov edi, eax
    call uc_is_mark_gc
    add rsp, 8
    pop rsi
    pop rdi
    test eax, eax
    jnz .no
    cmp edi, 0x09AF
    jne uc_compose
    cmp esi, 0x09BC
    jne uc_compose
    mov eax, 0x09DF
    ret
.no:
    xor eax, eax
    ret

; the current record's glyph set, then on to the output: esi = glyph
nm_next_char:
    mov eax, [r15 + S_IDX]
    shl rax, 5
    add rax, [r15 + S_INFO]
    mov [rax + GI_GLYPH], esi
    jmp buf_next_glyph

; a copy of the current record as another character to the output: edi = u,
;   esi = glyph
nm_output_char:
    push rbx
    push r12
    push r13
    mov r12d, edi
    mov r13d, esi
    call buf_out_slot
    mov rbx, rdi
    mov esi, [r15 + S_IDX]
    shl rsi, 5
    add rsi, [r15 + S_INFO]
    movdqu xmm0, [rsi]
    movdqu xmm1, [rsi + 16]
    movdqu [rbx], xmm0
    movdqu [rbx + 16], xmm1
    mov [rbx + GI_GLYPH], r13d
    mov rdi, rbx
    mov esi, r12d
    call uc_set_props
    pop r13
    pop r12
    pop rbx
    ret

; nm_decomp — edi = shortest, esi = ab -> eax = characters written (0: none)
nm_decomp:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    sub rsp, 16
    mov ebp, edi                        ; shortest
    mov edi, esi
    call nm_decompose
    test eax, eax
    jz .zero
    mov r12d, edx                       ; a
    mov r13d, ecx                       ; b
    xor r14d, r14d                      ; b's glyph
    test r13d, r13d
    jz .a
    mov edi, r13d
    call norm_glyph
    test eax, eax
    jz .zero
    mov r14d, eax
.a:
    mov edi, r12d
    call norm_glyph
    mov ebx, eax                        ; a's glyph (0: none)
    test ebp, ebp
    jz .deeper
    test ebx, ebx
    jnz .write_a
.deeper:
    mov edi, ebp
    mov esi, r12d
    call nm_decomp
    test eax, eax
    jz .flat
    mov [rsp], eax
    test r13d, r13d
    jz .ret_saved
    mov edi, r13d
    mov esi, r14d
    call nm_output_char
    mov eax, [rsp]
    inc eax
    jmp .out
.ret_saved:
    mov eax, [rsp]
    jmp .out
.flat:
    test ebx, ebx
    jz .zero
.write_a:
    mov edi, r12d
    mov esi, ebx
    call nm_output_char
    mov eax, 1
    test r13d, r13d
    jz .out
    mov edi, r13d
    mov esi, r14d
    call nm_output_char
    mov eax, 2
    jmp .out
.zero:
    xor eax, eax
.out:
    add rsp, 16
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; nm_decompose_current — edi = shortest
nm_decompose_current:
    push rbx
    push r12
    push r13
    mov r12d, edi
    mov eax, [r15 + S_IDX]
    shl rax, 5
    add rax, [r15 + S_INFO]
    mov r13d, [rax + GI_CP]
    mov edi, r13d
    call norm_glyph
    mov ebx, eax
    test r12d, r12d
    jz .decomp
    test ebx, ebx
    jnz .next
.decomp:
    mov edi, r12d
    mov esi, r13d
    call nm_decomp
    test eax, eax
    jz .whole
    call buf_skip_glyph
    jmp .out
.whole:
    test ebx, ebx
    jnz .next
    ; a space the font lacks: its space glyph
    mov eax, [r15 + S_IDX]
    shl rax, 5
    add rax, [r15 + S_INFO]
    cmp byte [rax + GI_GC], GC_ZS
    jne .hyphen
    mov edi, r13d
    call uc_space_type
    test eax, eax
    jz .hyphen
    push rax
    sub rsp, 8
    mov edi, 0x20
    call norm_glyph
    add rsp, 8
    pop rcx
    test eax, eax
    jz .hyphen
    mov ebx, eax
    mov eax, [r15 + S_IDX]
    shl rax, 5
    add rax, [r15 + S_INFO]
    mov [rax + GI_SPACE], cl
    jmp .next
.hyphen:
    cmp r13d, 0x2011
    jne .next
    mov edi, 0x2010
    call norm_glyph
    mov ebx, eax
.next:
    mov esi, ebx
    call nm_next_char
.out:
    pop r13
    pop r12
    pop rbx
    ret

; the current record with its own nominal glyph to the output
nm_next_nominal:
    mov eax, [r15 + S_IDX]
    shl rax, 5
    add rax, [r15 + S_INFO]
    mov edi, [rax + GI_CP]
    call norm_glyph
    mov esi, eax
    jmp nm_next_char

; is record i (edi) a variation selector -> eax
nm_is_vs_at:
    mov eax, edi
    shl rax, 5
    add rax, [r15 + S_INFO]
    mov edi, [rax + GI_CP]
    jmp uc_is_vs

; is record i (edi) a mark -> eax
nm_is_mark_at:
    mov eax, edi
    shl rax, 5
    add rax, [r15 + S_INFO]
    movzx edi, byte [rax + GI_GC]
    jmp uc_is_mark_gc

; ----------------------------------------------------------------------------
; norm_run
; ----------------------------------------------------------------------------
global norm_run
norm_run:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    xor ebp, ebp                        ; shortest unless the Indic shaper
    cmp byte [r15 + S_SHAPER], 1
    je .mode
    inc ebp
.mode:
    call buf_clear_output
    mov r12d, [r15 + S_LEN]             ; count
    mov r13d, 1                         ; all simple
.cluster:
    cmp [r15 + S_IDX], r12d
    jae .decomposed
    ; the run of non-marks, less one base for the marks after it
    mov ebx, [r15 + S_IDX]
    inc ebx
.find_mark:
    cmp ebx, r12d
    jae .simple
    mov edi, ebx
    call nm_is_mark_at
    test eax, eax
    jnz .found_mark
    inc ebx
    jmp .find_mark
.found_mark:
    dec ebx
.simple:
    cmp [r15 + S_IDX], ebx
    jae .simple_done
    mov edi, ebp
    call nm_decompose_current
    jmp .simple
.simple_done:
    cmp [r15 + S_IDX], r12d
    jae .decomposed
    xor r13d, r13d
    ; a base and its marks
    mov ebx, [r15 + S_IDX]
    inc ebx
.marks:
    cmp ebx, r12d
    jae .have_marks
    mov edi, ebx
    call nm_is_mark_at
    test eax, eax
    jz .have_marks
    inc ebx
    jmp .marks
.have_marks:
    ; a variation selector among them?
    mov r14d, [r15 + S_IDX]
.vs_scan:
    cmp r14d, ebx
    jae .multi
    mov edi, r14d
    call nm_is_vs_at
    test eax, eax
    jnz .vs_cluster
    inc r14d
    jmp .vs_scan
.multi:
    cmp [r15 + S_IDX], ebx
    jae .cluster
    xor edi, edi
    call nm_decompose_current
    jmp .multi
.vs_cluster:
    lea r14d, [rbx - 1]                 ; end - 1
.vs_loop:
    cmp [r15 + S_IDX], r14d
    jae .vs_last
    mov edi, [r15 + S_IDX]
    inc edi
    call nm_is_vs_at
    test eax, eax
    jz .vs_plain
    mov eax, [r15 + S_IDX]
    shl rax, 5
    add rax, [r15 + S_INFO]
    mov edi, [rax + GI_CP]
    mov esi, [rax + 32 + GI_CP]
    call norm_variation
    test eax, eax
    jz .vs_nominal
    mov esi, eax
    call nm_next_char
    call buf_skip_glyph
    jmp .vs_after
.vs_nominal:
    call nm_next_nominal
.vs_after:
    mov eax, [r15 + S_IDX]
    cmp eax, ebx
    jae .vs_loop
    mov edi, eax
    call nm_is_vs_at
    test eax, eax
    jz .vs_loop
    call nm_next_nominal
    jmp .vs_after
.vs_plain:
    call nm_next_nominal
    jmp .vs_loop
.vs_last:
    cmp [r15 + S_IDX], ebx
    jae .cluster
    call nm_next_nominal
    jmp .cluster
.decomposed:
    call buf_sync
    test r13d, r13d
    jnz .cgj
    ; marks in combining-class order
    xor ebx, ebx
.reorder:
    mov r12d, [r15 + S_LEN]
    cmp ebx, r12d
    jae .reordered
    mov rax, [r15 + S_INFO]
    mov ecx, ebx
    shl rcx, 5
    cmp byte [rax + rcx + GI_MCC], 0
    jne .run
    inc ebx
    jmp .reorder
.run:
    lea r14d, [rbx + 1]
.run_end:
    cmp r14d, r12d
    jae .run_have
    mov ecx, r14d
    shl rcx, 5
    cmp byte [rax + rcx + GI_MCC], 0
    je .run_have
    inc r14d
    jmp .run_end
.run_have:
    mov eax, r14d
    sub eax, ebx
    cmp eax, 32
    ja .run_next
    mov esi, ebx
    mov edx, r14d
    mov ecx, GI_MCC
    call buf_sort
.run_next:
    mov ebx, r14d
    jmp .reorder
.reordered:
    call nm_cgj
    ; compose
    call buf_clear_output
    mov r12d, [r15 + S_LEN]
    xor ebx, ebx                        ; starter (output position)
    call buf_next_glyph
.compose:
    cmp [r15 + S_IDX], r12d
    jae .composed
    mov eax, [r15 + S_IDX]
    shl rax, 5
    add rax, [r15 + S_INFO]
    mov r14, rax                        ; cur
    movzx edi, byte [rax + GI_GC]
    call uc_is_mark_gc
    test eax, eax
    jz .no_compose
    mov eax, [r15 + S_OUTLEN]
    dec eax
    cmp ebx, eax
    je .try
    shl rax, 5
    add rax, [r15 + S_OUT]
    mov cl, [rax + GI_MCC]
    cmp cl, [r14 + GI_MCC]
    jae .no_compose
.try:
    mov eax, ebx
    shl rax, 5
    add rax, [r15 + S_OUT]
    mov edi, [rax + GI_CP]
    mov esi, [r14 + GI_CP]
    call nm_compose
    test eax, eax
    jz .no_compose
    mov ebp, eax                        ; composed
    mov edi, eax
    call norm_glyph
    test eax, eax
    jz .no_compose_restore
    push rax
    sub rsp, 8
    call buf_next_glyph
    mov esi, ebx
    mov edx, [r15 + S_OUTLEN]
    call buf_merge_out_clusters
    dec dword [r15 + S_OUTLEN]
    add rsp, 8
    pop rax
    mov edi, ebx
    shl rdi, 5
    add rdi, [r15 + S_OUT]
    mov [rdi + GI_GLYPH], eax
    mov esi, ebp
    call uc_set_props
    jmp .compose
.no_compose_restore:
.no_compose:
    call buf_next_glyph
    mov eax, [r15 + S_OUTLEN]
    dec eax
    mov ecx, eax
    shl rcx, 5
    add rcx, [r15 + S_OUT]
    cmp byte [rcx + GI_MCC], 0
    jne .compose
    mov ebx, eax
    jmp .compose
.composed:
    call buf_sync
    jmp .out
.cgj:
    call nm_cgj
.out:
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; a combining grapheme joiner between marks it keeps apart stays hidden;
; elsewhere lookups see it
nm_cgj:
    mov rax, [r15 + S_INFO]
    mov ecx, 1
.loop:
    lea edx, [rcx + 1]
    cmp edx, [r15 + S_LEN]
    jae .done
    mov edx, ecx
    shl rdx, 5
    cmp dword [rax + rdx + GI_CP], 0x034F
    jne .next
    mov r8b, [rax + rdx + 32 + GI_MCC]
    test r8b, r8b
    jz .unhide
    cmp [rax + rdx - 32 + GI_MCC], r8b
    ja .next
.unhide:
    and byte [rax + rdx + GI_UF], ~UF_HIDDEN
.next:
    inc ecx
    jmp .loop
.done:
    ret
