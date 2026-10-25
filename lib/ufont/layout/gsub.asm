; =============================================================================
; Utkarsha OS — lib/ufont/layout/gsub.asm
; =============================================================================
; GSUB subtables at the buffer's current glyph:
;
;   gsub_apply(rdi = subtable, esi = type) -> eax 1 applied / 0
;       1 single, 2 multiple, 3 alternate (the feature's value picks),
;       4 ligature, 5 context, 6 chained context, 8 reverse chaining single
;       (only at the top level; never through a context lookup)
;   gsub_covers(rdi = subtable, esi = type, edx = glyph) -> eax 1 / 0
;       is the glyph in the subtable's (first) coverage
;   gsub_would_apply(rdi = subtable, esi = type, rdx = glyphs (u32), ecx =
;       count, r8d = zero context) -> eax 1 / 0
;       would the subtable substitute exactly these glyphs (HarfBuzz's
;       would_apply: no flags, no context unless allowed)
; =============================================================================

%include "ufont.inc"
%include "shape.inc"

extern ot_coverage
extern ot_class
extern ot_off16
extern buf_cur
extern buf_skip_glyph
extern buf_delete_glyph
extern ap_replace_glyph
extern ap_replace_inplace
extern ap_output_component
extern ap_match_input
extern ap_match_backtrack
extern ap_match_lookahead
extern ap_ligate
extern ap_context

section .text

%macro INSIDE 2
    lea r11, [%1 + %2]
    cmp r11, [r15 + S_TEND]
%endmacro

; rbx = subtable, edx = glyph -> eax = index in the coverage at offset 2
gs_cov2:
    mov rdi, rbx
    mov rsi, [r15 + S_TEND]
    push rdx
    mov edx, 2
    call ot_off16
    pop rdx
    mov rdi, rax
    mov rsi, [r15 + S_TEND]
    jmp ot_coverage

; rbx = subtable, eax = index -> rax = the table at the offset array (count
;   at 4, offsets at 6) entry, 0
gs_array_entry:
    BE16 ecx, [rbx + 4]
    cmp eax, ecx
    jae .none
    lea edx, [rax * 2 + 6]
    INSIDE rbx, rdx
    ja .none
    mov rdi, rbx
    mov rsi, [r15 + S_TEND]
    jmp ot_off16
.none:
    xor eax, eax
    ret

; ----------------------------------------------------------------------------
; gsub_apply
; ----------------------------------------------------------------------------
global gsub_apply
gsub_apply:
    push rbx
    push r12
    push r13
    push r14
    push rbp
    sub rsp, 288                        ; match positions (u32 x 64) and more
    mov rbx, rdi
    mov r12d, esi
    INSIDE rbx, 6
    ja .no
    call buf_cur
    mov r13, rax                        ; the current record
    mov r14d, [rax + GI_GLYPH]
    cmp r12d, 5
    je .context
    cmp r12d, 6
    je .chain
    cmp r12d, 8
    je .reverse
    BE16 ebp, [rbx]                     ; format
    mov edx, r14d
    call gs_cov2
    cmp eax, -1
    je .no
    cmp r12d, 1
    je .single
    cmp r12d, 2
    je .multiple
    cmp r12d, 3
    je .alternate
    cmp r12d, 4
    je .ligature
    jmp .no
.single:
    cmp ebp, 1
    jne .single2
    movsx ecx, word [rbx + 4]
    xchg cl, ch
    movsx ecx, cx                       ; delta
    lea esi, [r14 + rcx]
    movzx esi, si
    call ap_replace_glyph
    jmp .yes
.single2:
    cmp ebp, 2
    jne .no
    BE16 ecx, [rbx + 4]
    cmp eax, ecx
    jae .no
    lea edx, [rax * 2 + 8]
    INSIDE rbx, rdx
    ja .no
    BE16 esi, [rbx + rax * 2 + 6]
    call ap_replace_glyph
    jmp .yes
.multiple:
    cmp ebp, 1
    jne .no
    call gs_array_entry
    test rax, rax
    jz .no
    mov rbp, rax                        ; the sequence
    INSIDE rbp, 2
    ja .no
    BE16 r12d, [rbp]                    ; how many
    lea edx, [r12 * 2 + 2]
    INSIDE rbp, rdx
    ja .no
    cmp r12d, 1
    je .mult_one
    test r12d, r12d
    jz .mult_none
    ; a component per glyph
    xor edx, edx
    test word [r13 + GI_PROPS], GP_LIGATURE
    jz .mult_class
    mov edx, GP_BASE
.mult_class:
    mov [rsp], edx                      ; class guess
    movzx eax, byte [r13 + GI_LIG]
    shr eax, 5
    mov [rsp + 4], eax                  ; ligature id
    xor r14d, r14d
.mult_each:
    cmp r14d, r12d
    jae .mult_done
    cmp dword [rsp + 4], 0
    jne .mult_keep
    call buf_cur
    mov ecx, r14d
    and ecx, 0x0F
    mov [rax + GI_LIG], cl
.mult_keep:
    BE16 esi, [rbp + r14 * 2 + 2]
    mov edx, [rsp]
    call ap_output_component
    inc r14d
    jmp .mult_each
.mult_done:
    call buf_skip_glyph
    jmp .yes
.mult_one:
    BE16 esi, [rbp + 2]
    call ap_replace_glyph
    jmp .yes
.mult_none:
    call buf_delete_glyph
    jmp .yes
.alternate:
    cmp ebp, 1
    jne .no
    call gs_array_entry
    test rax, rax
    jz .no
    mov rbp, rax
    INSIDE rbp, 2
    ja .no
    BE16 ecx, [rbp]
    lea edx, [rcx * 2 + 2]
    INSIDE rbp, rdx
    ja .no
    mov edx, [r15 + S_LMASK]
    bsf r8d, edx                        ; shift
    mov eax, [r13 + GI_MASK]
    and eax, edx
    xchg ecx, r8d
    shr eax, cl
    xchg ecx, r8d
    test eax, eax
    jz .no
    cmp eax, ecx
    ja .no
    BE16 esi, [rbp + rax * 2]           ; alternates[index - 1]
    call ap_replace_glyph
    jmp .yes
.ligature:
    cmp ebp, 1
    jne .no
    call gs_array_entry
    test rax, rax
    jz .no
    mov rbp, rax                        ; the ligature set
    INSIDE rbp, 2
    ja .no
    BE16 ecx, [rbp]
    lea edx, [rcx * 2 + 2]
    INSIDE rbp, rdx
    ja .no
    mov [rsp + 256], ecx
    mov dword [rsp + 260], 0
.lig_each:
    mov eax, [rsp + 260]
    cmp eax, [rsp + 256]
    jae .no
    inc dword [rsp + 260]
    mov rdi, rbp
    mov rsi, [r15 + S_TEND]
    lea edx, [rax * 2 + 2]
    call ot_off16
    test rax, rax
    jz .lig_each
    mov r12, rax                        ; the ligature
    INSIDE r12, 4
    ja .lig_each
    BE16 ecx, [r12 + 2]                 ; components
    test ecx, ecx
    jz .lig_each
    lea edx, [rcx * 2 + 2]
    INSIDE r12, rdx
    ja .lig_each
    cmp ecx, 1
    jne .lig_match
    BE16 esi, [r12]
    call ap_replace_glyph
    jmp .yes
.lig_match:
    cmp ecx, MAX_CONTEXT
    ja .lig_each
    mov [rsp + 264], ecx
    ; the matcher: the components after the first
    sub rsp, MB_SIZE + 8
    mov dword [rsp + MB_TYPE], MT_GLYPH
    dec ecx
    mov [rsp + MB_COUNT], ecx
    lea rax, [r12 + 4]
    mov [rsp + MB_DATA], rax
    mov qword [rsp + MB_BASE], 0
    mov rdi, rsp
    mov esi, [rsp + MB_SIZE + 8 + 264]
    lea rdx, [rsp + MB_SIZE + 8]
    call ap_match_input
    add rsp, MB_SIZE + 8
    test eax, eax
    jz .lig_each
    mov edi, [rsp + 264]
    mov rsi, rsp
    mov r8d, edx                        ; total components
    mov edx, ecx                        ; match end
    BE16 ecx, [r12]                     ; the ligature glyph
    call ap_ligate
    jmp .yes
.context:
    mov rdi, rbx
    xor esi, esi
    call ap_context
    jmp .out
.chain:
    mov rdi, rbx
    mov esi, 1
    call ap_context
    jmp .out
.reverse:
    cmp dword [r15 + S_NEST], MAX_NESTING
    jne .no
    BE16 eax, [rbx]
    cmp eax, 1
    jne .no
    mov edx, r14d
    call gs_cov2
    cmp eax, -1
    je .no
    mov ebp, eax                        ; coverage index
    ; backtrack, lookahead, substitutes
    lea r8, [rbx + 4]
    BE16 ecx, [r8]
    mov dword [rsp + MB_TYPE], MT_COVERAGE
    mov [rsp + MB_COUNT], ecx
    lea rax, [r8 + 2]
    mov [rsp + MB_DATA], rax
    mov [rsp + MB_BASE], rbx
    lea r8, [r8 + rcx * 2 + 2]
    INSIDE r8, 2
    ja .no
    BE16 ecx, [r8]
    mov dword [rsp + 32 + MB_TYPE], MT_COVERAGE
    mov [rsp + 32 + MB_COUNT], ecx
    lea rax, [r8 + 2]
    mov [rsp + 32 + MB_DATA], rax
    mov [rsp + 32 + MB_BASE], rbx
    lea r8, [r8 + rcx * 2 + 2]
    INSIDE r8, 2
    ja .no
    BE16 ecx, [r8]
    lea rdx, [r8 + rcx * 2 + 2]
    INSIDE rdx, 0
    ja .no
    xor r12d, r12d                      ; the substitute (0 past the list)
    cmp ebp, ecx
    jae .rev_have
    BE16 r12d, [r8 + rbp * 2 + 2]
.rev_have:
    mov rdi, rsp
    call ap_match_backtrack
    test eax, eax
    jz .no
    lea rdi, [rsp + 32]
    mov esi, [r15 + S_IDX]
    inc esi
    call ap_match_lookahead
    test eax, eax
    jz .no
    mov esi, r12d
    call ap_replace_inplace
.yes:
    mov eax, 1
    jmp .out
.no:
    xor eax, eax
.out:
    add rsp, 288
    pop rbp
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------------
; gsub_covers — rdi = subtable, esi = type, edx = glyph -> eax 1 / 0
; ----------------------------------------------------------------------------
global gsub_covers
gsub_covers:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12d, edx
    INSIDE rbx, 6
    ja .no
    cmp esi, 5
    je .ctx
    cmp esi, 6
    je .chain
    cmp esi, 8
    ja .no
    cmp esi, 7
    je .no
.cov2:
    mov edx, r12d
    call gs_cov2
    jmp .result
.ctx:
    BE16 eax, [rbx]
    cmp eax, 3
    jne .cov2
    BE16 ecx, [rbx + 2]
    test ecx, ecx
    jz .no
    mov rdi, rbx
    mov rsi, [r15 + S_TEND]
    mov edx, 6
    jmp .first
.chain:
    BE16 eax, [rbx]
    cmp eax, 3
    jne .cov2
    BE16 ecx, [rbx + 2]                 ; backtrack
    lea edx, [rcx * 2 + 4]              ; input count
    lea rax, [rdx + 4]
    INSIDE rbx, rax
    ja .no
    BE16 ecx, [rbx + rdx]
    test ecx, ecx
    jz .no
    add edx, 2
    mov rdi, rbx
    mov rsi, [r15 + S_TEND]
.first:
    call ot_off16
    mov rdi, rax
    mov rsi, [r15 + S_TEND]
    mov edx, r12d
    call ot_coverage
.result:
    cmp eax, -1
    je .no
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
; gsub_would_apply — rdi = subtable, esi = type, rdx = glyphs, ecx = count,
;   r8d = zero context -> eax 1 / 0
; ----------------------------------------------------------------------------
%define WS_GLYPHS 0
%define WS_N      8
%define WS_ZERO   12
%define WS_TYPE   16
%define WS_FMT    20
%define WS_SET    24
%define WS_R      32
%define WS_NR     36
%define WS_CD     40
%define WS_SIZE   48

global gsub_would_apply
gsub_would_apply:
    push rbx
    push r12
    push r13
    push r14
    push rbp
    sub rsp, WS_SIZE
    mov rbx, rdi
    mov [rsp + WS_GLYPHS], rdx
    mov [rsp + WS_N], ecx
    mov [rsp + WS_ZERO], r8d
    mov [rsp + WS_TYPE], esi
    INSIDE rbx, 6
    ja .no
    BE16 eax, [rbx]
    mov [rsp + WS_FMT], eax
    mov rax, [rsp + WS_GLYPHS]
    mov r14d, [rax]                     ; the first glyph
    cmp esi, 4
    je .ligature
    cmp esi, 5
    je .context
    cmp esi, 6
    je .context
    cmp esi, 8
    ja .no
    cmp esi, 7
    je .no
    ; single, multiple, alternate, reverse: one glyph, covered
    cmp ecx, 1
    jne .no
    mov edx, r14d
    call gs_cov2
    cmp eax, -1
    je .no
    jmp .yes
.ligature:
    mov edx, r14d
    call gs_cov2
    cmp eax, -1
    je .no
    call gs_array_entry
    test rax, rax
    jz .no
    mov rbp, rax
    INSIDE rbp, 2
    ja .no
    BE16 r12d, [rbp]
    xor r13d, r13d
.lig:
    cmp r13d, r12d
    jae .no
    mov rdi, rbp
    mov rsi, [r15 + S_TEND]
    lea edx, [r13 * 2 + 2]
    inc r13d
    call ot_off16
    test rax, rax
    jz .lig
    INSIDE rax, 4
    ja .lig
    BE16 ecx, [rax + 2]
    cmp ecx, [rsp + WS_N]
    jne .lig
    lea edx, [rcx * 2 + 2]
    INSIDE rax, rdx
    ja .lig
    mov rsi, [rsp + WS_GLYPHS]
    mov edx, 1
.lig_cmp:
    cmp edx, ecx
    jae .yes
    BE16 r8d, [rax + rdx * 2 + 2]
    cmp r8d, [rsi + rdx * 4]
    jne .lig
    inc edx
    jmp .lig_cmp
.context:
    cmp dword [rsp + WS_FMT], 3
    je .f3
    cmp dword [rsp + WS_FMT], 2
    je .f2
    cmp dword [rsp + WS_FMT], 1
    jne .no
    mov edx, r14d
    call gs_cov2
    cmp eax, -1
    je .no
    call gs_array_entry
    mov qword [rsp + WS_CD], 0
    jmp .set
.f2:
    ; the class set of the first glyph's class (no coverage asked)
    mov ebp, 4                          ; class definition offset
    mov r12d, 6                         ; set count
    cmp dword [rsp + WS_TYPE], 6
    jne .f2_cd
    mov ebp, 6
    mov r12d, 10
.f2_cd:
    INSIDE rbx, r12
    ja .no
    mov rdi, rbx
    mov rsi, [r15 + S_TEND]
    mov edx, ebp
    call ot_off16
    mov [rsp + WS_CD], rax
    mov rdi, rax
    mov rsi, [r15 + S_TEND]
    mov edx, r14d
    call ot_class
    BE16 ecx, [rbx + r12]
    cmp eax, ecx
    jae .no
    lea edx, [r12 + rax * 2 + 2]
    INSIDE rbx, rdx
    ja .no
    mov rdi, rbx
    mov rsi, [r15 + S_TEND]
    call ot_off16
.set:
    test rax, rax
    jz .no
    mov [rsp + WS_SET], rax
    INSIDE rax, 2
    ja .no
    BE16 ecx, [rax]
    mov [rsp + WS_NR], ecx
    mov dword [rsp + WS_R], 0
.rule:
    mov eax, [rsp + WS_R]
    cmp eax, [rsp + WS_NR]
    jae .no
    inc dword [rsp + WS_R]
    mov rdi, [rsp + WS_SET]
    mov rsi, [r15 + S_TEND]
    lea edx, [rax * 2 + 2]
    call ot_off16
    test rax, rax
    jz .rule
    mov r8, rax
    cmp dword [rsp + WS_TYPE], 6
    jne .rule_input
    ; chained: no backtrack / lookahead under zero context
    INSIDE r8, 2
    ja .rule
    BE16 ecx, [r8]
    test ecx, ecx
    jz .no_back
    cmp dword [rsp + WS_ZERO], 0
    jne .rule
.no_back:
    lea r8, [r8 + rcx * 2 + 2]
    INSIDE r8, 2
    ja .rule
    BE16 ecx, [r8]                      ; input count
    lea r9, [r8 + rcx * 2]              ; at the lookahead count
    INSIDE r9, 2
    ja .rule
    cmp dword [rsp + WS_ZERO], 0
    je .rule_items
    cmp word [r9], 0
    jne .rule
    jmp .rule_items
.rule_input:
    INSIDE r8, 4
    ja .rule
    BE16 ecx, [r8]
    add r8, 2                           ; the items follow the count field +2
.rule_items:
    ; r8 = the count field (chained) or glyph count field + 2 (plain); items
    ; from r8 + 2
    cmp ecx, [rsp + WS_N]
    jne .rule
    lea rdx, [r8 + rcx * 2]
    INSIDE rdx, 0
    ja .rule
    mov rsi, [rsp + WS_GLYPHS]
    mov r12d, 1
.item:
    cmp r12d, [rsp + WS_N]
    jae .yes
    BE16 r13d, [r8 + r12 * 2]           ; item r12 - 1, at r8 + 2 + (r12 - 1) * 2
    mov edx, [rsi + r12 * 4]
    mov rdi, [rsp + WS_CD]
    test rdi, rdi
    jz .item_glyph
    push rsi
    sub rsp, 8
    mov rsi, [r15 + S_TEND]
    call ot_class
    add rsp, 8
    pop rsi
    cmp eax, r13d
    jne .rule
    inc r12d
    jmp .item
.item_glyph:
    cmp edx, r13d
    jne .rule
    inc r12d
    jmp .item
.f3:
    ; coverages
    mov r8, rbx
    cmp dword [rsp + WS_TYPE], 6
    jne .f3_plain
    BE16 ecx, [rbx + 2]
    test ecx, ecx
    jz .f3_noback
    cmp dword [rsp + WS_ZERO], 0
    jne .no
.f3_noback:
    lea r8, [rbx + rcx * 2 + 4]         ; input count
    INSIDE r8, 2
    ja .no
    BE16 ecx, [r8]
    lea r9, [r8 + rcx * 2 + 2]
    INSIDE r9, 2
    ja .no
    cmp dword [rsp + WS_ZERO], 0
    je .f3_items
    cmp word [r9], 0
    jne .no
    jmp .f3_items
.f3_plain:
    lea r8, [rbx + 2]
    BE16 ecx, [r8]
    add r8, 2                           ; coverages start at r8 + 2
.f3_items:
    cmp ecx, [rsp + WS_N]
    jne .no
    lea rdx, [r8 + rcx * 2 + 2]
    INSIDE rdx, 0
    ja .no
    mov r12d, 1
.f3_item:
    cmp r12d, [rsp + WS_N]
    jae .yes
    BE16 eax, [r8 + r12 * 2 + 2]
    test eax, eax
    jz .no
    lea rdi, [rbx + rax]
    mov rsi, [r15 + S_TEND]
    cmp rdi, rsi
    jae .no
    mov rax, [rsp + WS_GLYPHS]
    mov edx, [rax + r12 * 4]
    push r8
    sub rsp, 8
    call ot_coverage
    add rsp, 8
    pop r8
    cmp eax, -1
    je .no
    inc r12d
    jmp .f3_item
.yes:
    mov eax, 1
    jmp .out
.no:
    xor eax, eax
.out:
    add rsp, WS_SIZE
    pop rbp
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
