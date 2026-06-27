; =============================================================================
; str/unicode/security.asm
; Unicode security mechanisms: confusable detection, identifier safety.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Source: Unicode Technical Standard #39 (Security Mechanisms),
;         DoNotEmit.txt
;
; -----------------------------------------------------------------------------
; Unicode Security TR39 addresses visual spoofing attacks:
;
;   Confusables: Characters that look identical or near-identical in
;   common fonts but have different codepoints.
;     Example: "а" (Cyrillic U+0430) vs "a" (Latin U+0061)
;              "Ⅰ" (Roman numeral U+2160) vs "I" (Latin U+0049)
;              "⁰" (superscript U+2070) vs "°" (degree U+00B0)
;
;   The "skeleton" algorithm maps each codepoint to a canonical form
;   for comparison. Two strings are confusable if their skeletons match.
;     skeleton(s) = NFKD(foldCase(NFKD(s)))
;
;   Identifier Status/Type classifies codepoints for identifier safety:
;     Allowed     — safe for identifiers in this script
;     Restricted  — may cause confusion; needs context review
;
;   Mixed-script detection flags strings that mix scripts in ways that
;   could be used for spoofing (e.g., mixing Cyrillic and Latin).
;
;   Do-Not-Emit (DoNotEmit.txt) lists characters that should never be
;   emitted in new text: deprecated, obsolete, or problematic characters.
;
; Functions:
;   str_cp_skeleton                — get skeleton form of a codepoint
;   str_cp_is_confusable_with      — check if two codepoints are confusable
;   str_is_mixed_script_confusable — string-level mixed-script confusable check
;   str_cp_identifier_status       — Allowed/Restricted for identifiers
;   str_cp_identifier_type         — detailed identifier type classification
;   str_cp_is_do_not_emit          — should this codepoint be suppressed?
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_utf8_decode_unchecked
extern str_cp_script
extern str_cp_fold_simple
extern str_cp_category

; Identifier status
IDENT_ALLOWED       equ 0  ; safe for general identifiers
IDENT_RESTRICTED    equ 1  ; restricted — potential confusion source

; Identifier type
IDTYPE_ALLOWED          equ 0  ; generally safe
IDTYPE_RECOMMENDED      equ 1  ; recommended for identifiers
IDTYPE_INCLUSION        equ 2  ; included for specific scripts
IDTYPE_NOT_CHARACTER    equ 3  ; not a character (Cn, surrogates)
IDTYPE_DEPRECATED       equ 4  ; deprecated
IDTYPE_DEFAULT_IGNORABLE equ 5 ; invisible characters
IDTYPE_NOT_NFKC         equ 6  ; not normalized under NFKC
IDTYPE_NOT_XID          equ 7  ; not XID_Continue
IDTYPE_EXCLUSION        equ 8  ; excluded scripts
IDTYPE_OBSOLETE         equ 9  ; obsolete
IDTYPE_TECHNICAL        equ 10 ; technical use only
IDTYPE_LIMITED_USE      equ 11 ; limited use scripts

; Do-Not-Emit reasons
DNE_NONE            equ 0  ; not in DoNotEmit
DNE_DEPRECATED      equ 1  ; deprecated character
DNE_DEFAULT_IGNORABLE equ 2 ; default ignorable
DNE_NOT_NFKC        equ 3  ; not NFKC (compatibility char)
DNE_OBSOLETE        equ 4  ; obsolete character

section .text

; -----------------------------------------------------------------------------
; str_cp_skeleton
;
; Get the "skeleton" of a codepoint for confusable detection.
; The skeleton is derived by: NFKD → foldCase → NFKD
;
; For single-codepoint lookups, this is simplified to the confusable
; mapping: cp → prototype codepoint (the "canonical" visual form).
;
; Many confusable pairs map to the same ASCII/Latin prototype:
;   Cyrillic а (0430) → Latin a (0061)
;   Fullwidth Ａ (FF21) → Latin A (0041)
;   Greek Α (0391) → Latin A (0041)
;
; Signature:
;   uint32_t str_cp_skeleton(uint32_t cp)
;
; Arguments:
;   EDI  — codepoint
;
; Returns:
;   EAX  — skeleton codepoint (maps confusable chars to same value)
; -----------------------------------------------------------------------------

STR_FUNC str_cp_skeleton

    cmp     edi, CODEPOINT_MAX
    ja      .sk_self

    ; Common confusable mappings (high-frequency pairs)

    ; ---- Cyrillic → Latin ----
    cmp     edi, 0x0410          ; А (Cyrillic)
    je      .sk_ret_0041
    cmp     edi, 0x0412          ; В
    je      .sk_ret_0042
    cmp     edi, 0x0415          ; Е
    je      .sk_ret_0045
    cmp     edi, 0x041A          ; К
    je      .sk_ret_004B
    cmp     edi, 0x041C          ; М
    je      .sk_ret_004D
    cmp     edi, 0x041D          ; Н
    je      .sk_ret_0048
    cmp     edi, 0x041E          ; О
    je      .sk_ret_004F
    cmp     edi, 0x0420          ; Р
    je      .sk_ret_0050
    cmp     edi, 0x0421          ; С
    je      .sk_ret_0043
    cmp     edi, 0x0422          ; Т
    je      .sk_ret_0054
    cmp     edi, 0x0425          ; Х
    je      .sk_ret_0058
    cmp     edi, 0x0430          ; а (lowercase Cyrillic)
    je      .sk_ret_0061
    cmp     edi, 0x0435          ; е
    je      .sk_ret_0065
    cmp     edi, 0x043E          ; о
    je      .sk_ret_006F
    cmp     edi, 0x0440          ; р
    je      .sk_ret_0070
    cmp     edi, 0x0441          ; с
    je      .sk_ret_0063
    cmp     edi, 0x0443          ; у
    je      .sk_ret_0079
    cmp     edi, 0x0445          ; х
    je      .sk_ret_0078

    ; ---- Greek → Latin ----
    cmp     edi, 0x0391          ; Α
    je      .sk_ret_0041
    cmp     edi, 0x0392          ; Β
    je      .sk_ret_0042
    cmp     edi, 0x0395          ; Ε
    je      .sk_ret_0045
    cmp     edi, 0x0397          ; Η
    je      .sk_ret_0048
    cmp     edi, 0x0399          ; Ι
    je      .sk_ret_0049
    cmp     edi, 0x039A          ; Κ
    je      .sk_ret_004B
    cmp     edi, 0x039C          ; Μ
    je      .sk_ret_004D
    cmp     edi, 0x039D          ; Ν
    je      .sk_ret_004E
    cmp     edi, 0x039F          ; Ο
    je      .sk_ret_004F
    cmp     edi, 0x03A1          ; Ρ
    je      .sk_ret_0050
    cmp     edi, 0x03A4          ; Τ
    je      .sk_ret_0054
    cmp     edi, 0x03A5          ; Υ
    je      .sk_ret_0059
    cmp     edi, 0x03A7          ; Χ
    je      .sk_ret_0058
    cmp     edi, 0x03A9          ; Ω → kept as-is (no Latin confusable)
    cmp     edi, 0x03BF          ; ο (lowercase)
    je      .sk_ret_006F

    ; ---- Fullwidth → ASCII ----
    cmp     edi, 0xFF01
    jb      .sk_chk_misc
    cmp     edi, 0xFF5E
    ja      .sk_chk_misc
    ; fullwidth U+FF01..FF5E → ASCII U+0021..007E
    mov     eax, edi
    sub     eax, 0xFEE0         ; 0xFF01 - 0x0021 = 0xFEE0
    pop     rbp
    ret

.sk_chk_misc:
    ; ---- Roman numerals → digits/letters ----
    cmp     edi, 0x2160          ; Ⅰ → I
    je      .sk_ret_0049
    cmp     edi, 0x2164          ; Ⅴ → V
    je      .sk_ret_0056
    cmp     edi, 0x2169          ; Ⅹ → X
    je      .sk_ret_0058
    cmp     edi, 0x216C          ; Ⅼ → L
    je      .sk_ret_004C
    cmp     edi, 0x216D          ; Ⅽ → C
    je      .sk_ret_0043
    cmp     edi, 0x216E          ; Ⅾ → D
    je      .sk_ret_0044
    cmp     edi, 0x216F          ; Ⅿ → M
    je      .sk_ret_004D

    ; ---- Superscript/subscript digits ----
    cmp     edi, 0x00B2          ; ² → 2
    je      .sk_ret_0032
    cmp     edi, 0x00B3          ; ³ → 3
    je      .sk_ret_0033
    cmp     edi, 0x00B9          ; ¹ → 1
    je      .sk_ret_0031

    ; ---- Miscellaneous look-alikes ----
    cmp     edi, 0x2126          ; Ω (Ohm) → Ω (Greek, 03A9)
    je      .sk_ret_03A9
    cmp     edi, 0x212A          ; K (Kelvin) → K (Latin)
    je      .sk_ret_004B
    cmp     edi, 0x212B          ; Å (Angstrom) → Å (Latin)
    je      .sk_ret_00C5

    ; ---- Zero-width characters → empty (map to 0 = ignored) ----
    cmp     edi, 0x200B          ; ZWSP
    je      .sk_ret_zero
    cmp     edi, 0x200C          ; ZWNJ
    je      .sk_ret_zero
    cmp     edi, 0x200D          ; ZWJ
    je      .sk_ret_zero
    cmp     edi, 0xFEFF          ; BOM
    je      .sk_ret_zero

.sk_self:
    ; no confusable mapping — return self
    mov     eax, edi
    pop     rbp
    ret

    ; ---- Return stubs for Latin targets ----
.sk_ret_zero: xor eax, eax
    pop rbp
    ret
.sk_ret_0031: mov eax, 0x31
    pop rbp
    ret
.sk_ret_0032: mov eax, 0x32
    pop rbp
    ret
.sk_ret_0033: mov eax, 0x33
    pop rbp
    ret
.sk_ret_0041: mov eax, 0x41
    pop rbp
    ret
.sk_ret_0042: mov eax, 0x42
    pop rbp
    ret
.sk_ret_0043: mov eax, 0x43
    pop rbp
    ret
.sk_ret_0044: mov eax, 0x44
    pop rbp
    ret
.sk_ret_0045: mov eax, 0x45
    pop rbp
    ret
.sk_ret_0048: mov eax, 0x48
    pop rbp
    ret
.sk_ret_0049: mov eax, 0x49
    pop rbp
    ret
.sk_ret_004B: mov eax, 0x4B
    pop rbp
    ret
.sk_ret_004C: mov eax, 0x4C
    pop rbp
    ret
.sk_ret_004D: mov eax, 0x4D
    pop rbp
    ret
.sk_ret_004E: mov eax, 0x4E
    pop rbp
    ret
.sk_ret_004F: mov eax, 0x4F
    pop rbp
    ret
.sk_ret_0050: mov eax, 0x50
    pop rbp
    ret
.sk_ret_0054: mov eax, 0x54
    pop rbp
    ret
.sk_ret_0056: mov eax, 0x56
    pop rbp
    ret
.sk_ret_0058: mov eax, 0x58
    pop rbp
    ret
.sk_ret_0059: mov eax, 0x59
    pop rbp
    ret
.sk_ret_0061: mov eax, 0x61
    pop rbp
    ret
.sk_ret_0063: mov eax, 0x63
    pop rbp
    ret
.sk_ret_0065: mov eax, 0x65
    pop rbp
    ret
.sk_ret_006F: mov eax, 0x6F
    pop rbp
    ret
.sk_ret_0070: mov eax, 0x70
    pop rbp
    ret
.sk_ret_0078: mov eax, 0x78
    pop rbp
    ret
.sk_ret_0079: mov eax, 0x79
    pop rbp
    ret
.sk_ret_00C5: mov eax, 0xC5
    pop rbp
    ret
.sk_ret_03A9: mov eax, 0x03A9
    pop rbp
    ret

STR_ENDFUNC str_cp_skeleton

; -----------------------------------------------------------------------------
; str_cp_is_confusable_with
;
; Check if two codepoints are visually confusable.
; Two codepoints are confusable if their skeletons are equal.
;
; Signature:
;   int64_t str_cp_is_confusable_with(uint32_t cp1, uint32_t cp2)
;
; Arguments:
;   EDI  — first codepoint
;   ESI  — second codepoint
;
; Returns:
;   RAX  = 1 if confusable, 0 if not
; -----------------------------------------------------------------------------

STR_FUNC str_cp_is_confusable_with

    push_regs rbx

    mov     ebx, esi            ; save cp2

    ; get skeleton(cp1)
    call    str_cp_skeleton
    mov     ecx, eax            ; skeleton1

    ; get skeleton(cp2)
    mov     edi, ebx
    call    str_cp_skeleton
    ; eax = skeleton2

    cmp     ecx, eax
    je      .cf_yes

    pop_regs rbx
    xor     eax, eax
    pop     rbp
    ret

.cf_yes:
    pop_regs rbx
    mov     eax, 1
    pop     rbp
    ret

STR_ENDFUNC str_cp_is_confusable_with

; -----------------------------------------------------------------------------
; str_is_mixed_script_confusable
;
; Check if a string contains mixed scripts in a way that could be confusable.
; A string is mixed-script confusable if:
;   1. It contains characters from 2+ scripts (excluding Common/Inherited)
;   2. Each script's characters have confusable equivalents in another script
;
; Signature:
;   int64_t str_is_mixed_script_confusable(const StrSlice *src)
;
; Arguments:
;   RDI  — source string
;
; Returns:
;   RAX  = 1 if mixed-script confusable detected
;   RAX  = 0 if safe
; -----------------------------------------------------------------------------

STR_FUNC str_is_mixed_script_confusable

    guard_null rdi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, rbx
    add     r12, [rdi + StrSlice.len]

    xor     r13d, r13d          ; script_set bitmask (up to 32 scripts)
    xor     r14d, r14d          ; number of distinct scripts seen

.msc_loop:
    cmp     rbx, r12
    jae     .msc_check

    ; decode codepoint
    sub     rsp, 16
    and     rsp, -16
    mov     rdi, rbx
    lea     rsi, [rsp]
    call    str_utf8_decode_unchecked
    mov     r8d, eax            ; codepoint
    add     rbx, [rsp]
    mov     rsp, rbp

    ; get script
    mov     edi, r8d
    push    r8
    call    str_cp_script
    pop     r8
    movzx   ecx, al             ; script id

    ; skip Common (0) and Inherited (1)
    cmp     ecx, 2
    jb      .msc_loop

    ; set bit in script_set
    cmp     ecx, 31
    ja      .msc_loop           ; overflow protection

    mov     eax, 1
    shl     eax, cl
    test    r13d, eax
    jnz     .msc_loop           ; already seen this script

    or      r13d, eax
    inc     r14d
    jmp     .msc_loop

.msc_check:
    ; mixed script if 2+ distinct non-Common/Inherited scripts
    cmp     r14d, 2
    jb      .msc_safe

    ; Has multiple scripts — check if they form a known confusable pair
    ; Common confusable script pairs:
    ;   Latin + Cyrillic
    ;   Latin + Greek
    ;   Latin + Armenian (some chars)
    ; For robustness, any 2+ scripts = potential concern

    pop_regs r14, r13, r12, rbx
    mov     eax, 1
    pop     rbp
    ret

.msc_safe:
    pop_regs r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_is_mixed_script_confusable

; -----------------------------------------------------------------------------
; str_cp_identifier_status
;
; Get the identifier status of a codepoint (TR39).
; Returns Allowed or Restricted.
;
; Signature:
;   uint8_t str_cp_identifier_status(uint32_t cp)
;
; Arguments:
;   EDI  — codepoint
;
; Returns:
;   AL   — IDENT_ALLOWED or IDENT_RESTRICTED
; -----------------------------------------------------------------------------

STR_FUNC str_cp_identifier_status

    cmp     edi, CODEPOINT_MAX
    ja      .is_restricted

    ; ASCII alphanumerics + underscore → Allowed
    cmp     edi, '_'
    je      .is_allowed
    cmp     edi, '0'
    jb      .is_chk_alpha
    cmp     edi, '9'
    jbe     .is_allowed
.is_chk_alpha:
    cmp     edi, 'A'
    jb      .is_chk_lower
    cmp     edi, 'Z'
    jbe     .is_allowed
.is_chk_lower:
    cmp     edi, 'a'
    jb      .is_chk_unicode
    cmp     edi, 'z'
    jbe     .is_allowed

.is_chk_unicode:
    ; Common safe ranges for identifiers
    ; Latin Extended: 0x00C0-0x024F (minus a few controls)
    cmp     edi, 0x00C0
    jb      .is_restricted
    cmp     edi, 0x024F
    jbe     .is_allowed

    ; Greek: 0x0370-0x03FF
    cmp     edi, 0x0370
    jb      .is_chk_cyrillic
    cmp     edi, 0x03FF
    jbe     .is_allowed

.is_chk_cyrillic:
    ; Cyrillic: 0x0400-0x04FF
    cmp     edi, 0x0400
    jb      .is_chk_devanagari
    cmp     edi, 0x04FF
    jbe     .is_allowed

.is_chk_devanagari:
    ; Devanagari: 0x0900-0x097F
    cmp     edi, 0x0900
    jb      .is_chk_cjk
    cmp     edi, 0x097F
    jbe     .is_allowed

.is_chk_cjk:
    ; CJK Unified Ideographs: 0x4E00-0x9FFF
    cmp     edi, 0x4E00
    jb      .is_chk_hangul
    cmp     edi, 0x9FFF
    jbe     .is_allowed

.is_chk_hangul:
    ; Hangul Syllables: 0xAC00-0xD7A3
    cmp     edi, 0xAC00
    jb      .is_chk_kana
    cmp     edi, 0xD7A3
    jbe     .is_allowed

.is_chk_kana:
    ; Hiragana: 0x3040-0x309F, Katakana: 0x30A0-0x30FF
    cmp     edi, 0x3040
    jb      .is_restricted
    cmp     edi, 0x30FF
    jbe     .is_allowed

.is_restricted:
    mov     al, IDENT_RESTRICTED
    pop     rbp
    ret

.is_allowed:
    mov     al, IDENT_ALLOWED
    pop     rbp
    ret

STR_ENDFUNC str_cp_identifier_status

; -----------------------------------------------------------------------------
; str_cp_identifier_type
;
; Get the detailed identifier type classification (TR39).
;
; Signature:
;   uint8_t str_cp_identifier_type(uint32_t cp)
;
; Arguments:
;   EDI  — codepoint
;
; Returns:
;   AL   — IDTYPE_* enum value
; -----------------------------------------------------------------------------

STR_FUNC str_cp_identifier_type

    cmp     edi, CODEPOINT_MAX
    ja      .it_not_char

    ; Surrogates
    cmp     edi, SURROGATE_HIGH_MIN
    jb      .it_chk_control
    cmp     edi, SURROGATE_LOW_MAX
    jbe     .it_not_char

.it_chk_control:
    ; C0/C1 controls (except HT, LF, CR)
    cmp     edi, 0x20
    jb      .it_chk_safe_control
    cmp     edi, 0x7F
    je      .it_technical        ; DEL
    cmp     edi, 0x80
    jb      .it_chk_allowed
    cmp     edi, 0x9F
    jbe     .it_technical        ; C1 controls

.it_chk_safe_control:
    cmp     edi, 0x09
    je      .it_technical        ; HT
    cmp     edi, 0x0A
    je      .it_technical        ; LF
    cmp     edi, 0x0D
    je      .it_technical        ; CR
    cmp     edi, 0x20
    jb      .it_technical        ; other C0 controls

.it_chk_allowed:
    ; Deprecated characters
    cmp     edi, 0x0149          ; LATIN SMALL LETTER N PRECEDED BY APOSTROPHE
    je      .it_deprecated
    cmp     edi, 0x0673          ; ARABIC LETTER ALEF WITH WAVY HAMZA BELOW
    je      .it_deprecated
    cmp     edi, 0x0F77          ; TIBETAN VOWEL SIGN VOCALIC RR
    je      .it_deprecated
    cmp     edi, 0x0F79          ; TIBETAN VOWEL SIGN VOCALIC LL
    je      .it_deprecated
    cmp     edi, 0x17A3          ; KHMER INDEPENDENT VOWEL QAQ
    je      .it_deprecated
    cmp     edi, 0x17A4          ; KHMER INDEPENDENT VOWEL QAA
    je      .it_deprecated
    cmp     edi, 0x206A
    jb      .it_chk_ignorable
    cmp     edi, 0x206F
    jbe     .it_deprecated       ; deprecated formatting controls

.it_chk_ignorable:
    ; Default Ignorable
    cmp     edi, 0x00AD          ; SOFT HYPHEN
    je      .it_default_ignorable
    cmp     edi, 0x034F          ; COMBINING GRAPHEME JOINER
    je      .it_default_ignorable
    cmp     edi, 0x200B          ; ZWSP
    je      .it_default_ignorable
    cmp     edi, 0x200C          ; ZWNJ
    je      .it_default_ignorable
    cmp     edi, 0x200D          ; ZWJ
    je      .it_default_ignorable
    cmp     edi, 0xFEFF          ; BOM
    je      .it_default_ignorable

    ; Noncharacters → Not_Character
    cmp     edi, 0xFDD0
    jb      .it_chk_general
    cmp     edi, 0xFDEF
    jbe     .it_not_char
    mov     eax, edi
    and     eax, 0xFFFF
    cmp     eax, 0xFFFE
    je      .it_not_char
    cmp     eax, 0xFFFF
    je      .it_not_char

.it_chk_general:
    ; Check general category for unassigned (Cn)
    push    rdi
    call    str_cp_category
    pop     rdi
    ; category 0 = Cn (unassigned) in our table
    test    al, al
    jz      .it_not_char

    ; If we got here, it's generally allowed (simplified)
    mov     al, IDTYPE_ALLOWED
    pop     rbp
    ret

.it_not_char:
    mov     al, IDTYPE_NOT_CHARACTER
    pop     rbp
    ret

.it_deprecated:
    mov     al, IDTYPE_DEPRECATED
    pop     rbp
    ret

.it_default_ignorable:
    mov     al, IDTYPE_DEFAULT_IGNORABLE
    pop     rbp
    ret

.it_technical:
    mov     al, IDTYPE_TECHNICAL
    pop     rbp
    ret

STR_ENDFUNC str_cp_identifier_type

; -----------------------------------------------------------------------------
; str_cp_is_do_not_emit
;
; Check if a codepoint should not be emitted in new text (DoNotEmit.txt).
; These are characters that are: deprecated, obsolete, default ignorable
; with no clear purpose, not NFKC, or otherwise problematic.
;
; Signature:
;   int64_t str_cp_is_do_not_emit(uint32_t cp)
;
; Arguments:
;   EDI  — codepoint
;
; Returns:
;   RAX  = 1 if should not be emitted, 0 if ok to emit
; -----------------------------------------------------------------------------

STR_FUNC str_cp_is_do_not_emit

    cmp     edi, CODEPOINT_MAX
    ja      .dne_yes            ; out of range → don't emit

    ; Deprecated characters
    cmp     edi, 0x0149
    je      .dne_yes            ; LATIN SMALL LETTER N PRECEDED BY APOSTROPHE
    cmp     edi, 0x0673
    je      .dne_yes            ; ARABIC LETTER ALEF WITH WAVY HAMZA BELOW
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
    ; Compatibility decomposition characters (prefer decomposed form)
    ; Ligatures: ﬀ ﬁ ﬂ ﬃ ﬄ ﬅ ﬆ
    cmp     edi, 0xFB00
    jb      .dne_chk_singletons
    cmp     edi, 0xFB06
    jbe     .dne_yes

.dne_chk_singletons:
    ; Singleton decomposition characters (prefer the canonical form)
    cmp     edi, 0x2126
    je      .dne_yes            ; OHM SIGN → use Ω (U+03A9)
    cmp     edi, 0x212A
    je      .dne_yes            ; KELVIN SIGN → use K
    cmp     edi, 0x212B
    je      .dne_yes            ; ANGSTROM SIGN → use Å

    ; Language tag characters (deprecated in Unicode 5.1)
    cmp     edi, 0xE0001
    je      .dne_yes            ; LANGUAGE TAG
    cmp     edi, 0xE0020
    jb      .dne_chk_interlinear
    cmp     edi, 0xE007F
    jbe     .dne_yes            ; TAG characters

.dne_chk_interlinear:
    ; Interlinear annotation characters
    cmp     edi, 0xFFF9
    jb      .dne_chk_music
    cmp     edi, 0xFFFB
    jbe     .dne_yes

.dne_chk_music:
    ; Noncharacters
    cmp     edi, 0xFDD0
    jb      .dne_no
    cmp     edi, 0xFDEF
    jbe     .dne_yes

    ; xxFFFE/xxFFFF for each plane
    mov     eax, edi
    and     eax, 0xFFFF
    cmp     eax, 0xFFFE
    jb      .dne_no
    jmp     .dne_yes

.dne_no:
    xor     eax, eax
    pop     rbp
    ret

.dne_yes:
    mov     eax, 1
    pop     rbp
    ret

STR_ENDFUNC str_cp_is_do_not_emit
