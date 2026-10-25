; =============================================================================
; Utkarsha OS — lib/ufont/layout/unicode.asm
; =============================================================================
; Character properties for shaping, over the generated tables (ucd.asm):
;
;   ufl_uc_set_props(rdi = GI record, esi = code point)
;       the record's character, general category, default-ignorable / joiner /
;       hidden flags, and for marks the continuation flag and modified
;       combining class (as HarfBuzz keeps them)
;   ufl_uc_decompose(edi = ab) -> eax 1 / 0, edx = a, ecx = b (0: a singleton)
;   ufl_uc_compose(edi = a, esi = b) -> eax = ab, 0 none
;   ufl_uc_space_type(edi) -> eax = the space fallback type (0: not a space)
;   ufl_uc_is_vs(edi) -> eax 1 for a variation selector
;   ufl_uc_is_mark_gc(edi = general category) -> eax 1 for Mn / Mc / Me
;
; Hangul syllables are composed and decomposed arithmetically.
; =============================================================================

%include "ufont.inc"
%include "shape.inc"

extern ufl_ucd_gc
extern ufl_ucd_mcc
extern ufl_ucd_decomp
extern ufl_ucd_decomp_count
extern ufl_ucd_comp
extern ufl_ucd_comp_count

%define SBASE 0xAC00
%define LBASE 0x1100
%define VBASE 0x1161
%define TBASE 0x11A7
%define LCOUNT 19
%define VCOUNT 21
%define TCOUNT 28
%define NCOUNT 588
%define SCOUNT 11172

section .text

; ----------------------------------------------------------------------------
; ufl_uc_is_default_ignorable — edi = code point -> eax 1 / 0
; ----------------------------------------------------------------------------
global ufl_uc_is_default_ignorable
ufl_uc_is_default_ignorable:
    xor eax, eax
    cmp edi, 0x00AD
    je .yes
    cmp edi, 0x034F
    je .yes
    cmp edi, 0x061C
    je .yes
    mov ecx, edi
    sub ecx, 0x17B4
    cmp ecx, 1
    jbe .yes
    mov ecx, edi
    sub ecx, 0x180B
    cmp ecx, 3
    jbe .yes
    mov ecx, edi
    sub ecx, 0x200B
    cmp ecx, 4
    jbe .yes
    mov ecx, edi
    sub ecx, 0x202A
    cmp ecx, 4
    jbe .yes
    mov ecx, edi
    sub ecx, 0x2060
    cmp ecx, 0x0F
    jbe .yes
    mov ecx, edi
    sub ecx, 0xFE00
    cmp ecx, 0x0F
    jbe .yes
    cmp edi, 0xFEFF
    je .yes
    mov ecx, edi
    sub ecx, 0xFFF0
    cmp ecx, 8
    jbe .yes
    mov ecx, edi
    sub ecx, 0x1D173
    cmp ecx, 7
    jbe .yes
    mov ecx, edi
    sub ecx, 0xE0000
    cmp ecx, 0xFFF
    jbe .yes
    ret
.yes:
    mov eax, 1
    ret

global ufl_uc_is_mark_gc
ufl_uc_is_mark_gc:
    xor eax, eax
    cmp edi, GC_MC
    jb .no
    cmp edi, GC_MN
    ja .no
    mov eax, 1
.no:
    ret

global ufl_uc_is_vs
ufl_uc_is_vs:
    xor eax, eax
    mov ecx, edi
    sub ecx, 0xFE00
    cmp ecx, 0x0F
    jbe .yes
    mov ecx, edi
    sub ecx, 0xE0100
    cmp ecx, 0xEF
    jbe .yes
    mov ecx, edi
    sub ecx, 0x180B
    cmp ecx, 2
    jbe .yes
    cmp edi, 0x180F
    je .yes
    ret
.yes:
    mov eax, 1
    ret

; ----------------------------------------------------------------------------
; ufl_uc_set_props — rdi = GI record, esi = code point
; ----------------------------------------------------------------------------
global ufl_uc_set_props
ufl_uc_set_props:
    push rbx
    push r12
    mov rbx, rdi
    mov r12d, esi
    mov [rbx + GI_CP], esi
    mov edi, esi
    call ufl_ucd_gc
    mov [rbx + GI_GC], al
    mov byte [rbx + GI_UF], 0
    mov byte [rbx + GI_MCC], 0
    cmp r12d, 0x80
    jb .done
    mov edi, r12d
    call ufl_uc_is_default_ignorable
    test eax, eax
    jz .mark
    mov al, UF_IGN
    cmp r12d, 0x200C
    jne .zwj
    or al, UF_ZWNJ
    jmp .flags
.zwj:
    cmp r12d, 0x200D
    jne .hidden
    or al, UF_ZWJ
    jmp .flags
.hidden:
    mov ecx, r12d
    sub ecx, 0x180B
    cmp ecx, 2
    jbe .hide
    cmp r12d, 0x180F
    je .hide
    mov ecx, r12d
    sub ecx, 0xE0020
    cmp ecx, 0x5F
    jbe .hide
    cmp r12d, 0x034F
    jne .flags
.hide:
    or al, UF_HIDDEN
.flags:
    mov [rbx + GI_UF], al
.mark:
    movzx edi, byte [rbx + GI_GC]
    call ufl_uc_is_mark_gc
    test eax, eax
    jz .done
    or byte [rbx + GI_UF], UF_CONT
    mov edi, r12d
    call ufl_ucd_mcc
    mov [rbx + GI_MCC], al
.done:
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------------
; ufl_uc_decompose — edi = ab -> eax 1 found / 0, edx = a, ecx = b
; ----------------------------------------------------------------------------
global ufl_uc_decompose
ufl_uc_decompose:
    mov eax, edi
    sub eax, SBASE
    cmp eax, SCOUNT
    jae .table
    xor edx, edx
    mov ecx, TCOUNT
    div ecx                             ; eax = si / T, edx = si % T
    test edx, edx
    jz .lv
    lea ecx, [rdx + TBASE]              ; LV, T
    mov edx, edi
    sub edx, ecx
    add edx, TBASE                      ; ab - (si % T)
    mov eax, 1
    ret
.lv:
    mov eax, edi
    sub eax, SBASE
    xor edx, edx
    mov ecx, NCOUNT
    div ecx                             ; eax = L index, edx = si % N
    push rax
    mov eax, edx
    xor edx, edx
    mov ecx, TCOUNT
    div ecx                             ; eax = V index
    lea ecx, [rax + VBASE]
    pop rax
    lea edx, [rax + LBASE]
    mov eax, 1
    ret
.table:
    lea r8, [rel ufl_ucd_decomp]
    xor r9d, r9d                        ; lo
    mov r10d, [rel ufl_ucd_decomp_count]    ; hi
.search:
    cmp r9d, r10d
    jae .none
    lea r11d, [r9 + r10]
    shr r11d, 1
    lea rax, [r11 + r11 * 2]
    mov ecx, [r8 + rax * 4]
    cmp edi, ecx
    je .found
    jb .lower
    lea r9d, [r11 + 1]
    jmp .search
.lower:
    mov r10d, r11d
    jmp .search
.found:
    mov edx, [r8 + rax * 4 + 4]
    mov ecx, [r8 + rax * 4 + 8]
    mov eax, 1
    ret
.none:
    xor eax, eax
    ret

; ----------------------------------------------------------------------------
; ufl_uc_compose — edi = a, esi = b -> eax = ab (0: none)
; ----------------------------------------------------------------------------
global ufl_uc_compose
ufl_uc_compose:
    ; LV + T
    mov eax, edi
    sub eax, SBASE
    cmp eax, SCOUNT
    jae .lv
    cmp esi, TBASE
    jbe .lv
    cmp esi, TBASE + TCOUNT
    jae .lv
    xor edx, edx
    mov ecx, TCOUNT
    div ecx
    test edx, edx
    jnz .lv
    lea eax, [rdi + rsi - TBASE]
    ret
.lv:
    mov eax, edi
    sub eax, LBASE
    cmp eax, LCOUNT
    jae .table
    mov ecx, esi
    sub ecx, VBASE
    cmp ecx, VCOUNT
    jae .table
    imul eax, eax, NCOUNT
    imul ecx, ecx, TCOUNT
    lea eax, [rax + rcx + SBASE]
    ret
.table:
    lea r8, [rel ufl_ucd_comp]
    xor r9d, r9d
    mov r10d, [rel ufl_ucd_comp_count]
.search:
    cmp r9d, r10d
    jae .none
    lea r11d, [r9 + r10]
    shr r11d, 1
    lea rax, [r11 + r11 * 2]
    mov ecx, [r8 + rax * 4]
    cmp edi, ecx
    jne .cmp
    mov ecx, [r8 + rax * 4 + 4]
    cmp esi, ecx
    je .found
    jmp .order
.cmp:
    mov edx, esi                        ; compare a first
    jb .lower
    lea r9d, [r11 + 1]
    jmp .search
.order:
    jb .lower
    lea r9d, [r11 + 1]
    jmp .search
.lower:
    mov r10d, r11d
    jmp .search
.found:
    mov eax, [r8 + rax * 4 + 8]
    ret
.none:
    xor eax, eax
    ret

; ----------------------------------------------------------------------------
; ufl_uc_space_type — edi = code point -> eax = HarfBuzz's space type (0 none)
; ----------------------------------------------------------------------------
%define SP_EM 1
%define SP_EM_2 2
%define SP_EM_3 3
%define SP_EM_4 4
%define SP_EM_5 5
%define SP_EM_6 6
%define SP_EM_16 16
%define SP_4_EM_18 17
%define SP_SPACE 18
%define SP_FIGURE 19
%define SP_PUNCTUATION 20
%define SP_NARROW 21

global ufl_uc_space_type
ufl_uc_space_type:
    xor eax, eax
    cmp edi, 0x20
    je .space
    cmp edi, 0xA0
    je .space
    cmp edi, 0x202F
    je .narrow
    cmp edi, 0x205F
    je .e418
    cmp edi, 0x3000
    je .em
    mov ecx, edi
    sub ecx, 0x2000
    cmp ecx, 0x0A
    ja .out
    lea rdx, [rel sp_2000]
    movzx eax, byte [rdx + rcx]
.out:
    ret
.space:
    mov eax, SP_SPACE
    ret
.narrow:
    mov eax, SP_NARROW
    ret
.e418:
    mov eax, SP_4_EM_18
    ret
.em:
    mov eax, SP_EM
    ret

section .rodata
sp_2000: db SP_EM_2, SP_EM, SP_EM_2, SP_EM, SP_EM_3, SP_EM_4, SP_EM_6, SP_FIGURE, SP_PUNCTUATION, SP_EM_5, SP_EM_16
