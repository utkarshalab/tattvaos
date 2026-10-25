; =============================================================================
; Utkarsha OS — lib/ufont/layout/otl.asm
; =============================================================================
; Reading OpenType layout tables (GDEF, GSUB, GPOS). Every offset is checked
; against the end of its table before anything is read through it; what is
; out of bounds reads as absent (an empty coverage, class 0, no lookup).
;
;   ot_coverage(rdi = coverage, rsi = table end, edx = glyph) -> eax index, -1
;   ot_class(rdi = class definition, rsi = end, edx = glyph) -> eax class
;   ot_off16(rdi = base, rsi = end, edx = byte offset of the field) -> rax =
;       base + the u16 offset there, 0 when null or out of bounds
;   otl_gdef_init               GDEF's class definitions and mark sets (state)
;   otl_glyph_props(edi = glyph) -> eax GDEF props (class bits, attachment
;       class << 8)
;   otl_mark_set_covers(edi = set, esi = glyph) -> eax 1 / 0
;   otl_select(edi = 0 GSUB / 1 GPOS)  script and language system for the run
;   otl_feature_index(edi = table, esi = tag) -> eax its index in the language
;       system, -1
;   otl_feature_lookups(edi = table, esi = feature index) -> rax = the lookup
;       indices (big-endian u16), ecx = how many
;   otl_lookup(edi = table, esi = lookup index) -> rax = the lookup, 0
;   otl_table(edi = table) -> rax = base, rdx = end (0, 0 when absent)
; =============================================================================

%include "ufont.inc"
%include "shape.inc"

extern ucd_scripts

section .text

; ----------------------------------------------------------------------------
; ot_off16 — rdi = base, rsi = end, edx = field offset -> rax
; ----------------------------------------------------------------------------
global ot_off16
ot_off16:
    test rdi, rdi
    jz .none
    lea rax, [rdi + rdx + 2]
    cmp rax, rsi
    ja .none
    BE16 eax, [rdi + rdx]
    test eax, eax
    jz .none
    add rax, rdi
    cmp rax, rsi
    jae .none
    ret
.none:
    xor eax, eax
    ret

; ----------------------------------------------------------------------------
; ot_coverage — rdi = coverage table, rsi = end, edx = glyph -> eax = index
;   (-1: not covered)
; ----------------------------------------------------------------------------
global ot_coverage
ot_coverage:
    test rdi, rdi
    jz .none
    lea rax, [rdi + 4]
    cmp rax, rsi
    ja .none
    BE16 eax, [rdi]
    BE16 ecx, [rdi + 2]                 ; count
    cmp eax, 1
    je .f1
    cmp eax, 2
    jne .none
    ; ranges: start, end, start index
    imul rax, rcx, 6
    lea rax, [rdi + rax + 4]
    cmp rax, rsi
    ja .none
    xor r8d, r8d
    mov r9d, ecx
.r_search:
    cmp r8d, r9d
    jae .none
    lea r10d, [r8 + r9]
    shr r10d, 1
    imul eax, r10d, 6
    lea r11, [rdi + rax + 4]
    BE16 eax, [r11]                     ; start
    cmp edx, eax
    jb .r_lo
    BE16 ecx, [r11 + 2]                 ; end
    cmp edx, ecx
    ja .r_hi
    BE16 ecx, [r11 + 4]
    sub edx, eax
    lea eax, [rcx + rdx]
    ret
.r_lo:
    mov r9d, r10d
    jmp .r_search
.r_hi:
    lea r8d, [r10 + 1]
    jmp .r_search
.f1:
    lea rax, [rdi + rcx * 2 + 4]
    cmp rax, rsi
    ja .none
    xor r8d, r8d
    mov r9d, ecx
.g_search:
    cmp r8d, r9d
    jae .none
    lea r10d, [r8 + r9]
    shr r10d, 1
    BE16 eax, [rdi + r10 * 2 + 4]
    cmp edx, eax
    je .g_found
    jb .g_lo
    lea r8d, [r10 + 1]
    jmp .g_search
.g_lo:
    mov r9d, r10d
    jmp .g_search
.g_found:
    mov eax, r10d
    ret
.none:
    mov eax, -1
    ret

; ----------------------------------------------------------------------------
; ot_class — rdi = class definition, rsi = end, edx = glyph -> eax = class
; ----------------------------------------------------------------------------
global ot_class
ot_class:
    test rdi, rdi
    jz .zero
    lea rax, [rdi + 6]
    cmp rax, rsi
    ja .zero
    BE16 eax, [rdi]
    cmp eax, 1
    je .f1
    cmp eax, 2
    jne .zero
    BE16 ecx, [rdi + 2]                 ; ranges
    imul rax, rcx, 6
    lea rax, [rdi + rax + 4]
    cmp rax, rsi
    ja .zero
    xor r8d, r8d
    mov r9d, ecx
.search:
    cmp r8d, r9d
    jae .zero
    lea r10d, [r8 + r9]
    shr r10d, 1
    imul eax, r10d, 6
    lea r11, [rdi + rax + 4]
    BE16 eax, [r11]
    cmp edx, eax
    jb .lo
    BE16 ecx, [r11 + 2]
    cmp edx, ecx
    ja .hi
    BE16 eax, [r11 + 4]
    ret
.lo:
    mov r9d, r10d
    jmp .search
.hi:
    lea r8d, [r10 + 1]
    jmp .search
.f1:
    BE16 eax, [rdi + 2]                 ; first glyph
    BE16 ecx, [rdi + 4]                 ; count
    sub edx, eax
    jb .zero
    cmp edx, ecx
    jae .zero
    lea rax, [rdi + rdx * 2 + 8]
    cmp rax, rsi
    ja .zero
    BE16 eax, [rdi + rdx * 2 + 6]
    ret
.zero:
    xor eax, eax
    ret

; ----------------------------------------------------------------------------
; otl_gdef_init
; ----------------------------------------------------------------------------
global otl_gdef_init
otl_gdef_init:
    push rbx
    push r12
    sub rsp, 8
    xor eax, eax
    mov [r15 + S_CLASSDEF], rax
    mov [r15 + S_MARKATTACH], rax
    mov [r15 + S_MARKSETS], rax
    mov [r15 + S_NMARKSETS], eax
    mov rax, [r15 + S_FONT]
    mov rbx, [rax + UfontFont_gdef]
    test rbx, rbx
    jz .out
    mov r12, [rax + UfontFont_gdef_len]
    add r12, rbx
    mov [r15 + S_GDEFEND], r12
    lea rax, [rbx + 12]
    cmp rax, r12
    ja .out
    cmp word [rbx], 0x0100              ; major version 1
    jne .out
    mov rdi, rbx
    mov rsi, r12
    mov edx, 4
    call ot_off16
    mov [r15 + S_CLASSDEF], rax
    mov rdi, rbx
    mov rsi, r12
    mov edx, 10
    call ot_off16
    mov [r15 + S_MARKATTACH], rax
    BE16 eax, [rbx + 2]                 ; minor version
    cmp eax, 2
    jb .out
    mov rdi, rbx
    mov rsi, r12
    mov edx, 12
    call ot_off16
    test rax, rax
    jz .out
    lea rcx, [rax + 4]
    cmp rcx, r12
    ja .out
    BE16 ecx, [rax]
    cmp ecx, 1
    jne .out
    BE16 ecx, [rax + 2]
    lea rdx, [rax + rcx * 4 + 4]
    cmp rdx, r12
    ja .out
    mov [r15 + S_MARKSETS], rax
    mov [r15 + S_NMARKSETS], ecx
.out:
    add rsp, 8
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------------
; otl_glyph_props — edi = glyph -> eax
; ----------------------------------------------------------------------------
global otl_glyph_props
otl_glyph_props:
    push rbx
    mov ebx, edi
    mov rdi, [r15 + S_CLASSDEF]
    mov rsi, [r15 + S_GDEFEND]
    mov edx, ebx
    call ot_class
    cmp eax, 1
    je .base
    cmp eax, 2
    je .lig
    cmp eax, 3
    je .mark
    xor eax, eax
    jmp .out
.base:
    mov eax, GP_BASE
    jmp .out
.lig:
    mov eax, GP_LIGATURE
    jmp .out
.mark:
    mov rdi, [r15 + S_MARKATTACH]
    mov rsi, [r15 + S_GDEFEND]
    mov edx, ebx
    call ot_class
    movzx eax, al
    shl eax, 8
    or eax, GP_MARK
.out:
    pop rbx
    ret

; ----------------------------------------------------------------------------
; otl_mark_set_covers — edi = set, esi = glyph -> eax 1 / 0
; ----------------------------------------------------------------------------
global otl_mark_set_covers
otl_mark_set_covers:
    xor eax, eax
    cmp edi, [r15 + S_NMARKSETS]
    jae .out
    mov r8, [r15 + S_MARKSETS]
    mov r9, [r15 + S_GDEFEND]
    mov edx, esi
    BE32 eax, [r8 + rdi * 4 + 4]
    test eax, eax
    jz .no
    add rax, r8
    cmp rax, r9
    jae .no
    mov rdi, rax
    mov rsi, r9
    call ot_coverage
    not eax                             ; -1 -> 0
    test eax, eax
    setnz al
    movzx eax, al
.out:
    ret
.no:
    xor eax, eax
    ret

; ----------------------------------------------------------------------------
; otl_table — edi = 0 GSUB / 1 GPOS -> rax = base, rdx = end (0 absent or
;   damaged header)
; ----------------------------------------------------------------------------
global otl_table
otl_table:
    mov rcx, [r15 + S_FONT]
    test edi, edi
    jnz .gpos
    mov rax, [rcx + UfontFont_gsub]
    mov rdx, [rcx + UfontFont_gsub_len]
    jmp .have
.gpos:
    mov rax, [rcx + UfontFont_gpos]
    mov rdx, [rcx + UfontFont_gpos_len]
.have:
    test rax, rax
    jz .none
    cmp rdx, 10
    jb .none
    cmp word [rax], 0x0100
    jne .none
    add rdx, rax
    ret
.none:
    xor eax, eax
    xor edx, edx
    ret

; ----------------------------------------------------------------------------
; otl_select — edi = table: the script record (tags of the run's script, then
;   DFLT, dflt, latn) and language system; S_SR, S_CHOSEN, S_LS
; ----------------------------------------------------------------------------
global otl_select
otl_select:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    sub rsp, 32                         ; [rsp] the tags to try, [rsp + 24] count
    mov ebp, edi
    mov qword [r15 + S_SR + rbp * 8], 0
    mov qword [r15 + S_LS + rbp * 8], 0
    mov dword [r15 + S_CHOSEN + rbp * 4], 0xFFFF
    call otl_table
    test rax, rax
    jz .out
    mov r12, rax                        ; table
    mov r13, rdx                        ; end
    mov rdi, r12
    mov rsi, r13
    mov edx, 4
    call ot_off16
    test rax, rax
    jz .out
    mov r14, rax                        ; script list
    ; the tags: new | '3' (not for Myanmar), new, old; then the defaults
    xor ebx, ebx
    mov eax, [r15 + S_SCRIPT]
    cmp eax, 3
    jb .defaults
    imul eax, eax, 12
    lea rcx, [rel ucd_scripts]
    add rcx, rax
    mov eax, [rcx + 8]                  ; new tag
    test eax, eax
    jz .old
    cmp eax, 'mym2'
    je .new
    mov edx, eax
    and edx, 0x00FFFFFF
    or edx, '3' << 24
    mov [rsp + rbx * 4], edx
    inc ebx
.new:
    mov [rsp + rbx * 4], eax
    inc ebx
.old:
    mov eax, [rcx + 4]
    mov [rsp + rbx * 4], eax
    inc ebx
.defaults:
    mov dword [rsp + rbx * 4], 'DFLT'
    mov dword [rsp + rbx * 4 + 4], 'dflt'
    mov dword [rsp + rbx * 4 + 8], 'latn'
    add ebx, 3
    mov [rsp + 24], ebx
    ; the first tag the list has
    lea rax, [r14 + 2]
    cmp rax, r13
    ja .out
    BE16 r9d, [r14]                     ; records
    imul rax, r9, 6
    lea rax, [r14 + rax + 2]
    cmp rax, r13
    ja .out
    xor ebx, ebx
.tag:
    cmp ebx, [rsp + 24]
    jae .out
    mov r8d, [rsp + rbx * 4]
    xor ecx, ecx
.rec:
    cmp ecx, r9d
    jae .next_tag
    imul eax, ecx, 6
    cmp [r14 + rax + 2], r8d
    je .found
    inc ecx
    jmp .rec
.next_tag:
    inc ebx
    jmp .tag
.found:
    mov [r15 + S_CHOSEN + rbp * 4], r8d
    lea rdi, [r14 + rax + 2]
    BE16 edx, [rdi + 4]
    test edx, edx
    jz .out
    lea rdi, [r14 + rdx]
    cmp rdi, r13
    jae .out
    mov [r15 + S_SR + rbp * 8], rdi
    mov rbx, rdi                        ; the script table
    lea rax, [rbx + 4]
    cmp rax, r13
    ja .out
    ; the language asked for, else the default
    mov r8d, [r15 + S_LANG]
    test r8d, r8d
    jz .default
    BE16 ecx, [rbx + 2]
    imul rax, rcx, 6
    lea rax, [rbx + rax + 4]
    cmp rax, r13
    ja .default
    xor edx, edx
.lang:
    cmp edx, ecx
    jae .default
    imul eax, edx, 6
    cmp [rbx + rax + 4], r8d
    je .lang_found
    inc edx
    jmp .lang
.lang_found:
    lea rdi, [rbx]
    mov rsi, r13
    lea edx, [rax + 8]
    call ot_off16
    jmp .ls
.default:
    mov rdi, rbx
    mov rsi, r13
    xor edx, edx
    call ot_off16
.ls:
    test rax, rax
    jz .out
    lea rcx, [rax + 6]
    cmp rcx, r13
    ja .out
    BE16 ecx, [rax + 4]
    lea rcx, [rax + rcx * 2 + 6]
    cmp rcx, r13
    ja .out
    mov [r15 + S_LS + rbp * 8], rax
.out:
    add rsp, 32
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; ----------------------------------------------------------------------------
; otl_feature_record — edi = table, esi = feature index -> rax = the feature
;   record (tag, offset), 0
; ----------------------------------------------------------------------------
otl_feature_record:
    push rbx
    push r12
    sub rsp, 8
    mov r12d, esi
    call otl_table
    test rax, rax
    jz .none
    mov rbx, rdx
    mov rdi, rax
    mov rsi, rdx
    mov edx, 6
    call ot_off16
    test rax, rax
    jz .none
    lea rcx, [rax + 2]
    cmp rcx, rbx
    ja .none
    BE16 ecx, [rax]
    cmp r12d, ecx
    jae .none
    imul rcx, r12, 6
    lea rcx, [rax + rcx + 2]
    lea rdx, [rcx + 6]
    cmp rdx, rbx
    ja .none
    mov rax, rcx
    jmp .out
.none:
    xor eax, eax
.out:
    add rsp, 8
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------------
; otl_feature_tag — edi = table, esi = feature index -> eax = tag (0 none)
; ----------------------------------------------------------------------------
global otl_feature_tag
otl_feature_tag:
    sub rsp, 8
    call otl_feature_record
    add rsp, 8
    test rax, rax
    jz .none
    mov eax, [rax]
    ret
.none:
    xor eax, eax
    ret

; ----------------------------------------------------------------------------
; otl_feature_index — edi = table, esi = tag -> eax = the first feature index
;   in the language system with that tag, -1
; ----------------------------------------------------------------------------
global otl_feature_index
otl_feature_index:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    mov ebp, edi
    mov r12d, esi
    mov rbx, [r15 + S_LS + rbp * 8]
    test rbx, rbx
    jz .none
    BE16 r13d, [rbx + 4]
    xor r14d, r14d
.loop:
    cmp r14d, r13d
    jae .none
    BE16 esi, [rbx + r14 * 2 + 6]
    mov edi, ebp
    call otl_feature_tag
    cmp eax, r12d
    je .found
    inc r14d
    jmp .loop
.found:
    BE16 eax, [rbx + r14 * 2 + 6]
    jmp .out
.none:
    mov eax, -1
.out:
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; ----------------------------------------------------------------------------
; otl_feature_lookups — edi = table, esi = feature index -> rax = lookup
;   indices (big-endian u16), ecx = count (0 when absent)
; ----------------------------------------------------------------------------
global otl_feature_lookups
otl_feature_lookups:
    push rbx
    push r12
    push r13
    mov r12d, edi
    call otl_feature_record
    test rax, rax
    jz .none
    mov rbx, rax
    mov edi, r12d
    call otl_table
    mov r13, rdx                        ; end
    BE16 ecx, [rbx + 4]
    mov rdi, rax
    mov rsi, rdx
    mov edx, 6
    push rcx
    sub rsp, 8
    call ot_off16                       ; the feature list
    add rsp, 8
    pop rcx
    test rax, rax
    jz .none
    add rax, rcx                        ; the feature table
    lea rcx, [rax + 4]
    cmp rcx, r13
    ja .none
    BE16 ecx, [rax + 2]
    lea rdx, [rax + rcx * 2 + 4]
    cmp rdx, r13
    ja .none
    add rax, 4
    jmp .out
.none:
    xor eax, eax
    xor ecx, ecx
.out:
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------------
; otl_lookup_count — edi = table -> eax
; otl_lookup — edi = table, esi = index -> rax = the lookup table, 0
; ----------------------------------------------------------------------------
global otl_lookup_count
otl_lookup_count:
    sub rsp, 8
    call otl_lookup_list
    add rsp, 8
    ret

; -> rax = lookup list, ecx = count, rdx = end
otl_lookup_list:
    push rbx
    call otl_table
    test rax, rax
    jz .none
    mov rbx, rdx
    mov rdi, rax
    mov rsi, rdx
    mov edx, 8
    call ot_off16
    test rax, rax
    jz .none
    lea rcx, [rax + 2]
    cmp rcx, rbx
    ja .none
    BE16 ecx, [rax]
    lea rdx, [rax + rcx * 2 + 2]
    cmp rdx, rbx
    ja .none
    mov rdx, rbx
    mov eax, ecx
    jmp .ret
.none:
    xor eax, eax
    xor ecx, ecx
    xor edx, edx
.ret:
    pop rbx
    ret

global otl_lookup
otl_lookup:
    push rbx
    mov ebx, esi
    call otl_lookup_list_ptr
    test rax, rax
    jz .none
    cmp ebx, ecx
    jae .none
    mov rdi, rax
    mov rsi, rdx
    lea edx, [rbx * 2 + 2]
    call ot_off16
    test rax, rax
    jz .none
    lea rcx, [rax + 6]
    cmp rcx, rsi
    ja .none
    pop rbx
    ret
.none:
    xor eax, eax
    pop rbx
    ret

; -> rax = lookup list pointer, ecx = count, rdx = end
otl_lookup_list_ptr:
    push rbx
    call otl_table
    test rax, rax
    jz .none
    mov rbx, rdx
    mov rdi, rax
    mov rsi, rdx
    mov edx, 8
    call ot_off16
    test rax, rax
    jz .none
    lea rcx, [rax + 2]
    cmp rcx, rbx
    ja .none
    BE16 ecx, [rax]
    lea rdx, [rax + rcx * 2 + 2]
    cmp rdx, rbx
    ja .none
    mov rdx, rbx
    pop rbx
    ret
.none:
    xor eax, eax
    xor ecx, ecx
    xor edx, edx
    pop rbx
    ret
