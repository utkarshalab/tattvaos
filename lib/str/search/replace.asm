%ifndef GUARD_LIB_STR_SEARCH_REPLACE_ASM
%define GUARD_LIB_STR_SEARCH_REPLACE_ASM
; =============================================================================
; str/search/replace.asm
; Fast Boyer-Moore-Horspool replacement function.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   core/replace.asm (str_replace_all)
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

section .text

; -----------------------------------------------------------------------------
; str_bmh_replace_all
;
; Fast bulk replacement using Boyer-Moore-Horspool search.
;
; Signature:
;   int64_t str_bmh_replace_all(const StrSlice *haystack, const StrSlice *needle,
;                               const StrSlice *replacement, uint8_t *dst,
;                               uint64_t cap, uint64_t *out_len)
; -----------------------------------------------------------------------------
STR_FUNC str_bmh_replace_all
    ; Forward directly to str_replace_all (which already uses BMH via str_find_from)
    jmp     str_replace_all
STR_ENDFUNC str_bmh_replace_all

%endif ; GUARD_LIB_STR_SEARCH_REPLACE_ASM
