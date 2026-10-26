; =============================================================================
; Utkarsha OS — lib/ufont/layout/fallback.asm
; =============================================================================
; Mark positioning for fonts without GPOS (HarfBuzz's fallback, as
; tools/shapemodel.py models it): each mark goes around its base by its
; combining class, from the glyphs' boxes - centred above or below, or to a
; corner, stacked away from the base by a sixteenth of the em; on a
; ligature, over the component it belongs to.
;
;   ufl_fb_recategorize   before GSUB: the combining classes Unicode gives
;                         the points of Hebrew, Arabic, Syriac, Thai, Lao and
;                         Tibetan mapped to the positions they mean (above,
;                         below, ...)
;   ufl_fb_position       after GPOS: every cluster's marks placed
;   ufl_fb_zero(edi = start, esi = end)  nonspacing marks made zero-width
;                         (their offsets take the advance back when the plan
;                         adjusts marks, left to right)
; =============================================================================

%include "ufont.inc"
%include "shape.inc"

extern ufont_extents
extern ufont_advance

; combining classes
%define CC_ATTACHED_BELOW_LEFT  200
%define CC_ATTACHED_BELOW       202
%define CC_ATTACHED_ABOVE       214
%define CC_ATTACHED_ABOVE_RIGHT 216
%define CC_BELOW_LEFT           218
%define CC_BELOW                220
%define CC_BELOW_RIGHT          222
%define CC_ABOVE_LEFT           228
%define CC_ABOVE                230
%define CC_ABOVE_RIGHT          232
%define CC_DOUBLE_BELOW         233
%define CC_DOUBLE_ABOVE         234

section .rodata
; the modified classes below 200 -> the position they mean
fb_recat:
    db 0, 1, 2, 222, 4, 5, 6, 7, 8, 9, 232, 228, 12, 214, 228, 220, 220, 220, 220, 220
    db 220, 220, 220, 220, 220, 220, 230, 230, 230, 230, 220, 230, 230, 220, 230, 230, 230, 37, 38, 39
    db 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59
    db 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79
    db 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99
    db 100, 101, 102, 103, 104, 105, 106, 232, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 220, 119
    db 120, 121, 230, 123, 124, 125, 126, 127, 128, 220, 130, 220, 230, 133, 134, 135, 136, 137, 138, 139
    db 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159
    db 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179
    db 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191, 192, 193, 194, 195, 196, 197, 198, 199
; Thai and Lao marks with class 0 that go above
fb_thai_above_right: dd 0x0E31, 0x0E34, 0x0E35, 0x0E36, 0x0E37, 0x0E47, 0x0E4C, 0x0E4D, 0x0E4E, 0
fb_lao_above: dd 0x0EB1, 0x0EB4, 0x0EB5, 0x0EB6, 0x0EB7, 0x0EBB, 0x0ECC, 0x0ECD, 0

section .text

; ----------------------------------------------------------------------------
; ufl_fb_recategorize: nonspacing marks' classes as positions
; ----------------------------------------------------------------------------
global ufl_fb_recategorize
ufl_fb_recategorize:
    mov rsi, [r15 + S_INFO]
    mov ecx, [r15 + S_LEN]
.each:
    test ecx, ecx
    jz .out
    cmp byte [rsi + GI_GC], GC_MN
    jne .next
    movzx eax, byte [rsi + GI_MCC]
    cmp eax, 200
    jae .next
    mov edi, [rsi + GI_CP]
    mov edx, edi
    and edx, ~0xFF
    cmp edx, 0x0E00                     ; Thai and Lao
    jne .table
    test eax, eax
    jnz .phinthu
    mov eax, CC_ABOVE_RIGHT
    lea rdx, [rel fb_thai_above_right]
    call .in_list
    je .store
    mov eax, CC_ABOVE
    lea rdx, [rel fb_lao_above]
    call .in_list
    je .store
    xor eax, eax
    cmp edi, 0x0EBC
    jne .table
    mov eax, CC_BELOW
    jmp .store
.phinthu:
    cmp edi, 0x0E3A
    jne .table
    mov eax, CC_BELOW_RIGHT
    jmp .store
.table:
    lea rdx, [rel fb_recat]
    movzx eax, byte [rdx + rax]
.store:
    mov [rsi + GI_MCC], al
.next:
    add rsi, GI_SIZE
    dec ecx
    jmp .each
.out:
    ret
; edi in the 0-terminated dd list at rdx -> ZF
.in_list:
    cmp dword [rdx], 0
    je .not_in
    cmp [rdx], edi
    je .in
    add rdx, 4
    jmp .in_list
.not_in:
    cmp edx, -1                         ; ZF clear
.in:
    ret

; ----------------------------------------------------------------------------
; fb_is_mark — eax = index -> ZF set when it is a Unicode mark (Mn, Mc, Me)
; fb_is_skipped — eax = index -> ZF clear when hidden or a default ignorable
; ----------------------------------------------------------------------------
fb_is_mark:
    shl rax, 5
    add rax, [r15 + S_INFO]
    movzx eax, byte [rax + GI_GC]
    sub eax, GC_MC
    cmp eax, 2
    ja .no
    xor eax, eax
.no:
    ret

fb_is_skipped:
    shl rax, 5
    add rax, [r15 + S_INFO]
    test byte [rax + GI_UF], UF_HIDDEN
    jnz .out
    test byte [rax + GI_UF], UF_IGN
    jz .out
    test word [rax + GI_PROPS], GP_SUBSTITUTED
    sete al
    test al, al
.out:
    ret

; ----------------------------------------------------------------------------
; ufl_fb_zero — edi = start, esi = end: nonspacing marks zero-width
; ----------------------------------------------------------------------------
global ufl_fb_zero
ufl_fb_zero:
    xor r8d, r8d                        ; adjust
    test byte [r15 + S_PFLAGS], PF_ADJUST
    jz .each
    cmp byte [r15 + S_RTL], 0
    sete r8b
.each:
    cmp edi, esi
    jae .out
    mov eax, edi
    shl rax, 5
    add rax, [r15 + S_INFO]
    cmp byte [rax + GI_GC], GC_MN
    jne .next
    imul ecx, edi, GPOS_SIZE
    add rcx, [r15 + S_POS]
    test r8d, r8d
    jz .zero
    mov eax, [rcx + GPOS_XA]
    sub [rcx + GPOS_XO], eax
    mov eax, [rcx + GPOS_YA]
    sub [rcx + GPOS_YO], eax
.zero:
    mov dword [rcx + GPOS_XA], 0
    mov dword [rcx + GPOS_YA], 0
.next:
    inc edi
    jmp .each
.out:
    ret

; ----------------------------------------------------------------------------
; ufl_fb_position: the marks of every cluster around their bases (a cluster
;   runs to the next character that is not a mark, hidden or ignorable)
; ----------------------------------------------------------------------------
global ufl_fb_position
ufl_fb_position:
    push rbx
    push rbp
    push r12
    xor ebx, ebx                        ; start
    mov ebp, 1
.each:
    cmp ebp, [r15 + S_LEN]
    jae .last
    mov eax, ebp
    call fb_is_mark
    jz .next
    mov eax, ebp
    call fb_is_skipped
    jnz .next
    mov edi, ebx
    mov esi, ebp
    call fb_cluster
    mov ebx, ebp
.next:
    inc ebp
    jmp .each
.last:
    mov edi, ebx
    mov esi, [r15 + S_LEN]
    call fb_cluster
    pop r12
    pop rbp
    pop rbx
    ret

; fb_cluster — edi = start, esi = end: each base and the marks after it
fb_cluster:
    push rbx
    push rbp
    push r12
    mov eax, esi
    sub eax, edi
    cmp eax, 2
    jl .out
    mov ebx, edi                        ; i
    mov r12d, esi
.each:
    cmp ebx, r12d
    jae .out
    mov eax, ebx
    call fb_is_mark
    jz .next
    lea ebp, [rbx + 1]                  ; j: past its marks (hidden and ignorables skipped)
.marks:
    cmp ebp, r12d
    jae .around
    mov eax, ebp
    call fb_is_skipped
    jnz .mark_next
    mov eax, ebp
    call fb_is_mark
    jnz .around
.mark_next:
    inc ebp
    jmp .marks
.around:
    mov edi, ebx
    mov esi, ebp
    call fb_around
    lea ebx, [rbp - 1]
.next:
    inc ebx
    jmp .each
.out:
    pop r12
    pop rbp
    pop rbx
    ret

; ----------------------------------------------------------------------------
; fb_around — edi = base, esi = end: the marks in (base, end) placed
; ----------------------------------------------------------------------------
%define FA_BASE     0                   ; the base's box: x bearing, y bearing, width, height
%define FA_COMP     16                  ; the ligature component's
%define FA_CLUSTER  32                  ; what the marks of one class stack on
%define FA_XOFF     48                  ; back to the base
%define FA_YOFF     52
%define FA_LASTCOMP 56
%define FA_LASTCC   60
%define FA_SIZE     64

fb_around:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    sub rsp, FA_SIZE
    mov ebx, edi
    mov r12d, esi
    mov rax, rbx
    shl rax, 5
    add rax, [r15 + S_INFO]
    mov esi, [rax + GI_GLYPH]
    mov rdi, [r15 + S_FONT]
    call ufont_extents
    test eax, eax
    jnz .have
    lea edi, [rbx + 1]
    mov esi, r12d
    call ufl_fb_zero
    jmp .out
.have:
    ; the base: from the origin, its advance wide, raised with its offset
    imul eax, ebx, GPOS_SIZE
    add rax, [r15 + S_POS]
    add edx, [rax + GPOS_YO]
    mov dword [rsp + FA_BASE], 0
    mov [rsp + FA_BASE + 4], edx
    mov [rsp + FA_BASE + 12], r9d
    mov rax, rbx
    shl rax, 5
    add rax, [r15 + S_INFO]
    mov esi, [rax + GI_GLYPH]
    mov rdi, [r15 + S_FONT]
    call ufont_advance
    mov [rsp + FA_BASE + 8], eax
    ; the ligature: its id and components
    mov rax, rbx
    shl rax, 5
    add rax, [r15 + S_INFO]
    movzx r13d, byte [rax + GI_LIG]
    mov r14d, 1
    test word [rax + GI_PROPS], GP_LIGATURE
    jz .num
    test r13d, 0x10
    jz .num
    mov r14d, r13d
    and r14d, 0x0F
.num:
    shr r13d, 5                         ; id
    ; left to right the marks come after the base's advance: offset back
    xor eax, eax
    xor ecx, ecx
    cmp byte [r15 + S_RTL], 0
    jne .offsets
    imul edx, ebx, GPOS_SIZE
    add rdx, [r15 + S_POS]
    sub eax, [rdx + GPOS_XA]
    sub ecx, [rdx + GPOS_YA]
.offsets:
    mov [rsp + FA_XOFF], eax
    mov [rsp + FA_YOFF], ecx
    movdqu xmm0, [rsp + FA_BASE]
    movdqu [rsp + FA_COMP], xmm0
    movdqu [rsp + FA_CLUSTER], xmm0
    mov dword [rsp + FA_LASTCOMP], -1
    mov dword [rsp + FA_LASTCC], 255
    lea ebp, [rbx + 1]
.each:
    cmp ebp, r12d
    jae .out
    mov rax, rbp
    shl rax, 5
    add rax, [r15 + S_INFO]
    imul edx, ebp, GPOS_SIZE
    add rdx, [r15 + S_POS]
    cmp byte [rax + GI_MCC], 0
    jne .mark
    ; not a mark (class 0): the offsets move past it
    mov ecx, [rdx + GPOS_XA]
    mov edi, [rdx + GPOS_YA]
    cmp byte [r15 + S_RTL], 0
    jne .add
    neg ecx
    neg edi
.add:
    add [rsp + FA_XOFF], ecx
    add [rsp + FA_YOFF], edi
    jmp .next
.mark:
    cmp r14d, 1
    jbe .class
    ; the component it is on (the last when it is not on this ligature)
    movzx esi, byte [rax + GI_LIG]
    xor edi, edi
    test esi, 0x10
    jnz .comp
    mov edi, esi
    and edi, 0x0F
.comp:
    dec edi                             ; unsigned: 0 - 1 is out of range
    shr esi, 5
    test r13d, r13d
    jz .last_comp
    cmp esi, r13d
    jne .last_comp
    cmp edi, r14d
    jb .comp_have
.last_comp:
    lea edi, [r14 - 1]
.comp_have:
    cmp edi, [rsp + FA_LASTCOMP]
    je .class
    mov [rsp + FA_LASTCOMP], edi
    mov dword [rsp + FA_LASTCC], 255
    movdqu xmm0, [rsp + FA_BASE]
    movdqu [rsp + FA_COMP], xmm0
    mov eax, edi                        ; its slot of the advance (right to left: from the end)
    cmp byte [r15 + S_RTL], 0
    je .slot
    lea eax, [r14 - 1]
    sub eax, edi
.slot:
    imul eax, [rsp + FA_COMP + 8]
    cdq
    idiv r14d
    add [rsp + FA_COMP], eax
    mov eax, [rsp + FA_COMP + 8]
    cdq
    idiv r14d
    mov [rsp + FA_COMP + 8], eax
    mov rax, rbp
    shl rax, 5
    add rax, [r15 + S_INFO]
.class:
    movzx edx, byte [rax + GI_MCC]
    cmp edx, [rsp + FA_LASTCC]
    je .place
    mov [rsp + FA_LASTCC], edx
    movdqu xmm0, [rsp + FA_COMP]
    movdqu [rsp + FA_CLUSTER], xmm0
.place:
    mov edi, ebp
    lea rsi, [rsp + FA_CLUSTER]
    call fb_mark
    imul edx, ebp, GPOS_SIZE
    add rdx, [r15 + S_POS]
    mov dword [rdx + GPOS_XA], 0
    mov dword [rdx + GPOS_YA], 0
    mov eax, [rsp + FA_XOFF]
    add [rdx + GPOS_XO], eax
    mov eax, [rsp + FA_YOFF]
    add [rdx + GPOS_YO], eax
.next:
    inc ebp
    jmp .each
.out:
    add rsp, FA_SIZE
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; ----------------------------------------------------------------------------
; fb_mark — edi = mark, rsi = the box it goes on (updated: the next mark of
;   the class stacks past it), edx = its class: its offsets
; ----------------------------------------------------------------------------
%define FK_X        0                   ; the mark's box
%define FK_Y        4
%define FK_W        8
%define FK_H        12
%define FK_GAP      16                  ; a sixteenth of the em

fb_mark:
    push rbx
    push rbp
    push r12
    push r13
    sub rsp, 24
    mov ebx, edi
    mov r12, rsi
    mov ebp, edx
    mov rax, rbx
    shl rax, 5
    add rax, [r15 + S_INFO]
    mov esi, [rax + GI_GLYPH]
    mov rdi, [r15 + S_FONT]
    call ufont_extents
    test eax, eax
    jz .out
    mov [rsp + FK_X], ecx
    mov [rsp + FK_Y], edx
    mov [rsp + FK_W], r8d
    mov [rsp + FK_H], r9d
    mov rax, [r15 + S_FONT]
    mov eax, [rax + UfontFont_upem]
    shr eax, 4
    mov [rsp + FK_GAP], eax
    imul r13d, ebx, GPOS_SIZE
    add r13, [r15 + S_POS]
    ; x
    cmp ebp, CC_DOUBLE_BELOW
    je .x_double
    cmp ebp, CC_DOUBLE_ABOVE
    je .x_double
    cmp ebp, CC_ATTACHED_BELOW_LEFT
    je .x_left
    cmp ebp, CC_BELOW_LEFT
    je .x_left
    cmp ebp, CC_ABOVE_LEFT
    je .x_left
    cmp ebp, CC_ATTACHED_ABOVE_RIGHT
    je .x_right
    cmp ebp, CC_BELOW_RIGHT
    je .x_right
    cmp ebp, CC_ABOVE_RIGHT
    je .x_right
    mov eax, [r12 + 8]                  ; centred
    sub eax, [rsp + FK_W]
    cdq
    sub eax, edx
    sar eax, 1
    add eax, [r12]
    sub eax, [rsp + FK_X]
    jmp .x_set
.x_double:
    mov eax, [rsp + FK_W]               ; centred on the base's end (right to left: its start)
    cdq
    sub eax, edx
    sar eax, 1
    mov ecx, eax
    mov eax, [r12]
    cmp byte [r15 + S_RTL], 0
    jne .x_double_rtl
    add eax, [r12 + 8]
.x_double_rtl:
    sub eax, ecx
    sub eax, [rsp + FK_X]
    jmp .x_set
.x_left:
    mov eax, [r12]
    sub eax, [rsp + FK_X]
    jmp .x_set
.x_right:
    mov eax, [r12]
    add eax, [r12 + 8]
    sub eax, [rsp + FK_W]
    sub eax, [rsp + FK_X]
.x_set:
    mov [r13 + GPOS_XO], eax
    mov dword [r13 + GPOS_YO], 0
    ; y
    mov ecx, [rsp + FK_GAP]
    cmp ebp, CC_DOUBLE_BELOW
    je .below_gap
    cmp ebp, CC_BELOW_LEFT
    je .below_gap
    cmp ebp, CC_BELOW
    je .below_gap
    cmp ebp, CC_BELOW_RIGHT
    je .below_gap
    cmp ebp, CC_ATTACHED_BELOW_LEFT
    je .below
    cmp ebp, CC_ATTACHED_BELOW
    je .below
    cmp ebp, CC_DOUBLE_ABOVE
    je .above_gap
    cmp ebp, CC_ABOVE_LEFT
    je .above_gap
    cmp ebp, CC_ABOVE
    je .above_gap
    cmp ebp, CC_ABOVE_RIGHT
    je .above_gap
    cmp ebp, CC_ATTACHED_ABOVE
    je .above
    cmp ebp, CC_ATTACHED_ABOVE_RIGHT
    je .above
    jmp .out
.below_gap:
    sub [r12 + 12], ecx
.below:
    mov eax, [r12 + 4]                  ; under the box's bottom
    add eax, [r12 + 12]
    sub eax, [rsp + FK_Y]
    test ecx, ecx
    setg dl
    test eax, eax
    setg dh
    cmp dl, dh
    jne .below_set
    sub [r12 + 12], eax                 ; it would go the wrong way: the bottom moves instead
    xor eax, eax
.below_set:
    mov [r13 + GPOS_YO], eax
    mov eax, [rsp + FK_H]
    add [r12 + 12], eax
    jmp .out
.above_gap:
    add [r12 + 4], ecx
    sub [r12 + 12], ecx
.above:
    mov eax, [r12 + 4]                  ; over the box's top
    mov edx, [rsp + FK_Y]
    add edx, [rsp + FK_H]
    sub eax, edx
    test ecx, ecx
    setg dl
    test eax, eax
    setg dh
    cmp dl, dh
    je .above_set
    mov r8d, eax                        ; the wrong way: half of it taken back
    neg eax
    cdq
    sub eax, edx
    sar eax, 1
    add [r12 + 4], eax
    sub [r12 + 12], eax
    add eax, r8d
.above_set:
    mov [r13 + GPOS_YO], eax
    mov eax, [rsp + FK_H]
    sub [r12 + 4], eax
    add [r12 + 12], eax
.out:
    add rsp, 24
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret
