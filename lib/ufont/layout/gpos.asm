; =============================================================================
; Utkarsha OS — lib/ufont/layout/gpos.asm
; =============================================================================
; GPOS subtables at the buffer's current glyph, positions in S_POS (font
; units, y up):
;
;   ufl_gpos_apply(rdi = subtable, esi = type) -> eax 1 applied / 0
;       1 single, 2 pair (glyph pairs and classes), 3 cursive (exit anchor
;       to entry anchor; the later glyph hangs from the earlier one unless the
;       lookup says right to left), 4 mark to base, 5 mark to ligature (the
;       component the mark belongs to), 6 mark to mark, 7 context, 8 chained
;       context. Values: x / y placement and x advance (horizontal text); device
;       tables are for hinted sizes and are not applied, as with HarfBuzz at
;       font-unit scale.
; =============================================================================

%include "ufont.inc"
%include "shape.inc"

extern ufl_ot_coverage
extern ufl_ot_class
extern ufl_ot_off16
extern ufl_buf_cur
extern ufl_sk_init
extern ufl_sk_reset
extern ufl_sk_check
extern ufl_sk_next
extern ufl_sk_prev
extern ufl_ap_context

section .text

%macro INSIDE 2
    lea r11, [%1 + %2]
    cmp r11, [r15 + S_TEND]
%endmacro

; ecx = value format -> eax = the value record's bytes
gp_value_size:
    mov eax, ecx
    and eax, 0xFF
    popcnt eax, eax
    add eax, eax
    ret

; rsi = value record, ecx = format, rdi = GPOS_* position: x / y placement
;   and x advance added
gp_value:
    test ecx, 1
    jz .ypla
    movzx eax, word [rsi]
    xchg al, ah
    movsx eax, ax
    add [rdi + GPOS_XO], eax
    add rsi, 2
.ypla:
    test ecx, 2
    jz .xadv
    movzx eax, word [rsi]
    xchg al, ah
    movsx eax, ax
    add [rdi + GPOS_YO], eax
    add rsi, 2
.xadv:
    test ecx, 4
    jz .done
    movzx eax, word [rsi]
    xchg al, ah
    movsx eax, ax
    add [rdi + GPOS_XA], eax
.done:
    ret

; the position record of glyph eax -> rax
%macro POS_OF 1
    mov eax, %1
    imul eax, eax, GPOS_SIZE
    add rax, [r15 + S_POS]
%endmacro

; rbx = subtable, edx = field offset, r14d = glyph -> eax = coverage index
gp_cov:
    mov rdi, rbx
    mov rsi, [r15 + S_TEND]
    call ufl_ot_off16
    mov rdi, rax
    mov rsi, [r15 + S_TEND]
    mov edx, r14d
    jmp ufl_ot_coverage

; rdi = anchor table (0: none) -> eax = x, edx = y
gp_anchor:
    xor eax, eax
    xor edx, edx
    test rdi, rdi
    jz .out
    INSIDE rdi, 6
    ja .out
    BE16 ecx, [rdi]
    dec ecx
    cmp ecx, 2
    ja .out
    movzx eax, word [rdi + 2]
    xchg al, ah
    movsx eax, ax
    movzx edx, word [rdi + 4]
    xchg dl, dh
    movsx edx, dx
.out:
    ret

%define GF_SK      0                    ; SK
%define GF_MARK    56                   ; mark record's anchor (absolute, 0 none)
%define GF_CLASS   64
%define GF_BASE    72                   ; base glyph position
%define GF_T       76
%define GF_SIZE    80

; ----------------------------------------------------------------------------
; ufl_gpos_apply
; ----------------------------------------------------------------------------
global ufl_gpos_apply
ufl_gpos_apply:
    push rbx
    push r12
    push r13
    push r14
    push rbp
    sub rsp, GF_SIZE
    mov rbx, rdi
    mov r12d, esi
    INSIDE rbx, 6
    ja .no
    call ufl_buf_cur
    mov r13, rax
    mov r14d, [rax + GI_GLYPH]
    BE16 ebp, [rbx]                     ; format
    cmp r12d, 7
    je .context
    cmp r12d, 8
    je .chain
    cmp r12d, 1
    je .single
    cmp r12d, 2
    je .pair
    cmp r12d, 3
    je .cursive
    cmp r12d, 4
    je .mark_base
    cmp r12d, 5
    je .mark_lig
    cmp r12d, 6
    je .mark_mark
    jmp .no

.single:
    mov edx, 2
    call gp_cov
    cmp eax, -1
    je .no
    BE16 ecx, [rbx + 4]                 ; value format
    cmp ebp, 1
    jne .single2
    lea rsi, [rbx + 6]
    jmp .single_apply
.single2:
    cmp ebp, 2
    jne .no
    BE16 edx, [rbx + 6]
    cmp eax, edx
    jae .no
    mov r8d, eax
    call gp_value_size
    imul eax, r8d
    lea rsi, [rbx + rax + 8]
.single_apply:
    push rcx
    push rsi
    call gp_value_size
    pop rsi
    pop rcx
    INSIDE rsi, rax
    ja .no
    POS_OF [r15 + S_IDX]
    mov rdi, rax
    call gp_value
    inc dword [r15 + S_IDX]
    jmp .yes

.pair:
    mov edx, 2
    call gp_cov
    cmp eax, -1
    je .no
    mov r12d, eax                       ; coverage index
    INSIDE rbx, 16
    ja .no
    lea rdi, [rsp + GF_SK]
    xor esi, esi
    call ufl_sk_init
    lea rdi, [rsp + GF_SK]
    mov esi, [r15 + S_IDX]
    mov edx, 1
    call ufl_sk_reset
    lea rdi, [rsp + GF_SK]
    xor esi, esi
    call ufl_sk_next
    test eax, eax
    jz .no
    mov eax, [rsp + GF_SK + SK_IDX]
    shl rax, 5
    add rax, [r15 + S_INFO]
    mov r13d, [rax + GI_GLYPH]          ; the second glyph
    cmp ebp, 1
    jne .pair2
    ; pair sets
    BE16 ecx, [rbx + 8]
    cmp r12d, ecx
    jae .no
    lea edx, [r12 * 2 + 10]
    INSIDE rbx, rdx
    ja .no
    mov rdi, rbx
    mov rsi, [r15 + S_TEND]
    call ufl_ot_off16
    test rax, rax
    jz .no
    mov rbp, rax                        ; the pair set
    INSIDE rbp, 2
    ja .no
    BE16 ecx, [rbx + 4]
    call gp_value_size
    mov r8d, eax                        ; size 1
    BE16 ecx, [rbx + 6]
    call gp_value_size
    lea r9d, [r8 + rax + 2]             ; record size
    BE16 ecx, [rbp]                     ; records
    mov eax, ecx
    imul eax, r9d
    lea rdx, [rbp + rax + 2]
    INSIDE rdx, 0
    ja .no
    ; binary search the second glyph
    xor r10d, r10d
.ps_search:
    cmp r10d, ecx
    jae .no
    lea r11d, [r10 + rcx]
    shr r11d, 1
    mov eax, r11d
    imul eax, r9d
    lea rsi, [rbp + rax + 2]
    BE16 eax, [rsi]
    cmp r13d, eax
    je .ps_found
    jb .ps_lo
    lea r10d, [r11 + 1]
    jmp .ps_search
.ps_lo:
    mov ecx, r11d
    jmp .ps_search
.ps_found:
    add rsi, 2
    mov r12, rsi                        ; value 1
    lea r13, [rsi + r8]                 ; value 2
    jmp .pair_values
.pair2:
    cmp ebp, 2
    jne .no
    mov rdi, rbx
    mov rsi, [r15 + S_TEND]
    mov edx, 8
    call ufl_ot_off16
    mov rdi, rax
    mov rsi, [r15 + S_TEND]
    mov edx, r14d
    call ufl_ot_class
    mov r12d, eax                       ; class 1
    mov rdi, rbx
    mov rsi, [r15 + S_TEND]
    mov edx, 10
    call ufl_ot_off16
    mov rdi, rax
    mov rsi, [r15 + S_TEND]
    mov edx, r13d
    call ufl_ot_class                       ; class 2
    BE16 ecx, [rbx + 12]
    cmp r12d, ecx
    jae .no
    BE16 edx, [rbx + 14]
    cmp eax, edx
    jae .no
    imul r12d, edx
    add r12d, eax                       ; record number
    BE16 ecx, [rbx + 4]
    call gp_value_size
    mov r8d, eax
    BE16 ecx, [rbx + 6]
    call gp_value_size
    lea r9d, [r8 + rax]
    imul r12d, r9d
    lea rsi, [rbx + r12 + 16]
    lea rdx, [rsi + r9]
    INSIDE rdx, 0
    ja .no
    mov r12, rsi
    lea r13, [rsi + r8]
.pair_values:
    BE16 ecx, [rbx + 4]
    test ecx, ecx
    jz .second
    POS_OF [r15 + S_IDX]
    mov rdi, rax
    mov rsi, r12
    call gp_value
.second:
    mov ebp, [rsp + GF_SK + SK_IDX]
    BE16 ecx, [rbx + 6]
    test ecx, ecx
    jz .pair_done
    POS_OF ebp
    mov rdi, rax
    mov rsi, r13
    call gp_value
    inc ebp
.pair_done:
    mov [r15 + S_IDX], ebp
    jmp .yes

.mark_base:
    mov dword [rsp + GF_T], 4
    jmp .mark_find
.mark_lig:
    mov dword [rsp + GF_T], 5
.mark_find:
    INSIDE rbx, 12
    ja .no
    mov edx, 2
    call gp_cov
    cmp eax, -1
    je .no
    mov rdi, rax
    call gp_mark_record
    test eax, eax
    jz .no
    ; the base: the closest glyph before that is not a mark
    lea rdi, [rsp + GF_SK]
    xor esi, esi
    call ufl_sk_init
    mov dword [rsp + GF_SK + SK_PROPS], 8   ; ignore marks
    mov eax, [r15 + S_IDX]
    cmp [r15 + S_LASTBASEUNTIL], eax
    jbe .lb_ok
    mov dword [r15 + S_LASTBASEUNTIL], 0
    mov dword [r15 + S_LASTBASE], -1
.lb_ok:
    mov ebp, [r15 + S_IDX]              ; j
.lb:
    cmp ebp, [r15 + S_LASTBASEUNTIL]
    jbe .lb_done
    lea eax, [rbp - 1]
    shl rax, 5
    add rax, [r15 + S_INFO]
    mov r12, rax
    lea rdi, [rsp + GF_SK]
    mov rsi, rax
    xor edx, edx
    call ufl_sk_check
    cmp eax, 1
    jne .lb_next
    cmp dword [rsp + GF_T], 4
    jne .lb_match
    lea edi, [rbp - 1]
    call gp_accept
    test eax, eax
    jnz .lb_match
    ; not the first of a multiple substitution: only if it is a base itself
    mov edx, 4
    push r14
    mov r14d, [r12 + GI_GLYPH]
    call gp_cov
    pop r14
    cmp eax, -1
    je .lb_next
.lb_match:
    lea eax, [rbp - 1]
    mov [r15 + S_LASTBASE], eax
    jmp .lb_done
.lb_next:
    dec ebp
    jmp .lb
.lb_done:
    mov eax, [r15 + S_IDX]
    mov [r15 + S_LASTBASEUNTIL], eax
    mov eax, [r15 + S_LASTBASE]
    cmp eax, -1
    je .no
    mov [rsp + GF_BASE], eax
    shl rax, 5
    add rax, [r15 + S_INFO]
    mov r12, rax                        ; the base record
    push r14
    mov r14d, [r12 + GI_GLYPH]
    mov edx, 4
    call gp_cov
    pop r14
    cmp eax, -1
    je .no
    mov r13d, eax                       ; base / ligature index
    mov rdi, rbx
    mov rsi, [r15 + S_TEND]
    mov edx, 10
    call ufl_ot_off16                       ; base / ligature array
    test rax, rax
    jz .no
    mov rbp, rax
    cmp dword [rsp + GF_T], 5
    je .lig_attach
    ; base array: rows of class count anchors
    mov rdi, rbp
    mov esi, r13d
    call gp_matrix_anchor
    jmp .attach
.lig_attach:
    INSIDE rbp, 2
    ja .no
    BE16 ecx, [rbp]
    cmp r13d, ecx
    jae .no
    lea edx, [r13 * 2 + 2]
    INSIDE rbp, rdx
    ja .no
    mov rdi, rbp
    mov rsi, [r15 + S_TEND]
    call ufl_ot_off16                       ; the ligature attach
    test rax, rax
    jz .no
    mov rbp, rax
    INSIDE rbp, 2
    ja .no
    BE16 ecx, [rbp]                     ; components
    test ecx, ecx
    jz .no
    ; the component the mark belongs to, else the last
    call ufl_buf_cur
    movzx edx, byte [rax + GI_LIG]
    mov r8d, edx
    shr r8d, 5                          ; mark's id
    xor r9d, r9d
    test edx, 0x10
    jnz .mcomp
    mov r9d, edx
    and r9d, 0x0F                       ; mark's component
.mcomp:
    movzx eax, byte [r12 + GI_LIG]
    shr eax, 5
    lea esi, [rcx - 1]                  ; last component
    test eax, eax
    jz .comp_have
    cmp eax, r8d
    jne .comp_have
    test r9d, r9d
    jz .comp_have
    mov esi, r9d
    cmp esi, ecx
    jbe .comp_min
    mov esi, ecx
.comp_min:
    dec esi
.comp_have:
    mov rdi, rbp
    call gp_matrix_anchor
.attach:
    test rax, rax
    jz .no
    mov rdi, rax
    call gp_anchor
    push rax
    push rdx
    mov rdi, [rsp + 16 + GF_MARK]
    call gp_anchor                      ; the mark's
    pop r9                              ; base y
    pop r8                              ; base x
    sub r8d, eax
    sub r9d, edx
    POS_OF [r15 + S_IDX]
    mov [rax + GPOS_XO], r8d
    mov [rax + GPOS_YO], r9d
    mov dword [rax + GPOS_TYPE], 1
    mov ecx, [rsp + GF_BASE]
    sub ecx, [r15 + S_IDX]
    mov [rax + GPOS_CHAIN], ecx
    mov byte [r15 + S_HASATTACH], 1
    inc dword [r15 + S_IDX]
    jmp .yes

.mark_mark:
    INSIDE rbx, 12
    ja .no
    mov edx, 2
    call gp_cov
    cmp eax, -1
    je .no
    mov rdi, rax
    call gp_mark_record
    test eax, eax
    jz .no
    lea rdi, [rsp + GF_SK]
    xor esi, esi
    call ufl_sk_init
    mov eax, [r15 + S_LPROPS]
    and eax, ~LF_IGNORE_FLAGS
    mov [rsp + GF_SK + SK_PROPS], eax
    lea rdi, [rsp + GF_SK]
    mov esi, [r15 + S_IDX]
    mov edx, 1
    call ufl_sk_reset
    lea rdi, [rsp + GF_SK]
    xor esi, esi
    call ufl_sk_prev
    test eax, eax
    jz .no
    mov eax, [rsp + GF_SK + SK_IDX]
    mov [rsp + GF_BASE], eax
    shl rax, 5
    add rax, [r15 + S_INFO]
    mov r12, rax                        ; the other mark
    test word [r12 + GI_PROPS], GP_MARK
    jz .no
    ; same base, or same ligature component, or one of them a ligature
    call ufl_buf_cur
    movzx ecx, byte [rax + GI_LIG]      ; mark 1
    movzx edx, byte [r12 + GI_LIG]      ; mark 2
    mov r8d, ecx
    shr r8d, 5                          ; id1
    mov r9d, edx
    shr r9d, 5                          ; id2
    xor r10d, r10d                      ; comp1
    test ecx, 0x10
    jnz .c1
    mov r10d, ecx
    and r10d, 0x0F
.c1:
    xor r11d, r11d                      ; comp2
    test edx, 0x10
    jnz .c2
    mov r11d, edx
    and r11d, 0x0F
.c2:
    cmp r8d, r9d
    jne .ids_differ
    test r8d, r8d
    jz .mm_good
    cmp r10d, r11d
    je .mm_good
    jmp .no
.ids_differ:
    test r8d, r8d
    jz .id2
    test r10d, r10d
    jz .mm_good
.id2:
    test r9d, r9d
    jz .no
    test r11d, r11d
    jnz .no
.mm_good:
    push r14
    mov r14d, [r12 + GI_GLYPH]
    mov edx, 4
    call gp_cov
    pop r14
    cmp eax, -1
    je .no
    mov r13d, eax
    mov rdi, rbx
    mov rsi, [r15 + S_TEND]
    mov edx, 10
    call ufl_ot_off16
    test rax, rax
    jz .no
    mov rdi, rax
    mov esi, r13d
    call gp_matrix_anchor
    jmp .attach

.cursive:
    cmp ebp, 1
    jne .no
    mov edx, 2
    call gp_cov
    cmp eax, -1
    je .no
    mov edi, eax
    call gp_entry_exit
    test rax, rax
    jz .no
    mov rdi, rax
    call gp_anchor                      ; this glyph's entry
    mov [rsp + GF_MARK], eax            ; entry x
    mov [rsp + GF_MARK + 4], edx        ; entry y
    lea rdi, [rsp + GF_SK]
    xor esi, esi
    call ufl_sk_init
    lea rdi, [rsp + GF_SK]
    mov esi, [r15 + S_IDX]
    mov edx, 1
    call ufl_sk_reset
    lea rdi, [rsp + GF_SK]
    xor esi, esi
    call ufl_sk_prev
    test eax, eax
    jz .no
    mov eax, [rsp + GF_SK + SK_IDX]
    shl rax, 5
    add rax, [r15 + S_INFO]
    push r14
    mov r14d, [rax + GI_GLYPH]
    mov edx, 2
    call gp_cov
    pop r14
    cmp eax, -1
    je .no
    mov edi, eax
    call gp_entry_exit
    test rdx, rdx
    jz .no
    mov rdi, rdx
    call gp_anchor                      ; the previous glyph's exit
    mov r8d, eax                        ; exit x
    mov r9d, edx                        ; exit y
    mov r12d, [rsp + GF_SK + SK_IDX]    ; i
    mov r13d, [r15 + S_IDX]             ; j
    cmp byte [r15 + S_RTL], 0
    jne .curs_rtl
    ; left to right: the previous glyph's advance ends at its exit, this one
    ; starts at its entry
    imul eax, r12d, GPOS_SIZE
    add rax, [r15 + S_POS]
    mov ecx, r8d
    add ecx, [rax + GPOS_XO]
    mov [rax + GPOS_XA], ecx
    imul eax, r13d, GPOS_SIZE
    add rax, [r15 + S_POS]
    mov ecx, [rsp + GF_MARK]
    add ecx, [rax + GPOS_XO]
    sub [rax + GPOS_XA], ecx
    sub [rax + GPOS_XO], ecx
    jmp .curs_cross
.curs_rtl:
    ; right to left: the previous glyph starts at its exit, this one's
    ; advance ends at its entry
    imul eax, r12d, GPOS_SIZE
    add rax, [r15 + S_POS]
    mov ecx, r8d
    add ecx, [rax + GPOS_XO]
    sub [rax + GPOS_XA], ecx
    sub [rax + GPOS_XO], ecx
    imul eax, r13d, GPOS_SIZE
    add rax, [r15 + S_POS]
    mov ecx, [rsp + GF_MARK]
    add ecx, [rax + GPOS_XO]
    mov [rax + GPOS_XA], ecx
.curs_cross:
    ; the child hangs from the parent
    mov ecx, [rsp + GF_MARK + 4]
    sub ecx, r9d                        ; entry y - exit y
    mov ebx, r12d                       ; child
    mov ebp, r13d                       ; parent
    test dword [r15 + S_LPROPS], 1      ; right to left
    jnz .curs_dir
    xchg ebx, ebp
    neg ecx
.curs_dir:
    push rcx
    sub rsp, 8
    mov edi, ebx
    mov esi, ebp
    call gp_reverse_cursive
    add rsp, 8
    pop rcx
    imul eax, ebx, GPOS_SIZE
    add rax, [r15 + S_POS]
    mov edx, ebp
    sub edx, ebx
    mov [rax + GPOS_CHAIN], edx
    mov dword [rax + GPOS_TYPE], 2
    mov [rax + GPOS_YO], ecx
    mov byte [r15 + S_HASATTACH], 1
    ; the parent attached to the child: separated
    imul r8d, ebp, GPOS_SIZE
    add r8, [r15 + S_POS]
    neg edx
    cmp [r8 + GPOS_CHAIN], edx
    jne .curs_done
    mov dword [r8 + GPOS_CHAIN], 0
    mov dword [r8 + GPOS_YO], 0
.curs_done:
    inc dword [r15 + S_IDX]
    jmp .yes

.context:
    mov rdi, rbx
    xor esi, esi
    call ufl_ap_context
    jmp .out
.chain:
    mov rdi, rbx
    mov esi, 1
    call ufl_ap_context
    jmp .out
.yes:
    mov eax, 1
    jmp .out
.no:
    xor eax, eax
.out:
    add rsp, GF_SIZE
    pop rbp
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; gp_entry_exit — edi = coverage index; rbx = a cursive subtable -> rax =
;   its entry anchor, rdx = its exit anchor (0 when absent or past the list)
gp_entry_exit:
    xor eax, eax
    xor edx, edx
    BE16 ecx, [rbx + 4]                 ; records
    cmp edi, ecx
    jae .out
    lea r8, [rdi * 4 + 10]
    lea r9, [rbx + r8]
    cmp r9, [r15 + S_TEND]
    ja .out
    BE16 ecx, [rbx + rdi * 4 + 6]       ; entry
    test ecx, ecx
    jz .exit
    lea rax, [rbx + rcx]
    cmp rax, [r15 + S_TEND]
    jb .exit
    xor eax, eax
.exit:
    BE16 ecx, [rbx + rdi * 4 + 8]
    test ecx, ecx
    jz .out
    lea rdx, [rbx + rcx]
    cmp rdx, [r15 + S_TEND]
    jb .out
    xor edx, edx
.out:
    ret

; gp_reverse_cursive — edi = glyph, esi = its new parent: a cursive chain
;   it had is turned round so its old tree hangs from it
gp_reverse_cursive:
    push rbx
    push r12
    push r13
    mov ebx, edi
    mov r13d, esi
    imul eax, ebx, GPOS_SIZE
    mov r12, [r15 + S_POS]
    add r12, rax                        ; pos[i]
    mov ecx, [r12 + GPOS_CHAIN]
    test ecx, ecx
    jz .out
    test dword [r12 + GPOS_TYPE], 2
    jz .out
    mov dword [r12 + GPOS_CHAIN], 0
    lea edi, [rbx + rcx]                ; j
    cmp edi, r13d
    je .out
    push rcx
    push rdi
    mov esi, r13d
    call gp_reverse_cursive
    pop rdi
    pop rcx
    imul eax, edi, GPOS_SIZE
    add rax, [r15 + S_POS]
    mov edx, [r12 + GPOS_YO]
    neg edx
    mov [rax + GPOS_YO], edx
    neg ecx
    mov [rax + GPOS_CHAIN], ecx
    mov edx, [r12 + GPOS_TYPE]
    mov [rax + GPOS_TYPE], edx
.out:
    pop r13
    pop r12
    pop rbx
    ret

; gp_mark_record — rdi = mark index; rbx = subtable (mark array at 8) ->
;   eax 1, the frame's GF_MARK (anchor) and GF_CLASS set (an index past the
;   array reads as class 0, no anchor, as HarfBuzz's Null record)
gp_mark_record:
    lea r10, [rsp + 8]                  ; the caller's frame
    mov qword [r10 + GF_MARK], 0
    mov dword [r10 + GF_CLASS], 0
    push rdi
    mov rdi, rbx
    mov rsi, [r15 + S_TEND]
    mov edx, 8
    call ufl_ot_off16
    pop rdi
    lea r10, [rsp + 8]
    test rax, rax
    jz .one
    INSIDE rax, 2
    ja .one
    BE16 ecx, [rax]
    cmp edi, ecx
    jae .one
    lea rdx, [rax + rdi * 4 + 6]
    INSIDE rdx, 0
    ja .one
    BE16 ecx, [rax + rdi * 4 + 2]
    mov [r10 + GF_CLASS], ecx
    BE16 ecx, [rax + rdi * 4 + 4]
    test ecx, ecx
    jz .one
    add rcx, rax
    mov [r10 + GF_MARK], rcx
.one:
    mov eax, 1
    ret

; gp_matrix_anchor — rdi = anchor matrix (rows of class count offsets,
;   count first), esi = row; the caller's GF_CLASS; rbx = subtable (class
;   count at 6) -> rax = the anchor, 0 when absent
gp_matrix_anchor:
    lea r10, [rsp + 8]
    INSIDE rdi, 2
    ja .none
    BE16 ecx, [rdi]                     ; rows
    cmp esi, ecx
    jae .none
    BE16 edx, [rbx + 6]                 ; class count
    mov eax, [r10 + GF_CLASS]
    cmp eax, edx
    jae .none
    imul esi, edx
    add esi, eax
    lea edx, [rsi * 2 + 2]
    INSIDE rdi, rdx
    ja .none
    BE16 eax, [rdi + rsi * 2 + 2]
    test eax, eax
    jz .none
    add rax, rdi
    cmp rax, [r15 + S_TEND]
    jae .none
    ret
.none:
    xor eax, eax
    ret

; gp_accept — edi = position -> eax 1 when it is a fine base: not the
;   second or later glyph of a multiple substitution (unless after a mark)
gp_accept:
    mov rcx, [r15 + S_INFO]
    mov eax, edi
    shl rax, 5
    lea rdx, [rcx + rax]
    test word [rdx + GI_PROPS], GP_MULTIPLIED
    jz .yes
    movzx r8d, byte [rdx + GI_LIG]
    test r8d, 0x10
    jnz .yes
    test r8d, 0x0F
    jz .yes
    test edi, edi
    jz .yes
    test word [rdx - 32 + GI_PROPS], GP_MARK
    jnz .yes
    test word [rdx - 32 + GI_PROPS], GP_MULTIPLIED
    jz .yes
    movzx r9d, byte [rdx - 32 + GI_LIG]
    mov eax, r8d
    shr eax, 5
    mov r10d, r9d
    shr r10d, 5
    cmp eax, r10d
    jne .yes
    ; components: this one's must follow the one before's
    xor r10d, r10d
    test r9d, 0x10
    jnz .prev_comp
    mov r10d, r9d
    and r10d, 0x0F
.prev_comp:
    and r8d, 0x0F
    inc r10d
    cmp r8d, r10d
    jne .yes
    xor eax, eax
    ret
.yes:
    mov eax, 1
    ret
