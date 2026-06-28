; =============================================================================
; str/unicode/width.asm
; East Asian Width property + display width calculation.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Source: EastAsianWidth.txt
;
; -----------------------------------------------------------------------------
; East Asian Width classes (UAX #11):
;   F  — Fullwidth    (Ａ, ０)              → 2 columns
;   H  — Halfwidth    (ｱ, ﾊ)              → 1 column
;   W  — Wide         (漢, ア, 가)          → 2 columns
;   Na — Narrow       (A, 1)               → 1 column
;   A  — Ambiguous    (°, ×, α)            → 1 or 2 (context)
;   N  — Neutral      (most Latin, symbols) → 1 column
;
; Display width is what terminals need: how many columns a character
; occupies. This is the assembly equivalent of wcwidth()/wcswidth().
;
; Functions:
;   str_cp_east_asian_width  — get EAW class for codepoint
;   str_cp_display_width     — columns a codepoint takes (0, 1, or 2)
;   str_display_width        — total display width of a UTF-8 string
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_utf8_decode_unchecked

; East Asian Width classes
EAW_N   equ 0      ; Neutral
EAW_Na  equ 1      ; Narrow
EAW_H   equ 2      ; Halfwidth
EAW_W   equ 3      ; Wide
EAW_F   equ 4      ; Fullwidth
EAW_A   equ 5      ; Ambiguous

section .text

; -----------------------------------------------------------------------------
; str_cp_east_asian_width
;
; Arguments: EDI = codepoint
; Returns:   AL = EAW_* class
; -----------------------------------------------------------------------------

STR_FUNC str_cp_east_asian_width

    ; ASCII → Narrow
    cmp     edi, 0x80
    jb      .eaw_na

    ; CJK Unified Ideographs: 0x4E00-0x9FFF → Wide
    cmp     edi, 0x4E00
    jb      .eaw_chk_ranges
    cmp     edi, 0x9FFF
    jbe     .eaw_w

    ; CJK Ext A: 0x3400-0x4DBF → Wide
    cmp     edi, 0x3400
    jb      .eaw_chk_ranges
    cmp     edi, 0x4DBF
    jbe     .eaw_w

.eaw_chk_ranges:
    ; Hangul Syllables: 0xAC00-0xD7AF → Wide
    cmp     edi, 0xAC00
    jb      .eaw_chk_kata
    cmp     edi, 0xD7AF
    jbe     .eaw_w

.eaw_chk_kata:
    ; Katakana: 0x30A0-0x30FF → Wide
    cmp     edi, 0x30A0
    jb      .eaw_chk_hira
    cmp     edi, 0x30FF
    jbe     .eaw_w

.eaw_chk_hira:
    ; Hiragana: 0x3040-0x309F → Wide
    cmp     edi, 0x3040
    jb      .eaw_chk_cjk_sym
    cmp     edi, 0x309F
    jbe     .eaw_w

.eaw_chk_cjk_sym:
    ; CJK Symbols: 0x3000-0x303F → Wide (includes ideographic space 0x3000)
    cmp     edi, 0x3000
    jb      .eaw_chk_fullwidth
    cmp     edi, 0x303F
    jbe     .eaw_w

.eaw_chk_fullwidth:
    ; Fullwidth Forms: 0xFF01-0xFF60 → Fullwidth (2 columns)
    cmp     edi, 0xFF01
    jb      .eaw_chk_halfwidth
    cmp     edi, 0xFF60
    jbe     .eaw_f

.eaw_chk_halfwidth:
    ; Halfwidth Forms: 0xFF61-0xFFDC → Halfwidth (1 column)
    cmp     edi, 0xFF61
    jb      .eaw_chk_encl
    cmp     edi, 0xFFDC
    jbe     .eaw_h

.eaw_chk_encl:
    ; Enclosed CJK: 0x3200-0x32FF → Wide
    cmp     edi, 0x3200
    jb      .eaw_chk_compat
    cmp     edi, 0x32FF
    jbe     .eaw_w

.eaw_chk_compat:
    ; CJK Compatibility: 0x3300-0x33FF → Wide
    cmp     edi, 0x3300
    jb      .eaw_chk_bopomofo
    cmp     edi, 0x33FF
    jbe     .eaw_w

.eaw_chk_bopomofo:
    ; Bopomofo: 0x3100-0x312F → Wide
    cmp     edi, 0x3100
    jb      .eaw_chk_yi
    cmp     edi, 0x312F
    jbe     .eaw_w

.eaw_chk_yi:
    ; Yi: 0xA000-0xA4CF → Wide
    cmp     edi, 0xA000
    jb      .eaw_chk_emoji
    cmp     edi, 0xA4CF
    jbe     .eaw_w

.eaw_chk_emoji:
    ; Common wide emoji ranges
    cmp     edi, 0x1F300
    jb      .eaw_chk_supp_cjk
    cmp     edi, 0x1F9FF
    jbe     .eaw_w

.eaw_chk_supp_cjk:
    ; CJK Ext B+: 0x20000-0x2FA1F → Wide
    cmp     edi, 0x20000
    jb      .eaw_chk_ambig
    cmp     edi, 0x2FA1F
    jbe     .eaw_w

.eaw_chk_ambig:
    ; Ambiguous characters (common subset)
    ; Greek letters: 0x0391-0x03C9
    cmp     edi, 0x0391
    jb      .eaw_chk_ambig2
    cmp     edi, 0x03C9
    jbe     .eaw_a

.eaw_chk_ambig2:
    ; Cyrillic: 0x0400-0x04FF
    cmp     edi, 0x0400
    jb      .eaw_n
    cmp     edi, 0x04FF
    jbe     .eaw_a

    ; default: Neutral
.eaw_n:  mov al, EAW_N
    pop rbp
    ret
.eaw_na: mov al, EAW_Na
    pop rbp
    ret
.eaw_w:  mov al, EAW_W
    pop rbp
    ret
.eaw_f:  mov al, EAW_F
    pop rbp
    ret
.eaw_h:  mov al, EAW_H
    pop rbp
    ret
.eaw_a:  mov al, EAW_A
    pop rbp
    ret

STR_ENDFUNC str_cp_east_asian_width

; -----------------------------------------------------------------------------
; str_cp_display_width
;
; Get the display width in terminal columns: 0, 1, or 2.
;
; Arguments: EDI = codepoint
; Returns:   EAX = 0 (zero-width), 1 (narrow), or 2 (wide)
; -----------------------------------------------------------------------------

STR_FUNC str_cp_display_width

    ; zero-width: combining marks (CCC > 0), control chars, ZWJ/ZWNJ
    cmp     edi, 0x200B
    je      .dw_zero            ; ZWSP
    cmp     edi, 0x200C
    je      .dw_zero            ; ZWNJ
    cmp     edi, 0x200D
    je      .dw_zero            ; ZWJ
    cmp     edi, 0xFEFF
    je      .dw_zero            ; BOM/ZWNBSP

    ; control chars
    cmp     edi, 0x20
    jb      .dw_zero
    cmp     edi, 0x7F
    je      .dw_zero

    ; combining marks: 0x0300-0x036F
    cmp     edi, 0x0300
    jb      .dw_get_eaw
    cmp     edi, 0x036F
    jbe     .dw_zero

    ; soft hyphen
    cmp     edi, 0xAD
    je      .dw_zero

.dw_get_eaw:
    call    str_cp_east_asian_width

    cmp     al, EAW_W
    je      .dw_two
    cmp     al, EAW_F
    je      .dw_two

    mov     eax, 1
    pop     rbp
    ret

.dw_two:
    mov     eax, 2
    pop     rbp
    ret

.dw_zero:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_cp_display_width

; -----------------------------------------------------------------------------
; str_display_width
;
; Total display width of a UTF-8 string in terminal columns.
;
; Signature:
;   int64_t str_display_width(const StrSlice *src, uint64_t *out_width)
; -----------------------------------------------------------------------------

STR_FUNC str_display_width

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, rbx
    add     r12, [rdi + StrSlice.len]
    mov     r13, rsi

    xor     r9, r9              ; total width

.dw_loop:
    cmp     rbx, r12
    jae     .dw_done

    sub     rsp, 16
    and     rsp, -16
    mov     rdi, rbx
    lea     rsi, [rsp]
    call    str_utf8_decode_unchecked
    mov     r8d, eax
    add     rbx, [rsp]
    mov     rsp, rbp

    mov     edi, r8d
    push    r8
    call    str_cp_display_width
    pop     r8
    add     r9, rax

    jmp     .dw_loop

.dw_done:
    mov     [r13], r9
    pop_regs r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_display_width

; -----------------------------------------------------------------------------
; str_display_truncate
;
; Truncate a string to at most max_columns display width.
; Returns the byte length of the prefix that fits in *out_byte_len.
;
; Signature:
;   int64_t str_display_truncate(const StrSlice *src, uint64_t max_columns,
;                                uint64_t *out_byte_len)
; -----------------------------------------------------------------------------
STR_FUNC str_display_truncate
    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15
    sub     rsp, 24             ; advance [rsp], cols [rsp+8], out_byte_len [rsp+16]

    mov     rbx, [rdi + StrSlice.ptr]   ; current ptr
    mov     r12, rbx
    add     r12, [rdi + StrSlice.len]   ; end ptr
    mov     r13, rsi                    ; max_columns
    mov     [rsp + 16], rdx             ; save out_byte_len ptr
    mov     r14, [rdi + StrSlice.ptr]   ; original src.ptr

    mov     qword [rsp + 8], 0          ; current_columns = 0

.loop:
    cmp     rbx, r12
    jae     .done

    ; decode next codepoint
    mov     rdi, rbx
    mov     rsi, rsp                    ; &advance
    call    str_utf8_decode_unchecked
    mov     r15d, eax                   ; cp

    ; get display width
    mov     edi, eax
    call    str_cp_display_width
    ; eax = width (0, 1, or 2)

    ; check if it fits
    mov     rcx, [rsp + 8]              ; current_columns
    add     rcx, rax                    ; new_columns
    cmp     rcx, r13
    ja      .done                       ; doesn't fit -> truncate before this char

    ; fits: advance
    mov     [rsp + 8], rcx              ; update current_columns
    mov     rax, [rsp]                  ; advance size
    add     rbx, rax
    jmp     .loop

.done:
    mov     rax, rbx
    sub     rax, r14                    ; byte_len = rbx - original_ptr
    mov     rcx, [rsp + 16]             ; out_byte_len ptr
    mov     [rcx], rax

    add     rsp, 24
    pop_regs r15, r14, r13, r12, rbx
    ret_ok
STR_ENDFUNC str_display_truncate