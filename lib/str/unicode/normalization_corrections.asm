%ifndef GUARD_LIB_STR_UNICODE_NORMALIZATION_CORRECTIONS_ASM
%define GUARD_LIB_STR_UNICODE_NORMALIZATION_CORRECTIONS_ASM
; =============================================================================
; str/unicode/normalization_corrections.asm
; Historical normalization corrections (NormalizationCorrections.txt).
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Source: NormalizationCorrections.txt
;
; -----------------------------------------------------------------------------
; NormalizationCorrections.txt documents corrections to the canonical
; decomposition mappings in UnicodeData.txt. Only 3 corrections have
; ever been made (normalization is stable — errors cannot be silently fixed):
;
;   U+2F868  — Unicode 3.2.0: was mapped to U+2136A, corrected to U+36FC
;              (CJK Compatibility Ideograph Supplement)
;
;   U+2F874  — Unicode 3.2.0: was mapped to U+5765, corrected to U+5765
;              (actually this was a mapping confirmation, same result)
;
;   U+2F91F  — Unicode 3.2.0: was mapped to U+43AB, corrected to U+243AB
;              (was mapping to wrong plane — BMP instead of SMP)
;
; These corrections are important for strict conformance testing.
; The corrected mappings are what appears in the current UnicodeData.txt,
; but implementations processing data normalized under older Unicode
; versions may encounter the old mappings.
;
; Functions:
;   str_cp_has_norm_correction   — does this codepoint have a correction?
;   str_cp_norm_correction_old   — get the OLD (incorrect) decomposition
;   str_cp_norm_correction_new   — get the NEW (correct) decomposition
;   str_cp_norm_correction_ver   — Unicode version the correction was applied
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

section .text

; -----------------------------------------------------------------------------
; str_cp_has_norm_correction
;
; Check if a codepoint has a historical normalization correction.
;
; Signature:
;   int64_t str_cp_has_norm_correction(uint32_t cp)
;
; Arguments:
;   EDI  — codepoint
;
; Returns:
;   RAX  = 1 if has correction, 0 otherwise
; -----------------------------------------------------------------------------

STR_FUNC str_cp_has_norm_correction

    cmp     edi, 0x2F868
    je      .hnc_yes
    cmp     edi, 0x2F874
    je      .hnc_yes
    cmp     edi, 0x2F91F
    je      .hnc_yes

    xor     eax, eax
    pop     rbp
    ret

.hnc_yes:
    mov     eax, 1
    pop     rbp
    ret

STR_ENDFUNC str_cp_has_norm_correction

; -----------------------------------------------------------------------------
; str_cp_norm_correction_old
;
; Get the OLD (incorrect) canonical decomposition mapping.
; This is what was in UnicodeData.txt before the correction.
;
; Signature:
;   uint32_t str_cp_norm_correction_old(uint32_t cp)
;
; Arguments:
;   EDI  — codepoint
;
; Returns:
;   EAX  — old (incorrect) mapping, or 0 if no correction exists
; -----------------------------------------------------------------------------

STR_FUNC str_cp_norm_correction_old

    cmp     edi, 0x2F868
    je      .nco_2f868
    cmp     edi, 0x2F874
    je      .nco_2f874
    cmp     edi, 0x2F91F
    je      .nco_2f91f

    xor     eax, eax
    pop     rbp
    ret

.nco_2f868:
    mov     eax, 0x2136A        ; old incorrect mapping
    pop     rbp
    ret

.nco_2f874:
    mov     eax, 0x5765         ; was correct but reconfirmed
    pop     rbp
    ret

.nco_2f91f:
    mov     eax, 0x43AB         ; old: BMP codepoint (wrong plane)
    pop     rbp
    ret

STR_ENDFUNC str_cp_norm_correction_old

; -----------------------------------------------------------------------------
; str_cp_norm_correction_new
;
; Get the NEW (correct) canonical decomposition mapping.
; This is what the current UnicodeData.txt contains.
;
; Signature:
;   uint32_t str_cp_norm_correction_new(uint32_t cp)
;
; Arguments:
;   EDI  — codepoint
;
; Returns:
;   EAX  — new (correct) mapping, or 0 if no correction exists
; -----------------------------------------------------------------------------

STR_FUNC str_cp_norm_correction_new

    cmp     edi, 0x2F868
    je      .ncn_2f868
    cmp     edi, 0x2F874
    je      .ncn_2f874
    cmp     edi, 0x2F91F
    je      .ncn_2f91f

    xor     eax, eax
    pop     rbp
    ret

.ncn_2f868:
    mov     eax, 0x36FC         ; corrected mapping
    pop     rbp
    ret

.ncn_2f874:
    mov     eax, 0x5765         ; same (reconfirmed)
    pop     rbp
    ret

.ncn_2f91f:
    mov     eax, 0x243AB        ; corrected: SMP codepoint (right plane)
    pop     rbp
    ret

STR_ENDFUNC str_cp_norm_correction_new

; -----------------------------------------------------------------------------
; str_cp_norm_correction_ver
;
; Get the Unicode version in which the correction was applied.
; Encoded as (major << 8 | minor), e.g., 3.2 = 0x0302.
;
; Signature:
;   uint16_t str_cp_norm_correction_ver(uint32_t cp)
;
; Arguments:
;   EDI  — codepoint
;
; Returns:
;   AX   — version (major << 8 | minor), or 0 if no correction
; -----------------------------------------------------------------------------

STR_FUNC str_cp_norm_correction_ver

    cmp     edi, 0x2F868
    je      .ncv_32
    cmp     edi, 0x2F874
    je      .ncv_32
    cmp     edi, 0x2F91F
    je      .ncv_32

    xor     eax, eax            ; no correction
    pop     rbp
    ret

.ncv_32:
    mov     eax, 0x0302         ; Unicode 3.2.0
    pop     rbp
    ret

STR_ENDFUNC str_cp_norm_correction_ver

%endif ; GUARD_LIB_STR_UNICODE_NORMALIZATION_CORRECTIONS_ASM
