; =============================================================================
; str/unicode/equivalent_ideograph.asm
; CJK Compatibility → Unified Ideograph mapping.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Source: EquivalentUnifiedIdeograph.txt
;
; -----------------------------------------------------------------------------
; CJK Compatibility Ideographs are duplicate encodings of CJK Unified
; Ideographs. They exist for round-trip compatibility with legacy standards
; (JIS, KS, CNS, etc.) but should generally be replaced with their
; unified equivalents in new text.
;
; Ranges:
;   U+F900..U+FA6D    — CJK Compatibility Ideographs (BMP)
;   U+FA70..U+FAD9    — CJK Compatibility Ideographs (BMP, additional)
;   U+2F800..U+2FA1D  — CJK Compatibility Ideographs Supplement (SMP)
;
; Note: Not all codepoints in these ranges are compatibility ideographs.
; Some are unified ideographs that were misplaced historically.
; The ones with canonical decompositions (in UnicodeData.txt) map to
; their unified equivalents. Those without decompositions are "true"
; unified ideographs that happen to be in the compatibility block.
;
; Functions:
;   str_cp_equivalent_unified   — get the unified ideograph equivalent
;   str_cp_is_compat_ideograph  — is this a CJK compatibility ideograph?
;   str_cp_is_cjk_unified      — is this in the CJK Unified Ideographs range?
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern _ucd_decomp_index
extern _ucd_decomp_data

section .text

; -----------------------------------------------------------------------------
; str_cp_equivalent_unified
;
; Get the equivalent CJK Unified Ideograph for a compatibility ideograph.
; If the codepoint is not a compatibility ideograph, returns 0.
;
; Signature:
;   uint32_t str_cp_equivalent_unified(uint32_t cp)
;
; Arguments:
;   EDI  — codepoint (potentially a compat ideograph)
;
; Returns:
;   EAX  — the unified equivalent, or 0 if not a compat ideograph
; -----------------------------------------------------------------------------

STR_FUNC str_cp_equivalent_unified

    ; BMP CJK Compatibility Ideographs: U+F900-U+FA6D
    cmp     edi, 0xF900
    jb      .eu_chk_smp
    cmp     edi, 0xFA6D
    jbe     .eu_bmp_lookup

    ; Additional: U+FA70-U+FAD9
    cmp     edi, 0xFA70
    jb      .eu_chk_smp
    cmp     edi, 0xFAD9
    jbe     .eu_bmp_lookup

.eu_chk_smp:
    ; SMP CJK Compatibility Ideographs Supplement: U+2F800-U+2FA1D
    cmp     edi, 0x2F800
    jb      .eu_none
    cmp     edi, 0x2FA1D
    ja      .eu_none

    ; SMP entries: these all have canonical decompositions to single chars
    ; For a full implementation, this would use a dedicated SMP table.
    ; Simplified: return 0 (table-driven in full build)
    jmp     .eu_none

.eu_bmp_lookup:
    ; look up canonical decomposition from table
    ; compat ideographs with decompositions map to exactly 1 codepoint
    lea     rax, [rel _ucd_decomp_index]
    mov     eax, [rax + rdi * 4]

    ; check if has canonical decomposition (type == 1)
    mov     ecx, eax
    and     ecx, 0x0F
    cmp     ecx, 1              ; DECOMP_CANONICAL
    jne     .eu_none            ; no decomposition or compat type (unexpected)

    ; get length — should be 1 (singleton)
    mov     edx, eax
    shr     edx, 4
    and     edx, 0x0F
    cmp     edx, 1
    jne     .eu_none            ; multi-char decomp — not a simple mapping

    ; get the equivalent codepoint
    shr     eax, 8              ; offset into decomp_data
    lea     rcx, [rel _ucd_decomp_data]
    mov     eax, [rcx + rax * 4]
    pop     rbp
    ret

.eu_none:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_cp_equivalent_unified

; -----------------------------------------------------------------------------
; str_cp_is_compat_ideograph
;
; Check if a codepoint is in the CJK Compatibility Ideographs range.
; Note: some codepoints in this range are actually unified (no decomposition).
;
; Signature:
;   int64_t str_cp_is_compat_ideograph(uint32_t cp)
;
; Arguments:
;   EDI  — codepoint
;
; Returns:
;   RAX  = 1 if in compat ideograph range, 0 otherwise
; -----------------------------------------------------------------------------

STR_FUNC str_cp_is_compat_ideograph

    ; BMP range 1
    cmp     edi, 0xF900
    jb      .ci_chk_range2
    cmp     edi, 0xFA6D
    jbe     .ci_yes

.ci_chk_range2:
    ; BMP range 2
    cmp     edi, 0xFA70
    jb      .ci_chk_smp
    cmp     edi, 0xFAD9
    jbe     .ci_yes

.ci_chk_smp:
    ; SMP supplement
    cmp     edi, 0x2F800
    jb      .ci_no
    cmp     edi, 0x2FA1D
    jbe     .ci_yes

.ci_no:
    xor     eax, eax
    pop     rbp
    ret

.ci_yes:
    mov     eax, 1
    pop     rbp
    ret

STR_ENDFUNC str_cp_is_compat_ideograph

; -----------------------------------------------------------------------------
; str_cp_is_cjk_unified
;
; Check if a codepoint is in the CJK Unified Ideographs block (main block).
; This includes the main block and extension blocks A-I.
;
; Signature:
;   int64_t str_cp_is_cjk_unified(uint32_t cp)
;
; Arguments:
;   EDI  — codepoint
;
; Returns:
;   RAX  = 1 if CJK Unified Ideograph, 0 otherwise
; -----------------------------------------------------------------------------

STR_FUNC str_cp_is_cjk_unified

    ; CJK Unified Ideographs: U+4E00-U+9FFF
    cmp     edi, 0x4E00
    jb      .cu_chk_ext_a
    cmp     edi, 0x9FFF
    jbe     .cu_yes

.cu_chk_ext_a:
    ; Extension A: U+3400-U+4DBF
    cmp     edi, 0x3400
    jb      .cu_chk_ext_b
    cmp     edi, 0x4DBF
    jbe     .cu_yes

.cu_chk_ext_b:
    ; Extension B: U+20000-U+2A6DF
    cmp     edi, 0x20000
    jb      .cu_chk_ext_c
    cmp     edi, 0x2A6DF
    jbe     .cu_yes

.cu_chk_ext_c:
    ; Extension C: U+2A700-U+2B73F
    cmp     edi, 0x2A700
    jb      .cu_chk_ext_d
    cmp     edi, 0x2B73F
    jbe     .cu_yes

.cu_chk_ext_d:
    ; Extension D: U+2B740-U+2B81F
    cmp     edi, 0x2B740
    jb      .cu_chk_ext_e
    cmp     edi, 0x2B81F
    jbe     .cu_yes

.cu_chk_ext_e:
    ; Extension E: U+2B820-U+2CEAF
    cmp     edi, 0x2B820
    jb      .cu_chk_ext_f
    cmp     edi, 0x2CEAF
    jbe     .cu_yes

.cu_chk_ext_f:
    ; Extension F: U+2CEB0-U+2EBEF
    cmp     edi, 0x2CEB0
    jb      .cu_chk_ext_g
    cmp     edi, 0x2EBEF
    jbe     .cu_yes

.cu_chk_ext_g:
    ; Extension G: U+30000-U+3134F
    cmp     edi, 0x30000
    jb      .cu_chk_ext_h
    cmp     edi, 0x3134F
    jbe     .cu_yes

.cu_chk_ext_h:
    ; Extension H: U+31350-U+323AF
    cmp     edi, 0x31350
    jb      .cu_chk_ext_i
    cmp     edi, 0x323AF
    jbe     .cu_yes

.cu_chk_ext_i:
    ; Extension I: U+2EBF0-U+2F7FF (proposed — may not be in final spec)
    cmp     edi, 0x2EBF0
    jb      .cu_no
    cmp     edi, 0x2F7FF
    jbe     .cu_yes

.cu_no:
    xor     eax, eax
    pop     rbp
    ret

.cu_yes:
    mov     eax, 1
    pop     rbp
    ret

STR_ENDFUNC str_cp_is_cjk_unified
