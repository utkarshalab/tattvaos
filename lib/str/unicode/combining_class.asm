%ifndef GUARD_LIB_STR_UNICODE_COMBINING_CLASS_ASM
%define GUARD_LIB_STR_UNICODE_COMBINING_CLASS_ASM
; =============================================================================
; str/unicode/combining_class.asm
; Canonical Combining Class (CCC) queries (DerivedCombiningClass.txt).
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;
; -----------------------------------------------------------------------------
; The Canonical Combining Class (CCC) is a property of Unicode codepoints
; used by the normalization algorithms (NFD, NFC, NFKD, NFKC) to order
; sequences of combining marks during decomposition.
;
; Value range:
;   0     = Starter (spacing character that does not combine)
;   1..254 = Combining marks (accents, marks, sub-marks, Hebrew points, etc.)
;   255   = (Invalid/unused value)
;
; Functions:
;   str_cp_ccc — get the canonical combining class of a codepoint
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"


section .text

; -----------------------------------------------------------------------------
; str_cp_ccc
;
; Get the canonical combining class of a codepoint.
; 0 = starter (not a combining mark).
; 1-254 = combining mark with that class.
;
; Signature:
;   uint8_t str_cp_ccc(uint32_t cp)
;
; Arguments:
;   EDI  — codepoint
;
; Returns:
;   AL   — combining class (0 for most characters)
; -----------------------------------------------------------------------------

STR_FUNC str_cp_ccc

    cmp     edi, 0x10FFFF
    ja      .ccc_zero

    ; simplified lookup: direct table for BMP, default 0 elsewhere
    ; (most combining marks are in the BMP)
    cmp     edi, 0x10000
    jae     .ccc_zero

    lea     r8, [rel _ucd_ccc_table]
    movzx   eax, byte [r8 + rdi]
    pop     rbp
    ret

.ccc_zero:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_cp_ccc

%endif ; GUARD_LIB_STR_UNICODE_COMBINING_CLASS_ASM
