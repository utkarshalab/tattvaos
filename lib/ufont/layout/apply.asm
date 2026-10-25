; =============================================================================
; Utkarsha OS — lib/ufont/layout/apply.asm
; =============================================================================
; Applying GSUB / GPOS lookups to the buffer, as HarfBuzz does:
;
;   ap_run_table(edi = 0 GSUB / 1 GPOS)   every stage's lookups, each over the
;       run (GSUB forward through the output side, reverse-chaining lookups
;       backward in place, GPOS in place), the stage's pause after it
;   ap_apply_subtables(rdi = lookup)  -> eax 1 when a subtable applied at idx
;   ap_check(rsi = record, edi = match props) -> eax 1 / 0 (skipped by the
;       lookup flags: ignored classes, mark filtering set, attachment type)
;   sk_init / sk_reset / sk_check / sk_next / sk_prev / sk_may_skip
;       the skipping iterator (SK_* on the caller's stack)
;   ap_match_input, ap_match_backtrack, ap_match_lookahead, ap_ligate,
;   ap_apply_records, ap_context      matching sequences and contexts
;   ap_set_class, ap_replace_glyph, ap_replace_inplace, ap_replace_lig,
;   ap_output_component               substitutions that keep glyph props
;   ap_would_apply(edi = lookup index, rsi = glyphs (u32), edx = count,
;       ecx = zero context) -> eax 1 / 0   would a GSUB lookup apply to
;       exactly these glyphs (flags and context ignored)
; =============================================================================

%include "ufont.inc"
%include "shape.inc"

extern otl_table
extern otl_lookup
extern otl_glyph_props
extern otl_mark_set_covers
extern ot_coverage
extern ot_class
extern ot_off16
extern buf_cur
extern buf_clear_output
extern buf_sync
extern buf_next_glyph
extern buf_replace_glyph
extern buf_output_glyph
extern buf_move_to
extern buf_merge_clusters
extern buf_next_serial
extern gsub_apply
extern gpos_apply

section .text

; ----------------------------------------------------------------------------
; ap_check — rsi = record, edi = match props -> eax 1 / 0
; ----------------------------------------------------------------------------
global ap_check
ap_check:
    movzx eax, word [rsi + GI_PROPS]
    mov ecx, eax
    and ecx, edi
    test ecx, LF_IGNORE_FLAGS
    jnz .no
    test eax, GP_MARK
    jz .yes
    test edi, LF_FILTER_SET
    jnz .set
    test edi, LF_ATTACH_TYPE
    jz .yes
    mov ecx, edi
    and ecx, LF_ATTACH_TYPE
    and eax, LF_ATTACH_TYPE
    cmp eax, ecx
    sete al
    movzx eax, al
    ret
.set:
    sub rsp, 8
    shr edi, 16
    mov esi, [rsi + GI_GLYPH]
    call otl_mark_set_covers
    add rsp, 8
    ret
.yes:
    mov eax, 1
    ret
.no:
    xor eax, eax
    ret

; ----------------------------------------------------------------------------
; the skipping iterator
; ----------------------------------------------------------------------------
; sk_init — rdi = SK, esi = context match (1: backtrack / lookahead)
global sk_init
sk_init:
    xor eax, eax
    cmp byte [r15 + S_GPOS], 0
    je .gsub
    or eax, SKF_ZWNJ | SKF_HIDDEN
    jmp .zwj
.gsub:
    test esi, esi
    jz .zwj
    cmp byte [r15 + S_AZWNJ], 0
    je .zwj
    or eax, SKF_ZWNJ
.zwj:
    test esi, esi
    jnz .zwj_yes
    cmp byte [r15 + S_AZWJ], 0
    je .ps
.zwj_yes:
    or eax, SKF_ZWJ
.ps:
    cmp byte [r15 + S_GPOS], 0
    jne .flags
    cmp byte [r15 + S_PERSYL], 0
    je .flags
    or eax, SKF_PERSYL
.flags:
    mov [rdi + SK_FLAGS], eax
    mov eax, -1
    test esi, esi
    jnz .mask
    mov eax, [r15 + S_LMASK]
.mask:
    mov [rdi + SK_MASK], eax
    mov eax, [r15 + S_LPROPS]
    mov [rdi + SK_PROPS], eax
    mov dword [rdi + SK_SYL], 0
    mov dword [rdi + SK_MTYPE], MT_NONE
    mov rax, [r15 + S_INFO]
    mov [rdi + SK_ARR], rax
    ret

; sk_reset — rdi = SK, esi = start, edx = items
global sk_reset
sk_reset:
    mov [rdi + SK_IDX], esi
    mov [rdi + SK_NUM], edx
    mov eax, [r15 + S_LEN]
    mov [rdi + SK_END], eax
    xor eax, eax
    cmp esi, [r15 + S_IDX]
    jne .syl
    cmp esi, [r15 + S_LEN]
    jae .syl
    mov rcx, [r15 + S_INFO]
    mov edx, esi
    shl rdx, 5
    movzx eax, byte [rcx + rdx + GI_SYL]
.syl:
    mov [rdi + SK_SYL], eax
    ret

; sk_matcher — rdi = SK, rsi = MB: matched against it
global sk_matcher
sk_matcher:
    mov eax, [rsi + MB_TYPE]
    mov [rdi + SK_MTYPE], eax
    mov rax, [rsi + MB_DATA]
    mov [rdi + SK_MDATA], rax
    mov rax, [rsi + MB_BASE]
    mov [rdi + SK_MBASE], rax
    ret

; sk_may_skip — rdi = SK, rsi = record -> eax 0 no, 1 yes, 2 maybe
global sk_may_skip
sk_may_skip:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    mov edi, [rbx + SK_PROPS]
    call ap_check
    test eax, eax
    jz .yes
    xor eax, eax
    movzx ecx, byte [r12 + GI_UF]
    test ecx, UF_IGN
    jz .out
    test word [r12 + GI_PROPS], GP_SUBSTITUTED
    jnz .out
    mov edx, [rbx + SK_FLAGS]
    test ecx, UF_HIDDEN
    jz .zwnj
    test edx, SKF_HIDDEN
    jz .out
.zwnj:
    test ecx, UF_ZWNJ
    jz .zwj
    test edx, SKF_ZWNJ
    jz .out
.zwj:
    test ecx, UF_ZWJ
    jz .maybe
    test edx, SKF_ZWJ
    jz .out
.maybe:
    mov eax, 2
    jmp .out
.yes:
    mov eax, 1
.out:
    add rsp, 8
    pop r12
    pop rbx
    ret

; sk_value — rdi = SK, rsi = record, edx = item -> eax 1 matches the item
sk_value:
    push rbx
    mov rbx, rsi
    mov rax, [rdi + SK_MDATA]
    BE16 r8d, [rax + rdx * 2]           ; the value
    mov eax, [rdi + SK_MTYPE]
    cmp eax, MT_GLYPH
    jne .class
    xor eax, eax
    cmp r8d, [rbx + GI_GLYPH]
    sete al
    jmp .out
.class:
    cmp eax, MT_CLASS
    jne .coverage
    push r8
    mov rdi, [rdi + SK_MBASE]
    mov rsi, [r15 + S_TEND]
    mov edx, [rbx + GI_GLYPH]
    call ot_class
    pop r8
    cmp eax, r8d
    sete al
    movzx eax, al
    jmp .out
.coverage:
    xor eax, eax
    test r8d, r8d
    jz .out
    mov rdi, [rdi + SK_MBASE]
    add rdi, r8
    mov rsi, [r15 + S_TEND]
    cmp rdi, rsi
    jae .no
    mov edx, [rbx + GI_GLYPH]
    sub rsp, 8
    call ot_coverage
    add rsp, 8
    not eax
    test eax, eax
    setnz al
    movzx eax, al
    jmp .out
.no:
    xor eax, eax
.out:
    pop rbx
    ret

; sk_check — rdi = SK, rsi = record, edx = item -> eax 0 skip, 1 match,
;   2 no match
global sk_check
sk_check:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    call sk_may_skip
    cmp eax, 1
    je .skip
    mov r14d, eax                       ; 0 no, 2 maybe
    ; may it match?
    mov eax, [r12 + GI_MASK]
    test eax, [rbx + SK_MASK]
    jz .no_match
    test dword [rbx + SK_FLAGS], SKF_PERSYL
    jz .value
    mov eax, [rbx + SK_SYL]
    test eax, eax
    jz .value
    movzx ecx, byte [r12 + GI_SYL]
    cmp eax, ecx
    jne .no_match
.value:
    cmp dword [rbx + SK_MTYPE], MT_NONE
    je .maybe
    mov rdi, rbx
    mov rsi, r12
    mov edx, r13d
    call sk_value
    test eax, eax
    jnz .match
.no_match:
    test r14d, r14d
    jz .nomatch
    jmp .skip
.maybe:
    test r14d, r14d
    jz .match
.skip:
    xor eax, eax
    jmp .out
.match:
    mov eax, 1
    jmp .out
.nomatch:
    mov eax, 2
.out:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; sk_next — rdi = SK, esi = item -> eax 1 matched (SK_IDX on it) / 0
global sk_next
sk_next:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    mov r12d, esi
.loop:
    mov eax, [rbx + SK_END]
    sub eax, [rbx + SK_NUM]             ; stop
    cmp [rbx + SK_IDX], eax
    jge .fail
    inc dword [rbx + SK_IDX]
    mov esi, [rbx + SK_IDX]
    shl rsi, 5
    add rsi, [r15 + S_INFO]
    mov rdi, rbx
    mov edx, r12d
    call sk_check
    cmp eax, 1
    je .match
    cmp eax, 2
    je .fail
    jmp .loop
.match:
    dec dword [rbx + SK_NUM]
    mov eax, 1
    jmp .out
.fail:
    xor eax, eax
.out:
    add rsp, 8
    pop r12
    pop rbx
    ret

; sk_prev — rdi = SK, esi = item: walks SK_ARR -> eax 1 / 0
global sk_prev
sk_prev:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    mov r12d, esi
.loop:
    mov eax, [rbx + SK_NUM]
    dec eax                             ; stop
    cmp [rbx + SK_IDX], eax
    jle .fail
    dec dword [rbx + SK_IDX]
    movsxd rsi, dword [rbx + SK_IDX]
    shl rsi, 5
    add rsi, [rbx + SK_ARR]
    mov rdi, rbx
    mov edx, r12d
    call sk_check
    cmp eax, 1
    je .match
    cmp eax, 2
    je .fail
    jmp .loop
.match:
    dec dword [rbx + SK_NUM]
    mov eax, 1
    jmp .out
.fail:
    xor eax, eax
.out:
    add rsp, 8
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------------
; substitutions keeping glyph props
; ----------------------------------------------------------------------------
; ap_set_class — rdi = record, esi = glyph, edx = class guess, ecx = 1
;   ligature / 2 component
global ap_set_class
ap_set_class:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    movzx eax, word [rbx + GI_PROPS]
    or eax, GP_SUBSTITUTED
    test ecx, 1
    jz .comp
    or eax, GP_LIGATED
    and eax, ~GP_MULTIPLIED
.comp:
    test ecx, 2
    jz .classes
    or eax, GP_MULTIPLIED
.classes:
    cmp qword [r15 + S_CLASSDEF], 0
    je .guess
    and eax, GP_PRESERVE
    mov r12d, eax
    mov edi, esi
    call otl_glyph_props
    or eax, r12d
    jmp .set
.guess:
    test edx, edx
    jz .set
    and eax, GP_PRESERVE
    or eax, edx
.set:
    mov [rbx + GI_PROPS], ax
    pop r13
    pop r12
    pop rbx
    ret

; esi = glyph
global ap_replace_glyph
ap_replace_glyph:
    push rbx
    mov ebx, esi
    call buf_cur
    mov rdi, rax
    mov esi, ebx
    xor edx, edx
    xor ecx, ecx
    call ap_set_class
    mov esi, ebx
    call buf_replace_glyph
    pop rbx
    ret

global ap_replace_inplace
ap_replace_inplace:
    push rbx
    mov ebx, esi
    call buf_cur
    mov rdi, rax
    mov esi, ebx
    xor edx, edx
    xor ecx, ecx
    call ap_set_class
    call buf_cur
    mov [rax + GI_GLYPH], ebx
    pop rbx
    ret

; esi = glyph, edx = class guess
global ap_replace_lig
ap_replace_lig:
    push rbx
    mov ebx, esi
    push rdx
    call buf_cur
    pop rdx
    mov rdi, rax
    mov esi, ebx
    mov ecx, 1
    call ap_set_class
    mov esi, ebx
    call buf_replace_glyph
    pop rbx
    ret

global ap_output_component
ap_output_component:
    push rbx
    mov ebx, esi
    push rdx
    call buf_cur
    pop rdx
    mov rdi, rax
    mov esi, ebx
    mov ecx, 2
    call ap_set_class
    mov esi, ebx
    call buf_output_glyph
    pop rbx
    ret

; ligature properties of the record at rsi
%macro LIG_ID 2                         ; %1 = 32-bit dest, %2 = record
    movzx %1, byte [%2 + GI_LIG]
    shr %1, 5
%endmacro
; component: 0 for a ligature base
%macro LIG_COMP 2
    movzx %1, byte [%2 + GI_LIG]
    test %1, 0x10
    jz %%c
    xor %1, %1
    jmp %%d
%%c:
    and %1, 0x0F
%%d:
%endmacro
%macro NUM_COMPS 2
    mov %1, 1
    test word [%2 + GI_PROPS], GP_LIGATURE
    jz %%d
    test byte [%2 + GI_LIG], 0x10
    jz %%d
    movzx %1, byte [%2 + GI_LIG]
    and %1, 0x0F
%%d:
%endmacro

; ----------------------------------------------------------------------------
; ap_match_input — rdi = MB of the items after the first, esi = count (with
;   the first), rdx = match positions (u32 x count) -> eax 1 / 0, ecx = end,
;   edx = components in all
; ----------------------------------------------------------------------------
%define MI_SK      0
%define MI_MP      56
%define MI_COUNT   64
%define MI_TOTAL   68
%define MI_FID     72                   ; first's ligature id
%define MI_FCOMP   76
%define MI_LIGBASE 80                   ; 0 not checked, 1 may not skip, 2 may skip
%define MI_I       84
%define MI_SIZE    96

global ap_match_input
ap_match_input:
    push rbx
    push r12
    push r13
    sub rsp, MI_SIZE
    mov [rsp + MI_MP], rdx
    mov [rsp + MI_COUNT], esi
    mov rbx, rdi
    lea rdi, [rsp + MI_SK]
    xor esi, esi
    call sk_init
    lea rdi, [rsp + MI_SK]
    mov esi, [r15 + S_IDX]
    mov edx, [rsp + MI_COUNT]
    dec edx
    call sk_reset
    lea rdi, [rsp + MI_SK]
    mov rsi, rbx
    call sk_matcher
    mov dword [rsp + MI_TOTAL], 0
    mov dword [rsp + MI_LIGBASE], 0
    call buf_cur
    LIG_ID ecx, rax
    mov [rsp + MI_FID], ecx
    LIG_COMP ecx, rax
    mov [rsp + MI_FCOMP], ecx
    mov dword [rsp + MI_I], 1
.item:
    mov eax, [rsp + MI_I]
    cmp eax, [rsp + MI_COUNT]
    jae .matched
    lea rdi, [rsp + MI_SK]
    lea esi, [rax - 1]
    call sk_next
    test eax, eax
    jz .fail
    mov eax, [rsp + MI_I]
    mov ecx, [rsp + MI_SK + SK_IDX]
    mov rdx, [rsp + MI_MP]
    mov [rdx + rax * 4], ecx
    mov r12, rcx
    shl r12, 5
    add r12, [r15 + S_INFO]             ; the record
    LIG_ID r8d, r12
    LIG_COMP r9d, r12
    mov eax, [rsp + MI_FID]
    test eax, eax
    jz .not_lig
    cmp dword [rsp + MI_FCOMP], 0
    je .not_lig
    cmp eax, r8d
    jne .other_comp
    cmp [rsp + MI_FCOMP], r9d
    je .count
.other_comp:
    cmp dword [rsp + MI_LIGBASE], 0
    jne .ligbase
    ; is the ligature's base skippable?
    mov dword [rsp + MI_LIGBASE], 1
    xor ecx, ecx
    cmp byte [r15 + S_HAVEOUT], 0
    je .ligbase
    mov ecx, [r15 + S_OUTLEN]
    mov r10, [r15 + S_OUT]
.lb:
    test ecx, ecx
    jz .ligbase
    mov edx, ecx
    shl rdx, 5
    LIG_ID eax, r10 + rdx - 32
    cmp eax, [rsp + MI_FID]
    jne .ligbase
    LIG_COMP eax, r10 + rdx - 32
    dec ecx
    test eax, eax
    jnz .lb
    ; found the base at ecx
    mov esi, ecx
    shl rsi, 5
    add rsi, r10
    lea rdi, [rsp + MI_SK]
    call sk_may_skip
    cmp eax, 1
    jne .ligbase
    mov dword [rsp + MI_LIGBASE], 2
.ligbase:
    cmp dword [rsp + MI_LIGBASE], 1
    je .fail
    jmp .count
.not_lig:
    test r8d, r8d
    jz .count
    test r9d, r9d
    jz .count
    cmp r8d, [rsp + MI_FID]
    jne .fail
.count:
    NUM_COMPS eax, r12
    add [rsp + MI_TOTAL], eax
    inc dword [rsp + MI_I]
    jmp .item
.matched:
    call buf_cur
    NUM_COMPS ecx, rax
    add [rsp + MI_TOTAL], ecx
    mov rdx, [rsp + MI_MP]
    mov eax, [r15 + S_IDX]
    mov [rdx], eax
    mov ecx, [rsp + MI_SK + SK_IDX]
    inc ecx
    mov edx, [rsp + MI_TOTAL]
    mov eax, 1
    jmp .out
.fail:
    xor eax, eax
.out:
    add rsp, MI_SIZE
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------------
; ap_match_backtrack — rdi = MB -> eax 1 / 0
; ap_match_lookahead — rdi = MB, esi = start (after the input) -> eax 1 / 0
; ----------------------------------------------------------------------------
global ap_match_backtrack
ap_match_backtrack:
    push rbx
    push r12
    sub rsp, SK_SIZE + 16
    mov rbx, rdi
    mov rdi, rsp
    mov esi, 1
    call sk_init
    mov rax, [r15 + S_INFO]
    mov ecx, [r15 + S_IDX]
    cmp byte [r15 + S_HAVEOUT], 0
    je .arr
    mov rax, [r15 + S_OUT]
    mov ecx, [r15 + S_OUTLEN]
.arr:
    mov [rsp + SK_ARR], rax
    mov rdi, rsp
    mov esi, ecx
    mov edx, [rbx + MB_COUNT]
    push rcx
    sub rsp, 8
    call sk_reset
    add rsp, 8
    pop rcx
    mov [rsp + SK_IDX], ecx
    mov rdi, rsp
    mov rsi, rbx
    call sk_matcher
    xor r12d, r12d
.item:
    cmp r12d, [rbx + MB_COUNT]
    jae .yes
    mov rdi, rsp
    mov esi, r12d
    call sk_prev
    test eax, eax
    jz .no
    inc r12d
    jmp .item
.yes:
    mov eax, 1
    jmp .out
.no:
    xor eax, eax
.out:
    add rsp, SK_SIZE + 16
    pop r12
    pop rbx
    ret

global ap_match_lookahead
ap_match_lookahead:
    push rbx
    push r12
    sub rsp, SK_SIZE + 16
    mov rbx, rdi
    mov r12d, esi
    mov rdi, rsp
    mov esi, 1
    call sk_init
    mov rdi, rsp
    lea esi, [r12 - 1]
    mov edx, [rbx + MB_COUNT]
    call sk_reset
    mov rdi, rsp
    mov rsi, rbx
    call sk_matcher
    xor r12d, r12d
.item:
    cmp r12d, [rbx + MB_COUNT]
    jae .yes
    mov rdi, rsp
    mov esi, r12d
    call sk_next
    test eax, eax
    jz .no
    inc r12d
    jmp .item
.yes:
    mov eax, 1
    jmp .out
.no:
    xor eax, eax
.out:
    add rsp, SK_SIZE + 16
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------------
; ap_ligate — edi = count, rsi = match positions, edx = match end, ecx =
;   ligature glyph, r8d = components in all
; ----------------------------------------------------------------------------
%define LG_COUNT  0
%define LG_END    4
%define LG_GLYPH  8
%define LG_TOTAL  12
%define LG_MP     16
%define LG_BASE   24                    ; is a base ligature
%define LG_MARK   28                    ; is a mark ligature
%define LG_ID     32
%define LG_LASTID 36
%define LG_LASTN  40
%define LG_SOFAR  44
%define LG_I      48
%define LG_SIZE   64

global ap_ligate
ap_ligate:
    push rbx
    push r12
    push r13
    sub rsp, LG_SIZE
    mov [rsp + LG_COUNT], edi
    mov [rsp + LG_MP], rsi
    mov [rsp + LG_END], edx
    mov [rsp + LG_GLYPH], ecx
    mov [rsp + LG_TOTAL], r8d
    mov esi, [r15 + S_IDX]
    call buf_merge_clusters
    ; a base or mark ligature: all components after the first are marks
    mov rbx, [rsp + LG_MP]
    mov r8, [r15 + S_INFO]
    mov eax, [rbx]
    shl rax, 5
    movzx ecx, word [r8 + rax + GI_PROPS]
    xor edx, edx
    test ecx, GP_BASE
    setnz dl
    mov [rsp + LG_BASE], edx
    xor edx, edx
    test ecx, GP_MARK
    setnz dl
    mov [rsp + LG_MARK], edx
    mov ecx, 1
.marks:
    cmp ecx, [rsp + LG_COUNT]
    jae .kind
    mov eax, [rbx + rcx * 4]
    shl rax, 5
    test word [r8 + rax + GI_PROPS], GP_MARK
    jnz .marks_next
    mov dword [rsp + LG_BASE], 0
    mov dword [rsp + LG_MARK], 0
    jmp .kind
.marks_next:
    inc ecx
    jmp .marks
.kind:
    xor r12d, r12d                      ; class guess
    mov dword [rsp + LG_ID], 0
    mov eax, [rsp + LG_BASE]
    or eax, [rsp + LG_MARK]
    jnz .first
    mov r12d, GP_LIGATURE
.serial:
    call buf_next_serial
    and eax, 7
    jz .serial
    mov [rsp + LG_ID], eax
.first:
    call buf_cur
    mov r13, rax
    LIG_ID ecx, r13
    mov [rsp + LG_LASTID], ecx
    NUM_COMPS ecx, r13
    mov [rsp + LG_LASTN], ecx
    mov [rsp + LG_SOFAR], ecx
    test r12d, r12d
    jz .replace
    mov eax, [rsp + LG_ID]
    shl eax, 5
    or eax, 0x10
    mov ecx, [rsp + LG_TOTAL]
    and ecx, 0x0F
    or eax, ecx
    mov [r13 + GI_LIG], al
    cmp byte [r13 + GI_GC], GC_MN
    jne .replace
    mov byte [r13 + GI_GC], GC_LO
.replace:
    mov esi, [rsp + LG_GLYPH]
    mov edx, r12d
    call ap_replace_lig
    mov dword [rsp + LG_I], 1
.comp:
    mov ecx, [rsp + LG_I]
    cmp ecx, [rsp + LG_COUNT]
    jae .after
.between:
    mov rbx, [rsp + LG_MP]
    mov ecx, [rsp + LG_I]
    mov eax, [rbx + rcx * 4]
    cmp [r15 + S_IDX], eax
    jae .component
    test r12d, r12d
    jz .pass
    call buf_cur
    LIG_COMP ecx, rax
    test ecx, ecx
    jnz .have_comp
    mov ecx, [rsp + LG_LASTN]
.have_comp:
    mov edx, [rsp + LG_LASTN]
    cmp ecx, edx
    jbe .min
    mov ecx, edx
.min:
    add ecx, [rsp + LG_SOFAR]
    sub ecx, edx
    and ecx, 0x0F
    mov edx, [rsp + LG_ID]
    shl edx, 5
    or ecx, edx
    mov [rax + GI_LIG], cl
.pass:
    call buf_next_glyph
    jmp .between
.component:
    call buf_cur
    LIG_ID ecx, rax
    mov [rsp + LG_LASTID], ecx
    NUM_COMPS ecx, rax
    mov [rsp + LG_LASTN], ecx
    add [rsp + LG_SOFAR], ecx
    inc dword [r15 + S_IDX]             ; the component itself goes
    inc dword [rsp + LG_I]
    jmp .comp
.after:
    ; marks after the last component follow the ligature's numbering
    cmp dword [rsp + LG_MARK], 0
    jne .out
    cmp dword [rsp + LG_LASTID], 0
    je .out
    mov ecx, [r15 + S_IDX]
.follow:
    cmp ecx, [r15 + S_LEN]
    jae .out
    mov rax, rcx
    shl rax, 5
    add rax, [r15 + S_INFO]
    LIG_ID edx, rax
    cmp edx, [rsp + LG_LASTID]
    jne .out
    LIG_COMP edx, rax
    test edx, edx
    jz .out
    mov r8d, [rsp + LG_LASTN]
    cmp edx, r8d
    jbe .fmin
    mov edx, r8d
.fmin:
    add edx, [rsp + LG_SOFAR]
    sub edx, r8d
    and edx, 0x0F
    mov r8d, [rsp + LG_ID]
    shl r8d, 5
    or edx, r8d
    mov [rax + GI_LIG], dl
    inc ecx
    jmp .follow
.out:
    add rsp, LG_SIZE
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------------
; ap_recurse — edi = lookup index -> eax 1 applied / 0
; ----------------------------------------------------------------------------
global ap_recurse
ap_recurse:
    push rbx
    push r12
    sub rsp, 8
    cmp dword [r15 + S_NEST], 0
    je .no
    dec dword [r15 + S_OPS]
    js .no
    movzx edi, di
    mov esi, edi
    movzx edi, byte [r15 + S_GPOS]
    call otl_lookup
    test rax, rax
    jz .no
    mov rbx, rax
    dec dword [r15 + S_NEST]
    mov r12d, [r15 + S_LPROPS]
    mov rdi, rbx
    call ap_lookup_props
    mov [r15 + S_LPROPS], eax
    mov rdi, rbx
    call ap_apply_subtables
    mov [r15 + S_LPROPS], r12d
    inc dword [r15 + S_NEST]
    jmp .out
.no:
    xor eax, eax
.out:
    add rsp, 8
    pop r12
    pop rbx
    ret

; ap_lookup_props — rdi = lookup -> eax = flags (| filtering set << 16; the
;   set flag dropped when GDEF has no such set)
global ap_lookup_props
ap_lookup_props:
    BE16 eax, [rdi + 2]
    test eax, LF_FILTER_SET
    jz .out
    BE16 ecx, [rdi + 4]                 ; subtables
    lea rdx, [rdi + rcx * 2 + 8]
    cmp rdx, [r15 + S_TEND]
    ja .drop
    BE16 ecx, [rdi + rcx * 2 + 6]       ; the set
    cmp ecx, [r15 + S_NMARKSETS]
    jae .drop
    shl ecx, 16
    or eax, ecx
    ret
.drop:
    and eax, ~LF_FILTER_SET
.out:
    ret

; ap_subtable — rdi = lookup, esi = i -> rax = subtable (extensions
;   followed), edx = its type; rax 0 when out of bounds
global ap_subtable
ap_subtable:
    push rbx
    mov rbx, rdi
    BE16 r8d, [rbx]                     ; type
    BE16 ecx, [rbx + 4]
    cmp esi, ecx
    jae .none
    lea rax, [rbx + rsi * 2 + 8]
    cmp rax, [r15 + S_TEND]
    ja .none
    BE16 eax, [rbx + rsi * 2 + 6]
    test eax, eax
    jz .none
    add rax, rbx
    lea rcx, [rax + 2]
    cmp rcx, [r15 + S_TEND]
    ja .none
    mov ecx, 7                          ; extension type: 7 in GSUB, 9 in GPOS
    cmp byte [r15 + S_GPOS], 0
    je .ext
    mov ecx, 9
.ext:
    cmp r8d, ecx
    jne .have
    lea rcx, [rax + 8]
    cmp rcx, [r15 + S_TEND]
    ja .none
    BE16 r8d, [rax + 2]
    BE32 ecx, [rax + 4]
    add rax, rcx
    lea rcx, [rax + 2]
    cmp rcx, [r15 + S_TEND]
    ja .none
.have:
    mov edx, r8d
    pop rbx
    ret
.none:
    xor eax, eax
    xor edx, edx
    pop rbx
    ret

; ----------------------------------------------------------------------------
; ap_apply_subtables — rdi = lookup -> eax 1 / 0
; ----------------------------------------------------------------------------
global ap_apply_subtables
ap_apply_subtables:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    BE16 r12d, [rbx + 4]
    xor r13d, r13d
.sub:
    cmp r13d, r12d
    jae .no
    mov rdi, rbx
    mov esi, r13d
    call ap_subtable
    inc r13d
    test rax, rax
    jz .sub
    mov rdi, rax
    mov esi, edx
    cmp byte [r15 + S_GPOS], 0
    jne .gpos
    call gsub_apply
    jmp .done
.gpos:
    call gpos_apply
.done:
    test eax, eax
    jz .sub
    mov eax, 1
    jmp .out
.no:
    xor eax, eax
.out:
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------------
; ap_apply_records — edi = count, rsi = match positions, rdx = lookup records
;   (u16 sequence index, u16 lookup index), ecx = records, r8d = match end
; ----------------------------------------------------------------------------
%define AR_MP      0                    ; u32 x MAX_CONTEXT (own copy)
%define AR_COUNT   256
%define AR_END     260                  ; i32
%define AR_RECS    264
%define AR_NRECS   272
%define AR_R       276
%define AR_ORIG    280
%define AR_IDX     284
%define AR_SIZE    288

global ap_apply_records
ap_apply_records:
    push rbx
    push r12
    push r13
    sub rsp, AR_SIZE
    mov [rsp + AR_COUNT], edi
    mov [rsp + AR_RECS], rdx
    mov [rsp + AR_NRECS], ecx
    ; positions from the start of the output
    mov eax, [r15 + S_IDX]
    cmp byte [r15 + S_HAVEOUT], 0
    je .bl
    mov eax, [r15 + S_OUTLEN]
.bl:
    mov ecx, eax
    sub ecx, [r15 + S_IDX]              ; delta
    add r8d, ecx
    mov [rsp + AR_END], r8d
    xor edx, edx
.copy:
    cmp edx, edi
    jae .copied
    mov eax, [rsi + rdx * 4]
    add eax, ecx
    mov [rsp + rdx * 4], eax
    inc edx
    jmp .copy
.copied:
    mov dword [rsp + AR_R], 0
.rec:
    mov eax, [rsp + AR_R]
    cmp eax, [rsp + AR_NRECS]
    jae .done
    inc dword [rsp + AR_R]
    mov rdx, [rsp + AR_RECS]
    BE16 ebx, [rdx + rax * 4]           ; sequence index
    BE16 r12d, [rdx + rax * 4 + 2]      ; lookup
    cmp ebx, [rsp + AR_COUNT]
    jae .rec
    mov [rsp + AR_IDX], ebx
    call ar_total_len
    mov [rsp + AR_ORIG], eax
    cmp [rsp + rbx * 4], eax
    jae .rec
    mov esi, [rsp + rbx * 4]
    call buf_move_to
    mov edi, r12d
    call ap_recurse
    test eax, eax
    jz .rec
    call ar_total_len
    sub eax, [rsp + AR_ORIG]            ; delta
    jz .rec
    mov ebx, [rsp + AR_IDX]
    add [rsp + AR_END], eax
    mov ecx, [rsp + rbx * 4]
    cmp [rsp + AR_END], ecx
    jge .end_ok
    sub ecx, [rsp + AR_END]
    add eax, ecx
    mov ecx, [rsp + rbx * 4]
    mov [rsp + AR_END], ecx
.end_ok:
    lea r13d, [rbx + 1]                 ; next
    test eax, eax
    jle .shrink
    mov ecx, eax
    add ecx, [rsp + AR_COUNT]
    cmp ecx, MAX_CONTEXT
    ja .done
    jmp .shift
.shrink:
    mov ecx, r13d
    sub ecx, [rsp + AR_COUNT]
    cmp eax, ecx
    jge .shrink_ok
    mov eax, ecx
.shrink_ok:
    sub r13d, eax
.shift:
    ; mp[next + delta ..] = mp[next .. count]
    mov ecx, [rsp + AR_COUNT]
    sub ecx, r13d                       ; how many
    lea r8d, [r13 + rax]                ; to
    test eax, eax
    jle .forward_copy
    ; moving up: from the end
    dec ecx
.up:
    test ecx, ecx
    js .shifted
    lea r9d, [r13 + rcx]
    mov r10d, [rsp + r9 * 4]
    lea r9d, [r8 + rcx]
    mov [rsp + r9 * 4], r10d
    dec ecx
    jmp .up
.forward_copy:
    xor r9d, r9d
.down:
    cmp r9d, ecx
    jae .shifted
    lea r10d, [r13 + r9]
    mov r11d, [rsp + r10 * 4]
    lea r10d, [r8 + r9]
    mov [rsp + r10 * 4], r11d
    inc r9d
    jmp .down
.shifted:
    add r13d, eax                       ; next += delta
    add [rsp + AR_COUNT], eax
    ; fill the new entries
    lea ecx, [rbx + 1]
.fill:
    cmp ecx, r13d
    jae .fix
    mov edx, [rsp + rcx * 4 - 4]
    inc edx
    mov [rsp + rcx * 4], edx
    inc ecx
    jmp .fill
.fix:
    cmp r13d, [rsp + AR_COUNT]
    jae .rec
    add [rsp + r13 * 4], eax
    inc r13d
    jmp .fix
.done:
    mov esi, [rsp + AR_END]
    call buf_move_to
    add rsp, AR_SIZE
    pop r13
    pop r12
    pop rbx
    ret

; -> eax = backtrack length + lookahead length
ar_total_len:
    mov eax, [r15 + S_IDX]
    cmp byte [r15 + S_HAVEOUT], 0
    je .bl
    mov eax, [r15 + S_OUTLEN]
.bl:
    add eax, [r15 + S_LEN]
    sub eax, [r15 + S_IDX]
    ret

; ----------------------------------------------------------------------------
; ap_context_apply — rdi = context block (CB_*) -> eax 1 / 0
; ----------------------------------------------------------------------------
%define CB_BACK    0                    ; MB
%define CB_INPUT   24                   ; MB (items after the first)
%define CB_LOOK    48                   ; MB
%define CB_RECS    72                   ; lookup records
%define CB_NRECS   80
%define CB_SIZE    88

%define CA_MP      0                    ; u32 x MAX_CONTEXT
%define CA_CB      256
%define CA_END     264
%define CA_SIZE    272

global ap_context_apply
ap_context_apply:
    push rbx
    sub rsp, CA_SIZE
    mov rbx, rdi
    lea rdi, [rbx + CB_INPUT]
    mov esi, [rbx + CB_INPUT + MB_COUNT]
    inc esi
    cmp esi, MAX_CONTEXT
    ja .no
    mov rdx, rsp
    call ap_match_input
    test eax, eax
    jz .no
    mov [rsp + CA_END], ecx
    lea rdi, [rbx + CB_BACK]
    call ap_match_backtrack
    test eax, eax
    jz .no
    lea rdi, [rbx + CB_LOOK]
    mov esi, [rsp + CA_END]
    call ap_match_lookahead
    test eax, eax
    jz .no
    mov edi, [rbx + CB_INPUT + MB_COUNT]
    inc edi
    mov rsi, rsp
    mov rdx, [rbx + CB_RECS]
    mov ecx, [rbx + CB_NRECS]
    mov r8d, [rsp + CA_END]
    call ap_apply_records
    mov eax, 1
    jmp .out
.no:
    xor eax, eax
.out:
    add rsp, CA_SIZE
    pop rbx
    ret

; ----------------------------------------------------------------------------
; ap_context — rdi = subtable, esi = 1 chained / 0 plain -> eax 1 / 0
;   (context and chained context substitution and positioning, formats 1-3)
; ----------------------------------------------------------------------------
%define CX_CB      0                    ; the context block
%define CX_ST      88
%define CX_CHAIN   96
%define CX_SET     104                  ; the rule set
%define CX_NRULES  112
%define CX_R       116
%define CX_FMT     120
%define CX_ICD     128                  ; class definitions (format 2)
%define CX_BCD     136
%define CX_LCD     144
%define CX_SIZE    160

; rdi = pointer, rcx = bytes it needs -> CF clear when inside the table
%macro INSIDE 2
    lea r11, [%1 + %2]
    cmp r11, [r15 + S_TEND]
%endmacro

global ap_context
ap_context:
    push rbx
    push r12
    push r13
    push r14
    push rbp
    sub rsp, CX_SIZE
    mov rbx, rdi
    mov [rsp + CX_ST], rdi
    mov [rsp + CX_CHAIN], esi
    INSIDE rbx, 6
    ja .no
    BE16 eax, [rbx]
    mov [rsp + CX_FMT], eax
    call buf_cur
    mov r14d, [rax + GI_GLYPH]          ; the current glyph
    ; nothing else matched by default
    xor eax, eax
    mov [rsp + CX_CB + CB_BACK + MB_COUNT], eax
    mov [rsp + CX_CB + CB_LOOK + MB_COUNT], eax
    mov [rsp + CX_CB + CB_INPUT + MB_COUNT], eax
    cmp dword [rsp + CX_FMT], 3
    je .f3
    cmp dword [rsp + CX_FMT], 2
    je .f2
    cmp dword [rsp + CX_FMT], 1
    jne .no
    ; format 1: rule sets by coverage index, rules of glyphs
    mov rdi, rbx
    mov rsi, [r15 + S_TEND]
    mov edx, 2
    call ot_off16
    mov rdi, rax
    mov rsi, [r15 + S_TEND]
    mov edx, r14d
    call ot_coverage
    cmp eax, -1
    je .no
    BE16 ecx, [rbx + 4]
    cmp eax, ecx
    jae .no
    lea edx, [rax * 2 + 6]
    INSIDE rbx, rdx
    ja .no
    mov rdi, rbx
    mov rsi, [r15 + S_TEND]
    call ot_off16
    jmp .rule_set
.f2:
    mov rdi, rbx
    mov rsi, [r15 + S_TEND]
    mov edx, 2
    call ot_off16
    mov rdi, rax
    mov rsi, [r15 + S_TEND]
    mov edx, r14d
    call ot_coverage
    cmp eax, -1
    je .no
    xor ebp, ebp                        ; offset of the class sets' count
    cmp dword [rsp + CX_CHAIN], 0
    jne .f2_chain
    mov rdi, rbx
    mov rsi, [r15 + S_TEND]
    mov edx, 4
    call ot_off16
    mov [rsp + CX_ICD], rax
    mov qword [rsp + CX_BCD], 0
    mov qword [rsp + CX_LCD], 0
    mov ebp, 6
    jmp .f2_class
.f2_chain:
    INSIDE rbx, 12
    ja .no
    mov rdi, rbx
    mov rsi, [r15 + S_TEND]
    mov edx, 4
    call ot_off16
    mov [rsp + CX_BCD], rax
    mov rdi, rbx
    mov rsi, [r15 + S_TEND]
    mov edx, 6
    call ot_off16
    mov [rsp + CX_ICD], rax
    mov rdi, rbx
    mov rsi, [r15 + S_TEND]
    mov edx, 8
    call ot_off16
    mov [rsp + CX_LCD], rax
    mov ebp, 10
.f2_class:
    mov rdi, [rsp + CX_ICD]
    mov rsi, [r15 + S_TEND]
    mov edx, r14d
    call ot_class
    BE16 ecx, [rbx + rbp]
    cmp eax, ecx
    jae .no
    lea edx, [rbp + rax * 2 + 2]
    INSIDE rbx, rdx
    ja .no
    mov rdi, rbx
    mov rsi, [r15 + S_TEND]
    call ot_off16
.rule_set:
    test rax, rax
    jz .no
    mov [rsp + CX_SET], rax
    INSIDE rax, 2
    ja .no
    BE16 ecx, [rax]
    mov [rsp + CX_NRULES], ecx
    lea edx, [rcx * 2 + 2]
    INSIDE rax, rdx
    ja .no
    mov dword [rsp + CX_R], 0
.rule:
    mov eax, [rsp + CX_R]
    cmp eax, [rsp + CX_NRULES]
    jae .no
    inc dword [rsp + CX_R]
    mov rdi, [rsp + CX_SET]
    mov rsi, [r15 + S_TEND]
    lea edx, [rax * 2 + 2]
    call ot_off16
    test rax, rax
    jz .rule
    mov r12, rax                        ; the rule
    ; matcher kind and base
    mov ecx, MT_GLYPH
    xor r13d, r13d
    cmp dword [rsp + CX_FMT], 2
    jne .kind
    mov ecx, MT_CLASS
.kind:
    mov [rsp + CX_CB + CB_BACK + MB_TYPE], ecx
    mov [rsp + CX_CB + CB_INPUT + MB_TYPE], ecx
    mov [rsp + CX_CB + CB_LOOK + MB_TYPE], ecx
    mov rax, [rsp + CX_BCD]
    mov [rsp + CX_CB + CB_BACK + MB_BASE], rax
    mov rax, [rsp + CX_ICD]
    mov [rsp + CX_CB + CB_INPUT + MB_BASE], rax
    mov rax, [rsp + CX_LCD]
    mov [rsp + CX_CB + CB_LOOK + MB_BASE], rax
    mov rdi, r12
    lea rsi, [rsp + CX_CB]
    mov edx, [rsp + CX_CHAIN]
    call cx_sequences
    test eax, eax
    jz .rule
    lea rdi, [rsp + CX_CB]
    call ap_context_apply
    test eax, eax
    jz .rule
    jmp .yes
.f3:
    ; format 3: coverages
    mov eax, MT_COVERAGE
    mov [rsp + CX_CB + CB_BACK + MB_TYPE], eax
    mov [rsp + CX_CB + CB_INPUT + MB_TYPE], eax
    mov [rsp + CX_CB + CB_LOOK + MB_TYPE], eax
    mov [rsp + CX_CB + CB_BACK + MB_BASE], rbx
    mov [rsp + CX_CB + CB_INPUT + MB_BASE], rbx
    mov [rsp + CX_CB + CB_LOOK + MB_BASE], rbx
    lea rdi, [rbx + 2]
    lea rsi, [rsp + CX_CB]
    mov edx, [rsp + CX_CHAIN]
    or edx, 2                           ; format 3 layout
    call cx_sequences
    test eax, eax
    jz .no
    ; the first input coverage must hold the current glyph
    mov rax, [rsp + CX_CB + CB_INPUT + MB_DATA]
    BE16 edx, [rax - 2]
    test edx, edx
    jz .no
    lea rdi, [rbx + rdx]
    mov rsi, [r15 + S_TEND]
    cmp rdi, rsi
    jae .no
    mov edx, r14d
    call ot_coverage
    cmp eax, -1
    je .no
    lea rdi, [rsp + CX_CB]
    call ap_context_apply
    test eax, eax
    jnz .yes
.no:
    xor eax, eax
    jmp .out
.yes:
    mov eax, 1
.out:
    add rsp, CX_SIZE
    pop rbp
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; cx_sequences — rdi = rule (or format 3 data after its format), rsi = CB,
;   edx = 1 chained | 2 format 3 -> eax 1 / 0 (out of bounds): the CB's
;   counts, data and lookup records. Format 3's input data points past the
;   first coverage (the current glyph's).
cx_sequences:
    mov r8, rdi
    test edx, 1
    jz .plain
    ; backtrack
    INSIDE r8, 2
    ja .bad
    BE16 ecx, [r8]
    mov [rsi + CB_BACK + MB_COUNT], ecx
    lea rax, [r8 + 2]
    mov [rsi + CB_BACK + MB_DATA], rax
    lea r8, [r8 + rcx * 2 + 2]
    ; input
    INSIDE r8, 2
    ja .bad
    BE16 ecx, [r8]
    test edx, 2
    jz .chain_rule_input
    ; format 3: input count includes the first
    test ecx, ecx
    jz .bad
    lea rax, [r8 + 4]
    mov [rsi + CB_INPUT + MB_DATA], rax
    dec ecx
    mov [rsi + CB_INPUT + MB_COUNT], ecx
    lea r8, [r8 + rcx * 2 + 4]
    jmp .lookahead
.chain_rule_input:
    test ecx, ecx
    jz .bad
    lea rax, [r8 + 2]
    mov [rsi + CB_INPUT + MB_DATA], rax
    dec ecx
    mov [rsi + CB_INPUT + MB_COUNT], ecx
    lea r8, [r8 + rcx * 2 + 2]
.lookahead:
    INSIDE r8, 2
    ja .bad
    BE16 ecx, [r8]
    mov [rsi + CB_LOOK + MB_COUNT], ecx
    lea rax, [r8 + 2]
    mov [rsi + CB_LOOK + MB_DATA], rax
    lea r8, [r8 + rcx * 2 + 2]
    ; records
    INSIDE r8, 2
    ja .bad
    BE16 ecx, [r8]
    mov [rsi + CB_NRECS], ecx
    lea rax, [r8 + 2]
    mov [rsi + CB_RECS], rax
    lea r8, [r8 + rcx * 4 + 2]
    INSIDE r8, 0
    ja .bad
    mov eax, 1
    ret
.plain:
    mov dword [rsi + CB_BACK + MB_COUNT], 0
    mov dword [rsi + CB_LOOK + MB_COUNT], 0
    INSIDE r8, 4
    ja .bad
    BE16 ecx, [r8]                      ; glyph count
    BE16 r9d, [r8 + 2]                  ; records
    test ecx, ecx
    jz .bad
    dec ecx
    mov [rsi + CB_INPUT + MB_COUNT], ecx
    mov [rsi + CB_NRECS], r9d
    test edx, 2
    jz .plain_rule
    ; format 3: coverages then records
    lea rax, [r8 + 6]
    mov [rsi + CB_INPUT + MB_DATA], rax
    lea r8, [r8 + rcx * 2 + 6]
    jmp .plain_recs
.plain_rule:
    lea rax, [r8 + 4]
    mov [rsi + CB_INPUT + MB_DATA], rax
    lea r8, [r8 + rcx * 2 + 4]
.plain_recs:
    mov [rsi + CB_RECS], r8
    lea r8, [r8 + r9 * 4]
    INSIDE r8, 0
    ja .bad
    mov eax, 1
    ret
.bad:
    xor eax, eax
    ret

; ----------------------------------------------------------------------------
; ap_is_reverse — rdi = lookup -> eax 1 for reverse chaining single (GSUB 8,
;   also through an extension)
; ----------------------------------------------------------------------------
ap_is_reverse:
    xor eax, eax
    cmp byte [r15 + S_GPOS], 0
    jne .out
    sub rsp, 8
    xor esi, esi
    call ap_subtable
    add rsp, 8
    xor eax, eax
    test rax, rax
    cmp edx, 8
    sete al
.out:
    ret

; ----------------------------------------------------------------------------
; ap_run_table — edi = 0 GSUB / 1 GPOS
; ----------------------------------------------------------------------------
global ap_run_table
ap_run_table:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    mov ebp, edi
    mov [r15 + S_GPOS], bpl
    call otl_table
    mov [r15 + S_TABLE], rax
    mov [r15 + S_TEND], rdx
    mov dword [r15 + S_NEST], MAX_NESTING
    xor r12d, r12d                      ; stage
    xor r13d, r13d                      ; next lookup entry
.stage:
    cmp r12d, [r15 + S_NST + rbp * 4]
    jae .out
    mov rax, r12
    shl rax, 4
    add rax, [r15 + S_ST + rbp * 8]
    mov r14d, [rax + ST_LAST]
.lookup:
    cmp r13d, r14d
    jae .pause
    imul ebx, r13d, LK_SIZE
    add rbx, [r15 + S_LK + rbp * 8]
    inc r13d
    mov edi, ebp
    mov esi, [rbx + LK_INDEX]
    call otl_lookup
    test rax, rax
    jz .lookup
    push rax
    sub rsp, 8
    mov rdi, rax
    call ap_lookup_props
    mov [r15 + S_LPROPS], eax
    mov al, [rbx + LK_AZWNJ]
    mov [r15 + S_AZWNJ], al
    mov al, [rbx + LK_AZWJ]
    mov [r15 + S_AZWJ], al
    mov al, [rbx + LK_PERSYL]
    mov [r15 + S_PERSYL], al
    mov eax, [rbx + LK_MASK]
    mov [r15 + S_LMASK], eax
    mov dword [r15 + S_LASTBASE], -1
    mov dword [r15 + S_LASTBASEUNTIL], 0
    add rsp, 8
    pop rbx                             ; the lookup now
    cmp dword [r15 + S_LEN], 0
    je .lookup
    cmp dword [r15 + S_LMASK], 0
    je .lookup
    mov rdi, rbx
    call ap_is_reverse
    test eax, eax
    jnz .reverse
    test ebp, ebp
    jnz .forward
    call buf_clear_output
.forward:
    mov dword [r15 + S_IDX], 0
.fwd:
    mov eax, [r15 + S_IDX]
    cmp eax, [r15 + S_LEN]
    jae .fwd_done
    mov rdi, rbx
    call ap_try
    test eax, eax
    jnz .fwd
    test ebp, ebp
    jnz .gpos_next
    call buf_next_glyph
    jmp .fwd
.gpos_next:
    inc dword [r15 + S_IDX]
    jmp .fwd
.fwd_done:
    test ebp, ebp
    jnz .lookup
    call buf_sync
    jmp .lookup
.reverse:
    mov eax, [r15 + S_LEN]
    dec eax
    mov [r15 + S_IDX], eax
.rev:
    cmp dword [r15 + S_IDX], 0
    jl .rev_done
    mov rdi, rbx
    call ap_try
    dec dword [r15 + S_IDX]
    jmp .rev
.rev_done:
    mov dword [r15 + S_IDX], 0
    jmp .lookup
.pause:
    mov rax, r12
    shl rax, 4
    add rax, [r15 + S_ST + rbp * 8]
    mov rax, [rax + ST_PAUSE]
    inc r12d
    test rax, rax
    jz .stage
    mov dword [r15 + S_IDX], 0
    call rax
    jmp .stage
.out:
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; the lookup at idx when the glyph is in its mask and not skipped by its
; flags: rdi = lookup -> eax 1 applied
ap_try:
    push rbx
    mov rbx, rdi
    call buf_cur
    mov ecx, [rax + GI_MASK]
    test ecx, [r15 + S_LMASK]
    jz .no
    mov rsi, rax
    mov edi, [r15 + S_LPROPS]
    call ap_check
    test eax, eax
    jz .no
    mov rdi, rbx
    call ap_apply_subtables
    pop rbx
    ret
.no:
    xor eax, eax
    pop rbx
    ret

; ----------------------------------------------------------------------------
; ap_would_apply — edi = GSUB lookup index, rsi = glyphs (u32), edx = count,
;   ecx = zero context -> eax 1 / 0
; ----------------------------------------------------------------------------
%define WA_GLYPHS  0
%define WA_COUNT   8
%define WA_ZERO    12
%define WA_LOOKUP  16
%define WA_I       24
%define WA_ST      32
%define WA_SIZE    48

extern gsub_would_apply
extern gsub_covers

global ap_would_apply
ap_would_apply:
    push rbx
    push r12
    push r13
    sub rsp, WA_SIZE
    mov [rsp + WA_GLYPHS], rsi
    mov [rsp + WA_COUNT], edx
    mov [rsp + WA_ZERO], ecx
    test edx, edx
    jz .no
    mov ebx, edi
    ; the GSUB table as the current one
    mov byte [r15 + S_GPOS], 0
    xor edi, edi
    call otl_table
    mov [r15 + S_TABLE], rax
    mov [r15 + S_TEND], rdx
    xor edi, edi
    mov esi, ebx
    call otl_lookup
    test rax, rax
    jz .no
    mov [rsp + WA_LOOKUP], rax
    BE16 r12d, [rax + 4]
    ; the first glyph must be in some subtable's coverage
    xor r13d, r13d
.cover:
    cmp r13d, r12d
    jae .no
    mov rdi, [rsp + WA_LOOKUP]
    mov esi, r13d
    call ap_subtable
    inc r13d
    test rax, rax
    jz .cover
    mov rdi, rax
    mov esi, edx
    mov rdx, [rsp + WA_GLYPHS]
    mov edx, [rdx]
    call gsub_covers
    test eax, eax
    jz .cover
    xor r13d, r13d
.sub:
    cmp r13d, r12d
    jae .no
    mov rdi, [rsp + WA_LOOKUP]
    mov esi, r13d
    call ap_subtable
    inc r13d
    test rax, rax
    jz .sub
    mov rdi, rax
    mov esi, edx
    mov rdx, [rsp + WA_GLYPHS]
    mov ecx, [rsp + WA_COUNT]
    mov r8d, [rsp + WA_ZERO]
    call gsub_would_apply
    test eax, eax
    jz .sub
    mov eax, 1
    jmp .out
.no:
    xor eax, eax
.out:
    add rsp, WA_SIZE
    pop r13
    pop r12
    pop rbx
    ret
