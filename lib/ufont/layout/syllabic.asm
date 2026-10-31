; =============================================================================
; Utkarsha OS — lib/ufont/layout/syllabic.asm
; =============================================================================
; What the syllabic shapers (Khmer, Myanmar, the Universal Shaping Engine)
; share, as HarfBuzz's hb-ot-shaper-syllabic:
;
;   ufl_syl_find(rdi = machine)   each record's syllable (GI_SYL: serial << 4 |
;                                 type, serials 1 .. 15) by the longest match of
;                                 the machine's automaton over the GI_CAT
;                                 categories -> eax 1 when a broken cluster
;                                 was found
;   ufl_syl_dotted_circles(edi = broken type, esi = the dotted circle's
;                                 category, edx = a repha category it goes
;                                 after (-1: none), ecx = its position (-1:
;                                 none)): a dotted circle at the start of every
;                                 broken cluster, when the font has one
;   ufl_syl_clear                 the syllables cleared (a pause: the features
;                                 after it are not held to a syllable)
;
; A machine (generated, layout/indic_table.asm): dq classes (db per category
; 0 .. 63), dq transitions (db per state and class, 255 none), dq accept (db
; per state, 255 none), dd classes, dd the broken cluster's type.
; =============================================================================

%include "ufont.inc"
%include "shape.inc"

extern ufl_norm_glyph
extern ufl_buf_clear_output
extern ufl_buf_sync
extern ufl_buf_next_glyph
extern ufl_buf_output_info

%define SM_CLASSES  0
%define SM_DFA      8
%define SM_ACCEPT   16
%define SM_NCLASSES 24
%define SM_BROKEN   28

section .text

; ----------------------------------------------------------------------------
; ufl_syl_find
; ----------------------------------------------------------------------------
global ufl_syl_find
ufl_syl_find:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    mov r14, rdi                        ; the machine
    mov r12, [r14 + SM_CLASSES]
    mov r13, [r14 + SM_DFA]
    mov ebp, 1                          ; serial
    xor ebx, ebx                        ; p
    xor r11d, r11d                      ; a broken cluster found
.syllable:
    cmp ebx, [r15 + S_LEN]
    jae .done
    xor ecx, ecx                        ; state
    mov r8d, ebx                        ; q
    lea r9d, [rbx + 1]                  ; the match's end (one character at least)
    xor r10d, r10d                      ; its type
.step:
    cmp r8d, [r15 + S_LEN]
    jae .have
    mov eax, r8d
    shl rax, 5
    add rax, [r15 + S_INFO]
    movzx eax, byte [rax + GI_CAT]
    and eax, 63
    movzx eax, byte [r12 + rax]         ; class
    imul ecx, [r14 + SM_NCLASSES]
    add ecx, eax
    movzx ecx, byte [r13 + rcx]
    cmp ecx, 255
    je .have
    inc r8d
    mov rax, [r14 + SM_ACCEPT]
    movzx eax, byte [rax + rcx]
    cmp eax, 255
    je .step
    mov r9d, r8d
    mov r10d, eax
    jmp .step
.have:
    cmp r10d, [r14 + SM_BROKEN]
    jne .mark
    mov r11d, 1
.mark:
    mov eax, ebp
    shl eax, 4
    or eax, r10d
.set:
    cmp ebx, r9d
    jae .serial
    mov rdx, rbx
    shl rdx, 5
    add rdx, [r15 + S_INFO]
    mov [rdx + GI_SYL], al
    inc ebx
    jmp .set
.serial:
    inc ebp
    cmp ebp, 16
    jne .syllable
    mov ebp, 1
    jmp .syllable
.done:
    mov eax, r11d
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; ----------------------------------------------------------------------------
; ufl_syl_dotted_circles
; ----------------------------------------------------------------------------
global ufl_syl_dotted_circles
ufl_syl_dotted_circles:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    sub rsp, 48                         ; the dotted circle record, the arguments
    mov [rsp + 32], edi                 ; broken type
    mov [rsp + 36], esi                 ; category
    mov [rsp + 40], edx                 ; repha category
    mov [rsp + 44], ecx                 ; position
    mov edi, 0x25CC
    call ufl_norm_glyph
    test eax, eax
    jz .out
    mov r13d, eax
    call ufl_buf_clear_output
    mov dword [r15 + S_IDX], 0
    xor r12d, r12d                      ; last syllable
.each:
    mov eax, [r15 + S_IDX]
    cmp eax, [r15 + S_LEN]
    jae .done
    mov rbx, rax
    shl rbx, 5
    add rbx, [r15 + S_INFO]
    movzx eax, byte [rbx + GI_SYL]
    cmp eax, r12d
    je .next
    mov ecx, eax
    and ecx, 0x0F
    cmp ecx, [rsp + 32]
    jne .next
    mov r12d, eax
    ; a record of zeros but for these
    xor eax, eax
    mov [rsp], rax
    mov [rsp + 8], rax
    mov [rsp + 16], rax
    mov [rsp + 24], rax
    mov dword [rsp + GI_CP], 0x25CC
    mov [rsp + GI_GLYPH], r13d
    mov eax, [rbx + GI_CLUSTER]
    mov [rsp + GI_CLUSTER], eax
    mov eax, [rbx + GI_MASK]
    mov [rsp + GI_MASK], eax
    mov [rsp + GI_SYL], r12b
    mov byte [rsp + GI_GC], GC_CC
    mov eax, [rsp + 36]
    mov [rsp + GI_CAT], al
    mov eax, [rsp + 44]
    cmp eax, -1
    je .repha
    mov [rsp + GI_POS], al
.repha:
    cmp dword [rsp + 40], -1
    je .put
    mov eax, [r15 + S_IDX]
    cmp eax, [r15 + S_LEN]
    jae .put
    mov rbx, rax
    shl rbx, 5
    add rbx, [r15 + S_INFO]
    movzx eax, byte [rbx + GI_SYL]
    cmp eax, r12d
    jne .put
    movzx eax, byte [rbx + GI_CAT]
    cmp eax, [rsp + 40]
    jne .put
    call ufl_buf_next_glyph
    jmp .repha
.put:
    mov rsi, rsp
    call ufl_buf_output_info
    jmp .each
.next:
    call ufl_buf_next_glyph
    jmp .each
.done:
    call ufl_buf_sync
.out:
    add rsp, 48
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; ----------------------------------------------------------------------------
; ufl_syl_clear
; ----------------------------------------------------------------------------
global ufl_syl_clear
ufl_syl_clear:
    xor ecx, ecx
.each:
    cmp ecx, [r15 + S_LEN]
    jae .done
    mov rax, rcx
    shl rax, 5
    add rax, [r15 + S_INFO]
    mov byte [rax + GI_SYL], 0
    inc ecx
    jmp .each
.done:
    ret
