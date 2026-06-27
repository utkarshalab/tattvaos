; =============================================================================
; str/unicode/do_not_emit.asm
; Characters that should not be emitted in new text (DoNotEmit.txt).
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Source: DoNotEmit.txt
;
; -----------------------------------------------------------------------------
; DoNotEmit.txt catalogs codepoints that should be avoided in new text.
; Categories:
;
;   Deprecated:
;     Characters formally deprecated by the Unicode Standard.
;     Still encoded for legacy compatibility but should not be used in
;     new text. Examples:
;       U+0149 LATIN SMALL LETTER N PRECEDED BY APOSTROPHE
;       U+0673 ARABIC LETTER ALEF WITH WAVY HAMZA BELOW
;       U+206A-206F Deprecated formatting controls
;
;   Default Ignorable with No Clear Function:
;     Zero-width characters that may cause unexpected behavior.
;     Some (like ZWJ) have important uses; others do not.
;
;   Not NFKC:
;     Characters with compatibility decompositions — prefer the decomposed
;     form. Examples: ﬁ (U+FB01) → "fi", ² (U+00B2) → "2"
;
;   Noncharacters:
;     Permanently reserved codepoints that should never appear in
;     interchange text: U+FDD0-U+FDEF, U+xFFFE, U+xFFFF
;
;   Obsolete:
;     Characters still assigned but whose use is strongly discouraged.
;
; Functions:
;   str_cp_is_do_not_emit    — should this codepoint be avoided?
;   str_cp_do_not_emit_reason — get the reason code for avoidance
;   str_cp_is_deprecated      — is this codepoint deprecated?
;   str_cp_is_noncharacter    — is this a noncharacter? (also in props.asm)
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

; Do-Not-Emit reason codes
DNE_NONE            equ 0
DNE_DEPRECATED      equ 1
DNE_DEFAULT_IGNORABLE equ 2
DNE_NOT_NFKC        equ 3
DNE_NONCHARACTER    equ 4
DNE_OBSOLETE        equ 5

section .text

; -----------------------------------------------------------------------------
; str_cp_is_do_not_emit
;
; Check if a codepoint should not be emitted in new text.
;
; Signature:
;   int64_t str_cp_is_do_not_emit(uint32_t cp)
;
; Arguments:
;   EDI  — codepoint
;
; Returns:
;   RAX  = 1 if should not emit, 0 if ok
; -----------------------------------------------------------------------------

STR_FUNC str_cp_is_do_not_emit

    cmp     edi, CODEPOINT_MAX
    ja      .dne_yes

    ; ---- Deprecated characters ----
    cmp     edi, 0x0149
    je      .dne_yes
    cmp     edi, 0x0673
    je      .dne_yes
    cmp     edi, 0x0F77
    je      .dne_yes
    cmp     edi, 0x0F79
    je      .dne_yes
    cmp     edi, 0x17A3
    je      .dne_yes
    cmp     edi, 0x17A4
    je      .dne_yes

    ; Deprecated formatting controls
    cmp     edi, 0x206A
    jb      .dne_chk_compat
    cmp     edi, 0x206F
    jbe     .dne_yes

.dne_chk_compat:
    ; ---- Not-NFKC: common compatibility characters ----
    ; Latin ligatures
    cmp     edi, 0xFB00
    jb      .dne_chk_halfwidth
    cmp     edi, 0xFB06
    jbe     .dne_yes            ; ﬀ ﬁ ﬂ ﬃ ﬄ ﬅ ﬆ

.dne_chk_halfwidth:
    ; Halfwidth/fullwidth forms (prefer ASCII/standard width)
    cmp     edi, 0xFF01
    jb      .dne_chk_singletons
    cmp     edi, 0xFF60
    jbe     .dne_yes            ; fullwidth ASCII variants

    cmp     edi, 0xFF61
    jb      .dne_chk_singletons
    cmp     edi, 0xFFDC
    jbe     .dne_yes            ; halfwidth CJK/Hangul variants

    cmp     edi, 0xFFE0
    jb      .dne_chk_singletons
    cmp     edi, 0xFFEE
    jbe     .dne_yes            ; fullwidth/halfwidth symbols

.dne_chk_singletons:
    ; Singleton decomposition characters
    cmp     edi, 0x2126
    je      .dne_yes            ; OHM SIGN → Ω
    cmp     edi, 0x212A
    je      .dne_yes            ; KELVIN SIGN → K
    cmp     edi, 0x212B
    je      .dne_yes            ; ANGSTROM SIGN → Å

    ; ---- Noncharacters ----
    cmp     edi, 0xFDD0
    jb      .dne_chk_plane_end
    cmp     edi, 0xFDEF
    jbe     .dne_yes

.dne_chk_plane_end:
    ; xxFFFE and xxFFFF for each plane
    mov     eax, edi
    and     eax, 0xFFFF
    cmp     eax, 0xFFFE
    jae     .dne_yes            ; catches both FFFE and FFFF

    ; ---- Tag characters (deprecated) ----
    cmp     edi, 0xE0001
    je      .dne_yes            ; LANGUAGE TAG
    cmp     edi, 0xE0020
    jb      .dne_chk_interlinear
    cmp     edi, 0xE007F
    jbe     .dne_yes            ; TAG SPACE..CANCEL TAG

.dne_chk_interlinear:
    ; Interlinear annotation anchors
    cmp     edi, 0xFFF9
    jb      .dne_chk_specials
    cmp     edi, 0xFFFB
    jbe     .dne_yes

.dne_chk_specials:
    ; Object replacement / replacement character (context dependent)
    cmp     edi, 0xFFFC
    je      .dne_yes            ; OBJECT REPLACEMENT CHARACTER

    ; ---- Musical format characters ----
    cmp     edi, 0x1D173
    jb      .dne_no
    cmp     edi, 0x1D17A
    jbe     .dne_yes            ; musical beaming/phrasing (deprecated)

.dne_no:
    xor     eax, eax
    pop     rbp
    ret

.dne_yes:
    mov     eax, 1
    pop     rbp
    ret

STR_ENDFUNC str_cp_is_do_not_emit

; -----------------------------------------------------------------------------
; str_cp_do_not_emit_reason
;
; Get the reason why a codepoint should not be emitted.
;
; Signature:
;   uint8_t str_cp_do_not_emit_reason(uint32_t cp)
;
; Arguments:
;   EDI  — codepoint
;
; Returns:
;   AL   — DNE_* reason code (DNE_NONE if ok to emit)
; -----------------------------------------------------------------------------

STR_FUNC str_cp_do_not_emit_reason

    cmp     edi, CODEPOINT_MAX
    ja      .dnr_nonchar

    ; ---- Deprecated ----
    cmp     edi, 0x0149
    je      .dnr_deprecated
    cmp     edi, 0x0673
    je      .dnr_deprecated
    cmp     edi, 0x0F77
    je      .dnr_deprecated
    cmp     edi, 0x0F79
    je      .dnr_deprecated
    cmp     edi, 0x17A3
    je      .dnr_deprecated
    cmp     edi, 0x17A4
    je      .dnr_deprecated
    cmp     edi, 0x206A
    jb      .dnr_chk_compat
    cmp     edi, 0x206F
    jbe     .dnr_deprecated
    cmp     edi, 0xE0001
    je      .dnr_deprecated
    cmp     edi, 0x1D173
    jb      .dnr_chk_compat
    cmp     edi, 0x1D17A
    jbe     .dnr_deprecated

.dnr_chk_compat:
    ; ---- Not NFKC ----
    cmp     edi, 0xFB00
    jb      .dnr_chk_fw
    cmp     edi, 0xFB06
    jbe     .dnr_nfkc
.dnr_chk_fw:
    cmp     edi, 0xFF01
    jb      .dnr_chk_singleton
    cmp     edi, 0xFFEE
    jbe     .dnr_nfkc

.dnr_chk_singleton:
    cmp     edi, 0x2126
    je      .dnr_nfkc
    cmp     edi, 0x212A
    je      .dnr_nfkc
    cmp     edi, 0x212B
    je      .dnr_nfkc

    ; ---- Noncharacters ----
    cmp     edi, 0xFDD0
    jb      .dnr_chk_plane_end
    cmp     edi, 0xFDEF
    jbe     .dnr_nonchar
.dnr_chk_plane_end:
    mov     eax, edi
    and     eax, 0xFFFF
    cmp     eax, 0xFFFE
    jae     .dnr_nonchar

    ; ---- Default Ignorable (problematic ones) ----
    cmp     edi, 0xE0020
    jb      .dnr_chk_interlinear
    cmp     edi, 0xE007F
    jbe     .dnr_default_ignorable

.dnr_chk_interlinear:
    cmp     edi, 0xFFF9
    jb      .dnr_chk_obj
    cmp     edi, 0xFFFB
    jbe     .dnr_obsolete

.dnr_chk_obj:
    cmp     edi, 0xFFFC
    je      .dnr_obsolete

.dnr_none:
    xor     eax, eax            ; DNE_NONE
    pop     rbp
    ret

.dnr_deprecated:
    mov     al, DNE_DEPRECATED
    pop     rbp
    ret

.dnr_nfkc:
    mov     al, DNE_NOT_NFKC
    pop     rbp
    ret

.dnr_nonchar:
    mov     al, DNE_NONCHARACTER
    pop     rbp
    ret

.dnr_default_ignorable:
    mov     al, DNE_DEFAULT_IGNORABLE
    pop     rbp
    ret

.dnr_obsolete:
    mov     al, DNE_OBSOLETE
    pop     rbp
    ret

STR_ENDFUNC str_cp_do_not_emit_reason

; -----------------------------------------------------------------------------
; str_cp_is_deprecated
;
; Check if a codepoint is formally deprecated by the Unicode Standard.
;
; Signature:
;   int64_t str_cp_is_deprecated(uint32_t cp)
;
; Arguments:
;   EDI  — codepoint
;
; Returns:
;   RAX  = 1 if deprecated, 0 otherwise
; -----------------------------------------------------------------------------

STR_FUNC str_cp_is_deprecated

    cmp     edi, 0x0149
    je      .dep_yes
    cmp     edi, 0x0673
    je      .dep_yes
    cmp     edi, 0x0F77
    je      .dep_yes
    cmp     edi, 0x0F79
    je      .dep_yes
    cmp     edi, 0x17A3
    je      .dep_yes
    cmp     edi, 0x17A4
    je      .dep_yes

    ; Deprecated formatting controls
    cmp     edi, 0x206A
    jb      .dep_chk_tag
    cmp     edi, 0x206F
    jbe     .dep_yes

.dep_chk_tag:
    ; Language tag
    cmp     edi, 0xE0001
    je      .dep_yes

    ; Musical format (deprecated in newer Unicode)
    cmp     edi, 0x1D173
    jb      .dep_no
    cmp     edi, 0x1D17A
    jbe     .dep_yes

.dep_no:
    xor     eax, eax
    pop     rbp
    ret

.dep_yes:
    mov     eax, 1
    pop     rbp
    ret

STR_ENDFUNC str_cp_is_deprecated
