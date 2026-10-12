; ============================================================================
; Kern — Kerning (kern table format 0 + advance widths from hmtx)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/font.inc"

section .text

; ---------------------------------------------------------------------------
; kern_get
;   IN: rdi = font*, rsi = left glyph, rdx = right glyph
;   OUT: rax = adjustment in font units (signed, usually <= 0)
; ---------------------------------------------------------------------------
global kern_get
kern_get:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    ASSERT_PTR rbx
    mov r14, [rbx + TtfFont.kern]
    test r14, r14
    jz .none
    movzx eax, word [r14 + 2]  ; nTables BE
    xchg al, ah
    mov ecx, eax
    add r14, 4
.table_loop:
    test ecx, ecx
    jz .none
    movzx eax, word [r14 + 0]  ; version
    xchg al, ah
    test eax, eax
    jnz .next_table
    movzx eax, word [r14 + 2]  ; length
    xchg al, ah
    mov r8d, eax
    movzx eax, byte [r14 + 3]  ; format
    test eax, eax
    jnz .next_table
    ; format 0: nPairs, searchRange, entrySelector, rangeShift, pairs
    movzx eax, word [r14 + 6]
    xchg al, ah
    mov r9d, eax  ; nPairs
    lea r10, [r14 + 14]
    xor r11d, r11d
.pair_loop:
    cmp r11d, r9d
    jae .next_table
    movzx eax, word [r10 + 0]
    xchg al, ah
    cmp eax, r12d
    jne .next_pair
    movzx eax, word [r10 + 2]
    xchg al, ah
    cmp eax, r13d
    jne .next_pair
    movsx eax, word [r10 + 4]
    xchg al, ah
    movsx eax, ax
    ret
.next_pair:
    add r10, 6
    inc r11d
    jmp .pair_loop
.next_table:
    add r14, r8
    dec ecx
    jmp .table_loop
.none:
    xor eax, eax
    ret

; ---------------------------------------------------------------------------
; hmtx_advance
;   IN: rdi = font*, rsi = glyph id — OUT: eax = advance width (font units)
; ---------------------------------------------------------------------------
global hmtx_advance
hmtx_advance:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12d, esi
    ASSERT_PTR rbx
    mov r13, [rbx + TtfFont.hmtx]
    test r13, r13
    jz .missing
    mov rax, [rbx + TtfFont.hhea]
    test rax, rax
    jz .missing
    mov rdi, rax
    add rdi, 34
    call cmap_be16  ; numberOfHMetrics
    test eax, eax
    jz .missing
    ; if glyph < numMetrics: advance at glyph*4, else last advance
    cmp r12d, eax
    jb .indexed
    dec eax
.indexed:
    movzx eax, word [r13 + rax * 4]
    xchg al, ah
    ret
.missing:
    xor eax, eax
    ret

section .data
global kern_version
kern_version: dq 0x010000
