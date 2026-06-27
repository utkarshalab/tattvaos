; =============================================================================
; str/unicode/standardized_variants.asm
; Standardized variation sequences (StandardizedVariants.txt).
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Source: StandardizedVariants.txt, emoji/emoji-variation-sequences.txt
;
; -----------------------------------------------------------------------------
; Variation sequences are base_codepoint + variation_selector pairs that
; select specific glyph variants. Three types of variation selectors:
;
; 1. Mongolian Free Variation Selectors (FVS1-FVS4):
;    U+180B..U+180E — select glyph forms for Mongolian letters
;
; 2. Standardized Variation Selectors (VS1-VS256):
;    U+FE00..U+FE0F (VS1-VS16)     — BMP variation selectors
;    U+E0100..U+E01EF (VS17-VS256) — supplementary variation selectors
;
;    VS15 (U+FE0E) = text presentation selector
;    VS16 (U+FE0F) = emoji presentation selector
;
;    CJK: many ideographs have VS sequences for glyph selection
;    (Japanese vs Chinese vs Korean standard forms)
;
; 3. Ideographic Variation Sequences (IVS):
;    Registered in the IVD (Ideographic Variation Database).
;    base_ideograph + VS17-VS256
;
; Functions:
;   str_cp_is_variation_selector   — is this a variation selector?
;   str_cp_variation_selector_num  — VS1..VS256 number (1-based)
;   str_cp_has_standardized_variant — does base cp have standardized variants?
;   str_cp_variant_count           — how many variants for this base cp?
;   str_is_text_presentation       — is this VS15 (text style)?
;   str_is_emoji_presentation_vs   — is this VS16 (emoji style)?
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

section .text

; -----------------------------------------------------------------------------
; str_cp_is_variation_selector
;
; Check if a codepoint is any type of variation selector.
;
; Signature:
;   int64_t str_cp_is_variation_selector(uint32_t cp)
;
; Arguments:
;   EDI  — codepoint
;
; Returns:
;   RAX  = 1 if variation selector, 0 otherwise
; -----------------------------------------------------------------------------

STR_FUNC str_cp_is_variation_selector

    ; Mongolian FVS1-FVS4: U+180B-U+180E
    cmp     edi, 0x180B
    jb      .vs_chk_bmp
    cmp     edi, 0x180E
    jbe     .vs_yes

.vs_chk_bmp:
    ; BMP VS1-VS16: U+FE00-U+FE0F
    cmp     edi, 0xFE00
    jb      .vs_chk_supp
    cmp     edi, 0xFE0F
    jbe     .vs_yes

.vs_chk_supp:
    ; Supplementary VS17-VS256: U+E0100-U+E01EF
    cmp     edi, 0xE0100
    jb      .vs_no
    cmp     edi, 0xE01EF
    jbe     .vs_yes

.vs_no:
    xor     eax, eax
    pop     rbp
    ret

.vs_yes:
    mov     eax, 1
    pop     rbp
    ret

STR_ENDFUNC str_cp_is_variation_selector

; -----------------------------------------------------------------------------
; str_cp_variation_selector_num
;
; Get the variation selector number (1-based) for a VS codepoint.
;
; Signature:
;   int64_t str_cp_variation_selector_num(uint32_t cp)
;
; Arguments:
;   EDI  — codepoint (must be a variation selector)
;
; Returns:
;   RAX  = 1-256 for VS1-VS256
;   RAX  = 0 if not a variation selector
;   RAX  = -1..-4 for Mongolian FVS1-FVS4
; -----------------------------------------------------------------------------

STR_FUNC str_cp_variation_selector_num

    ; Mongolian FVS
    cmp     edi, 0x180B
    jb      .vsn_chk_bmp
    cmp     edi, 0x180E
    ja      .vsn_chk_bmp
    ; FVS1-FVS4: encoded as -1 to -4 (negative = Mongolian)
    mov     eax, 0x180B
    sub     eax, edi
    dec     eax                 ; FVS1=0x180B → -1, FVS2=0x180C → -2, etc.
    pop     rbp
    ret

.vsn_chk_bmp:
    ; BMP VS1-VS16: U+FE00-U+FE0F → 1-16
    cmp     edi, 0xFE00
    jb      .vsn_chk_supp
    cmp     edi, 0xFE0F
    ja      .vsn_chk_supp
    mov     eax, edi
    sub     eax, 0xFE00
    inc     eax                 ; 1-based
    pop     rbp
    ret

.vsn_chk_supp:
    ; Supplementary VS17-VS256: U+E0100-U+E01EF → 17-256
    cmp     edi, 0xE0100
    jb      .vsn_none
    cmp     edi, 0xE01EF
    ja      .vsn_none
    mov     eax, edi
    sub     eax, 0xE0100
    add     eax, 17             ; 17-based
    pop     rbp
    ret

.vsn_none:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_cp_variation_selector_num

; -----------------------------------------------------------------------------
; str_cp_has_standardized_variant
;
; Check if a base codepoint has any standardized variation sequences.
;
; Signature:
;   int64_t str_cp_has_standardized_variant(uint32_t cp)
;
; Arguments:
;   EDI  — base codepoint
;
; Returns:
;   RAX  = 1 if has variants, 0 otherwise
; -----------------------------------------------------------------------------

STR_FUNC str_cp_has_standardized_variant

    ; Emoji with text/emoji presentation variants
    ; Most emoji in 0x2600+ range have VS15/VS16 variants
    cmp     edi, 0x2600
    jb      .hsv_chk_cjk
    cmp     edi, 0x27BF
    jbe     .hsv_yes            ; Misc Symbols + Dingbats

    cmp     edi, 0x1F300
    jb      .hsv_chk_text_emoji
    cmp     edi, 0x1FAFF
    jbe     .hsv_yes            ; SMP emoji blocks

.hsv_chk_text_emoji:
    ; Text-style emoji with VS variants
    cmp     edi, 0x203C
    je      .hsv_yes            ; ‼
    cmp     edi, 0x2049
    je      .hsv_yes            ; ⁉
    cmp     edi, '#'
    je      .hsv_yes            ; keycap #
    cmp     edi, '*'
    je      .hsv_yes            ; keycap *
    cmp     edi, '0'
    jb      .hsv_chk_cjk
    cmp     edi, '9'
    jbe     .hsv_yes            ; keycap digits

.hsv_chk_cjk:
    ; CJK Unified Ideographs with IVS entries
    ; Many CJK ideographs have variation sequences for JIS/CNS/KS standards
    cmp     edi, 0x4E00
    jb      .hsv_chk_compat
    cmp     edi, 0x9FFF
    jbe     .hsv_yes            ; CJK unified (many have IVS)

    ; CJK Extension A
    cmp     edi, 0x3400
    jb      .hsv_chk_compat
    cmp     edi, 0x4DBF
    jbe     .hsv_yes

.hsv_chk_compat:
    ; CJK Compatibility Ideographs
    cmp     edi, 0xF900
    jb      .hsv_chk_mongolian
    cmp     edi, 0xFAFF
    jbe     .hsv_yes

.hsv_chk_mongolian:
    ; Mongolian letters with FVS variants
    cmp     edi, 0x1820
    jb      .hsv_no
    cmp     edi, 0x1878
    jbe     .hsv_yes

.hsv_no:
    xor     eax, eax
    pop     rbp
    ret

.hsv_yes:
    mov     eax, 1
    pop     rbp
    ret

STR_ENDFUNC str_cp_has_standardized_variant

; -----------------------------------------------------------------------------
; str_cp_variant_count
;
; Get the number of standardized variation sequences for a base codepoint.
;
; Signature:
;   uint64_t str_cp_variant_count(uint32_t cp)
;
; Arguments:
;   EDI  — base codepoint
;
; Returns:
;   RAX  — number of variants (0 if none)
; -----------------------------------------------------------------------------

STR_FUNC str_cp_variant_count

    ; Emoji with text/emoji presentation: typically 2 (VS15 + VS16)
    cmp     edi, 0x2600
    jb      .vc_chk_cjk
    cmp     edi, 0x27BF
    jbe     .vc_ret_2

    cmp     edi, 0x1F300
    jb      .vc_chk_text_emoji
    cmp     edi, 0x1FAFF
    jbe     .vc_ret_2

.vc_chk_text_emoji:
    cmp     edi, 0x203C
    je      .vc_ret_2
    cmp     edi, 0x2049
    je      .vc_ret_2
    cmp     edi, '#'
    je      .vc_ret_2
    cmp     edi, '*'
    je      .vc_ret_2
    cmp     edi, '0'
    jb      .vc_chk_cjk
    cmp     edi, '9'
    jbe     .vc_ret_2

.vc_chk_cjk:
    ; CJK ideographs: variable number of IVS entries
    ; Conservative estimate: at least 1 for common chars
    cmp     edi, 0x4E00
    jb      .vc_chk_mongolian
    cmp     edi, 0x9FFF
    jbe     .vc_ret_1           ; simplified: at least 1

.vc_chk_mongolian:
    ; Mongolian: typically 2-4 FVS forms
    cmp     edi, 0x1820
    jb      .vc_zero
    cmp     edi, 0x1878
    jbe     .vc_ret_3           ; typical: 3 variants

.vc_zero:
    xor     eax, eax
    pop     rbp
    ret

.vc_ret_1:
    mov     eax, 1
    pop     rbp
    ret

.vc_ret_2:
    mov     eax, 2
    pop     rbp
    ret

.vc_ret_3:
    mov     eax, 3
    pop     rbp
    ret

STR_ENDFUNC str_cp_variant_count

; -----------------------------------------------------------------------------
; str_is_text_presentation
;
; Check if a codepoint is VS15 (U+FE0E) — text presentation selector.
; When placed after an emoji base character, requests text-style rendering.
;
; Signature:
;   int64_t str_is_text_presentation(uint32_t cp)
;
; Arguments:
;   EDI  — codepoint
;
; Returns:
;   RAX  = 1 if VS15 (text style), 0 otherwise
; -----------------------------------------------------------------------------

STR_FUNC str_is_text_presentation

    cmp     edi, 0xFE0E
    je      .tp_yes
    xor     eax, eax
    pop     rbp
    ret
.tp_yes:
    mov     eax, 1
    pop     rbp
    ret

STR_ENDFUNC str_is_text_presentation

; -----------------------------------------------------------------------------
; str_is_emoji_presentation_vs
;
; Check if a codepoint is VS16 (U+FE0F) — emoji presentation selector.
; When placed after an emoji base character, requests emoji-style rendering.
;
; Signature:
;   int64_t str_is_emoji_presentation_vs(uint32_t cp)
;
; Arguments:
;   EDI  — codepoint
;
; Returns:
;   RAX  = 1 if VS16 (emoji style), 0 otherwise
; -----------------------------------------------------------------------------

STR_FUNC str_is_emoji_presentation_vs

    cmp     edi, 0xFE0F
    je      .ep_yes
    xor     eax, eax
    pop     rbp
    ret
.ep_yes:
    mov     eax, 1
    pop     rbp
    ret

STR_ENDFUNC str_is_emoji_presentation_vs
