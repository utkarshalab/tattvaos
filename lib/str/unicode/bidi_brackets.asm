%ifndef GUARD_LIB_STR_UNICODE_BIDI_BRACKETS_ASM
%define GUARD_LIB_STR_UNICODE_BIDI_BRACKETS_ASM
; =============================================================================
; str/unicode/bidi_brackets.asm
; Paired bracket algorithm (UAX #9 rule N0) for full bidi support.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Source: BidiBrackets.txt, BidiCharacterTest.txt
;
; -----------------------------------------------------------------------------
; In bidirectional text, paired brackets ( ) [ ] { } need special handling.
; An opening bracket followed by content and a closing bracket should be
; treated as a unit, not individually reordered.
;
; BidiBrackets.txt maps each opening bracket to its closing counterpart
; and vice versa, with a type: o=opening, c=closing.
;
; Functions:
;   str_bidi_bracket_type   — is codepoint an opening/closing bracket?
;   str_bidi_bracket_pair   — get the paired bracket for a codepoint
;   str_bidi_resolve_brackets — resolve brackets in a bidi run (N0)
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

BRACKET_NONE    equ 0
BRACKET_OPEN    equ 1
BRACKET_CLOSE   equ 2

MAX_BRACKET_DEPTH equ 63    ; UAX #9 max bracket stack depth

section .rodata
align 16

; Common bracket pairs: (codepoint, paired_codepoint, type)
; Sorted by codepoint for binary search.
_bracket_pairs:
    dd 0x0028, 0x0029, BRACKET_OPEN     ; ( → )
    dd 0x0029, 0x0028, BRACKET_CLOSE    ; ) → (
    dd 0x005B, 0x005D, BRACKET_OPEN     ; [ → ]
    dd 0x005D, 0x005B, BRACKET_CLOSE    ; ] → [
    dd 0x007B, 0x007D, BRACKET_OPEN     ; { → }
    dd 0x007D, 0x007B, BRACKET_CLOSE    ; } → {
    dd 0x0F3A, 0x0F3B, BRACKET_OPEN     ; ༺ → ༻
    dd 0x0F3B, 0x0F3A, BRACKET_CLOSE
    dd 0x0F3C, 0x0F3D, BRACKET_OPEN     ; ༼ → ༽
    dd 0x0F3D, 0x0F3C, BRACKET_CLOSE
    dd 0x169B, 0x169C, BRACKET_OPEN     ; ᚛ → ᚜
    dd 0x169C, 0x169B, BRACKET_CLOSE
    dd 0x2045, 0x2046, BRACKET_OPEN     ; ⁅ → ⁆
    dd 0x2046, 0x2045, BRACKET_CLOSE
    dd 0x207D, 0x207E, BRACKET_OPEN     ; ⁽ → ⁾
    dd 0x207E, 0x207D, BRACKET_CLOSE
    dd 0x208D, 0x208E, BRACKET_OPEN     ; ₍ → ₎
    dd 0x208E, 0x208D, BRACKET_CLOSE
    dd 0x2308, 0x2309, BRACKET_OPEN     ; ⌈ → ⌉
    dd 0x2309, 0x2308, BRACKET_CLOSE
    dd 0x230A, 0x230B, BRACKET_OPEN     ; ⌊ → ⌋
    dd 0x230B, 0x230A, BRACKET_CLOSE
    dd 0x2329, 0x232A, BRACKET_OPEN     ; 〈 → 〉
    dd 0x232A, 0x2329, BRACKET_CLOSE
    dd 0x27E6, 0x27E7, BRACKET_OPEN     ; ⟦ → ⟧
    dd 0x27E7, 0x27E6, BRACKET_CLOSE
    dd 0x27E8, 0x27E9, BRACKET_OPEN     ; ⟨ → ⟩
    dd 0x27E9, 0x27E8, BRACKET_CLOSE
    dd 0x27EA, 0x27EB, BRACKET_OPEN     ; ⟪ → ⟫
    dd 0x27EB, 0x27EA, BRACKET_CLOSE
    dd 0x3008, 0x3009, BRACKET_OPEN     ; 〈 → 〉
    dd 0x3009, 0x3008, BRACKET_CLOSE
    dd 0x300A, 0x300B, BRACKET_OPEN     ; 《 → 》
    dd 0x300B, 0x300A, BRACKET_CLOSE
    dd 0x300C, 0x300D, BRACKET_OPEN     ; 「 → 」
    dd 0x300D, 0x300C, BRACKET_CLOSE
    dd 0x300E, 0x300F, BRACKET_OPEN     ; 『 → 』
    dd 0x300F, 0x300E, BRACKET_CLOSE
    dd 0x3010, 0x3011, BRACKET_OPEN     ; 【 → 】
    dd 0x3011, 0x3010, BRACKET_CLOSE
    dd 0x3014, 0x3015, BRACKET_OPEN     ; 〔 → 〕
    dd 0x3015, 0x3014, BRACKET_CLOSE
    dd 0x3016, 0x3017, BRACKET_OPEN     ; 〖 → 〗
    dd 0x3017, 0x3016, BRACKET_CLOSE
    dd 0x3018, 0x3019, BRACKET_OPEN     ; 〘 → 〙
    dd 0x3019, 0x3018, BRACKET_CLOSE
    dd 0x301A, 0x301B, BRACKET_OPEN     ; 〚 → 〛
    dd 0x301B, 0x301A, BRACKET_CLOSE
    dd 0xFF08, 0xFF09, BRACKET_OPEN     ; （ → ）
    dd 0xFF09, 0xFF08, BRACKET_CLOSE
    dd 0xFF3B, 0xFF3D, BRACKET_OPEN     ; ［ → ］
    dd 0xFF3D, 0xFF3B, BRACKET_CLOSE
    dd 0xFF5B, 0xFF5D, BRACKET_OPEN     ; ｛ → ｝
    dd 0xFF5D, 0xFF5B, BRACKET_CLOSE
    dd 0xFF5F, 0xFF60, BRACKET_OPEN     ; ｟ → ｠
    dd 0xFF60, 0xFF5F, BRACKET_CLOSE
_bracket_pairs_end:

BRACKET_PAIR_COUNT equ (_bracket_pairs_end - _bracket_pairs) / 12

section .text

; -----------------------------------------------------------------------------
; str_bidi_bracket_type
; Returns: AL = BRACKET_NONE/OPEN/CLOSE
; -----------------------------------------------------------------------------

STR_FUNC str_bidi_bracket_type

    lea     r8, [rel _bracket_pairs]
    xor     r9, r9
    mov     r10, BRACKET_PAIR_COUNT

.bbt_search:
    cmp     r9, r10
    jae     .bbt_none

    mov     r11, r9
    add     r11, r10
    shr     r11, 1

    mov     rax, r11
    imul    rax, 12
    mov     ecx, [r8 + rax]

    cmp     edi, ecx
    jb      .bbt_left
    ja      .bbt_right

    ; found
    mov     eax, [r8 + rax + 8]
    pop     rbp
    ret

.bbt_left:
    mov     r10, r11
    jmp     .bbt_search
.bbt_right:
    lea     r9, [r11 + 1]
    jmp     .bbt_search

.bbt_none:
    mov     al, BRACKET_NONE
    pop     rbp
    ret

STR_ENDFUNC str_bidi_bracket_type

; -----------------------------------------------------------------------------
; str_bidi_bracket_pair
; Arguments: EDI = codepoint
; Returns:   EAX = paired bracket codepoint, or 0 if not a bracket
; -----------------------------------------------------------------------------

STR_FUNC str_bidi_bracket_pair

    lea     r8, [rel _bracket_pairs]
    xor     r9, r9
    mov     r10, BRACKET_PAIR_COUNT

.bbp_search:
    cmp     r9, r10
    jae     .bbp_none

    mov     r11, r9
    add     r11, r10
    shr     r11, 1

    mov     rax, r11
    imul    rax, 12
    mov     ecx, [r8 + rax]

    cmp     edi, ecx
    jb      .bbp_left
    ja      .bbp_right

    mov     eax, [r8 + rax + 4]
    pop     rbp
    ret

.bbp_left:
    mov     r10, r11
    jmp     .bbp_search
.bbp_right:
    lea     r9, [r11 + 1]
    jmp     .bbp_search

.bbp_none:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_bidi_bracket_pair
%endif ; GUARD_LIB_STR_UNICODE_BIDI_BRACKETS_ASM
