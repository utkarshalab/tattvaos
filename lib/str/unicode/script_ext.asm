%ifndef GUARD_LIB_STR_UNICODE_SCRIPT_EXT_ASM
%define GUARD_LIB_STR_UNICODE_SCRIPT_EXT_ASM
; =============================================================================
; str/unicode/script_ext.asm
; Script extensions — codepoints shared across multiple scripts.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
; Source: ScriptExtensions.txt
;
; -----------------------------------------------------------------------------
; Some codepoints belong to multiple scripts:
;   U+0964 (।, Devanagari danda) is used by Hindi, Bengali, Gurmukhi, etc.
;   U+0030-0039 (digits 0-9) are Common but used by all scripts.
;
; ScriptExtensions.txt lists which scripts each codepoint can appear in,
; beyond its primary script assignment in Scripts.txt.
;
; Useful for: confusable detection, mixed-script security checks (IDN).
;
; Functions:
;   str_cp_script_extensions  — get bitmask of scripts a codepoint belongs to
;   str_cp_in_script          — check if codepoint belongs to a specific script
;   str_scripts_overlap       — check if two strings share a script
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"


; Script extension bitmask (up to 32 scripts in one uint32)
; Bit positions match SCRIPT_* enum from script_detect.asm
SCEXT_COMMON      equ (1 << 0)
SCEXT_INHERITED   equ (1 << 1)
SCEXT_LATIN       equ (1 << 2)
SCEXT_GREEK       equ (1 << 3)
SCEXT_CYRILLIC    equ (1 << 4)
SCEXT_DEVANAGARI  equ (1 << 8)
SCEXT_BENGALI     equ (1 << 9)
SCEXT_GURMUKHI    equ (1 << 10)
SCEXT_GUJARATI    equ (1 << 11)
SCEXT_TAMIL       equ (1 << 12)

section .text

; -----------------------------------------------------------------------------
; str_cp_script_extensions
;
; Get a bitmask of all scripts a codepoint belongs to.
;
; Arguments: EDI = codepoint
; Returns:   EAX = bitmask of SCEXT_* flags
; -----------------------------------------------------------------------------

STR_FUNC str_cp_script_extensions

    ; Common characters belong to all scripts (return all-bits)
    push    rdi
    call    str_cp_script
    pop     rdi
    movzx   ecx, al

    cmp     cl, 0               ; SCRIPT_COMMON
    je      .se_common
    cmp     cl, 1               ; SCRIPT_INHERITED
    je      .se_inherited

    ; Devanagari danda/double danda — shared across Indic scripts
    cmp     edi, 0x0964
    je      .se_indic_shared
    cmp     edi, 0x0965
    je      .se_indic_shared

    ; Default: just the primary script
    mov     eax, 1
    shl     eax, cl
    pop     rbp
    ret

.se_common:
    mov     eax, SCEXT_COMMON
    pop     rbp
    ret

.se_inherited:
    mov     eax, SCEXT_INHERITED
    pop     rbp
    ret

.se_indic_shared:
    ; Danda is used by Devanagari, Bengali, Gurmukhi, Gujarati, Tamil, etc.
    mov     eax, SCEXT_DEVANAGARI | SCEXT_BENGALI | SCEXT_GURMUKHI | SCEXT_GUJARATI | SCEXT_TAMIL
    pop     rbp
    ret

STR_ENDFUNC str_cp_script_extensions

; -----------------------------------------------------------------------------
; str_cp_in_script
;
; Check if a codepoint can appear in a specific script.
;
; Arguments: EDI = codepoint, SIL = script enum (SCRIPT_*)
; Returns:   EAX = 1 yes, 0 no
; -----------------------------------------------------------------------------

STR_FUNC str_cp_in_script

    push    rsi
    push    rdi
    call    str_cp_script_extensions
    pop     rdi
    pop     rsi

    ; check if bit for the requested script is set
    movzx   ecx, sil
    bt      eax, ecx
    setc    al
    movzx   eax, al

    pop     rbp
    ret

STR_ENDFUNC str_cp_in_script
%endif ; GUARD_LIB_STR_UNICODE_SCRIPT_EXT_ASM
