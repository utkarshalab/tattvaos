%ifndef GUARD_LIB_STR_UNICODE_BIDI_MIRROR_ASM
%define GUARD_LIB_STR_UNICODE_BIDI_MIRROR_ASM
; =============================================================================
; str/unicode/bidi_mirror.asm
; Bidi mirroring: get the mirrored glyph for RTL display.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
; Source: BidiMirroring.txt
;
; -----------------------------------------------------------------------------
; When displaying RTL text, certain characters need their visual form
; mirrored: ( becomes ), < becomes >, etc. BidiMirroring.txt lists
; all such pairs.
;
; Functions:
;   str_bidi_mirror       — get mirrored codepoint (or same if not mirrored)
;   str_bidi_is_mirrored  — check if codepoint has a mirror
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

section .rodata
align 16

; Mirror pairs: (cp, mirrored_cp) sorted by cp. Binary searchable.
_bidi_mirror_pairs:
    dd 0x0028, 0x0029       ; ( ↔ )
    dd 0x0029, 0x0028
    dd 0x003C, 0x003E       ; < ↔ >
    dd 0x003E, 0x003C
    dd 0x005B, 0x005D       ; [ ↔ ]
    dd 0x005D, 0x005B
    dd 0x007B, 0x007D       ; { ↔ }
    dd 0x007D, 0x007B
    dd 0x00AB, 0x00BB       ; « ↔ »
    dd 0x00BB, 0x00AB
    dd 0x2039, 0x203A       ; ‹ ↔ ›
    dd 0x203A, 0x2039
    dd 0x2045, 0x2046       ; ⁅ ↔ ⁆
    dd 0x2046, 0x2045
    dd 0x207D, 0x207E       ; ⁽ ↔ ⁾
    dd 0x207E, 0x207D
    dd 0x208D, 0x208E       ; ₍ ↔ ₎
    dd 0x208E, 0x208D
    dd 0x2140, 0x2140       ; ⅀ (self-mirror placeholder)
    dd 0x2208, 0x220B       ; ∈ ↔ ∋
    dd 0x220B, 0x2208
    dd 0x2215, 0x29F5       ; ∕ ↔ ⧵
    dd 0x221F, 0x221F       ; ∟
    dd 0x2220, 0x2220       ; ∠
    dd 0x2264, 0x2265       ; ≤ ↔ ≥
    dd 0x2265, 0x2264
    dd 0x226E, 0x226F       ; ≮ ↔ ≯
    dd 0x226F, 0x226E
    dd 0x2308, 0x2309       ; ⌈ ↔ ⌉
    dd 0x2309, 0x2308
    dd 0x230A, 0x230B       ; ⌊ ↔ ⌋
    dd 0x230B, 0x230A
    dd 0x27E8, 0x27E9       ; ⟨ ↔ ⟩
    dd 0x27E9, 0x27E8
    dd 0x27EA, 0x27EB       ; ⟪ ↔ ⟫
    dd 0x27EB, 0x27EA
    dd 0x3008, 0x3009       ; 〈 ↔ 〉
    dd 0x3009, 0x3008
    dd 0x300A, 0x300B       ; 《 ↔ 》
    dd 0x300B, 0x300A
    dd 0x300C, 0x300D       ; 「 ↔ 」
    dd 0x300D, 0x300C
    dd 0x300E, 0x300F       ; 『 ↔ 』
    dd 0x300F, 0x300E
    dd 0xFF08, 0xFF09       ; （ ↔ ）
    dd 0xFF09, 0xFF08
    dd 0xFF1C, 0xFF1E       ; ＜ ↔ ＞
    dd 0xFF1E, 0xFF1C
    dd 0xFF3B, 0xFF3D       ; ［ ↔ ］
    dd 0xFF3D, 0xFF3B
    dd 0xFF5B, 0xFF5D       ; ｛ ↔ ｝
    dd 0xFF5D, 0xFF5B
_bidi_mirror_pairs_end:

MIRROR_PAIR_COUNT equ (_bidi_mirror_pairs_end - _bidi_mirror_pairs) / 8

section .text

STR_FUNC str_bidi_mirror

    lea     r8, [rel _bidi_mirror_pairs]
    xor     r9, r9
    mov     r10, MIRROR_PAIR_COUNT

.bm_search:
    cmp     r9, r10
    jae     .bm_self
    mov     r11, r9
    add     r11, r10
    shr     r11, 1
    mov     ecx, [r8 + r11 * 8]
    cmp     edi, ecx
    jb      .bm_left
    ja      .bm_right
    mov     eax, [r8 + r11 * 8 + 4]
    pop     rbp
    ret
.bm_left:
    mov     r10, r11
    jmp     .bm_search
.bm_right:
    lea     r9, [r11 + 1]
    jmp     .bm_search
.bm_self:
    mov     eax, edi
    pop     rbp
    ret

STR_ENDFUNC str_bidi_mirror

STR_FUNC str_bidi_is_mirrored

    push    rdi
    call    str_bidi_mirror
    pop     rdi
    cmp     eax, edi
    setne   al
    movzx   eax, al
    pop     rbp
    ret

STR_ENDFUNC str_bidi_is_mirrored
%endif ; GUARD_LIB_STR_UNICODE_BIDI_MIRROR_ASM
