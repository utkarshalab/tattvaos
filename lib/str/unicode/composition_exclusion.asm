; =============================================================================
; str/unicode/composition_exclusion.asm
; Composition exclusion checks (CompositionExclusions.txt).
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Source: CompositionExclusions.txt, DerivedNormalizationProps.txt
;
; -----------------------------------------------------------------------------
; During NFC (Canonical Composition), certain codepoints must NOT be composed
; even though they have a canonical decomposition. These are the "composition
; exclusions" defined in UAX #15.
;
; Three categories of exclusions:
;
; 1. Script-specific exclusions (from CompositionExclusions.txt):
;    Codepoints explicitly listed — mostly precomposed Hebrew, Tibetan,
;    and other script-specific characters that should not recompose.
;    Examples: U+0958 DEVANAGARI LETTER QA (= 0915 + 093C)
;              U+0F43 TIBETAN LETTER GHA (= 0F42 + 0FB7)
;
; 2. Post-composition version exclusions:
;    Characters added after a Unicode version that would break stability.
;    These have canonical decomposition but were excluded to maintain
;    normalization stability across Unicode versions.
;
; 3. Singleton decompositions (derived):
;    Characters that decompose to a single codepoint. These are excluded
;    because composing back would lose the distinction.
;    Examples: U+2126 OHM SIGN → U+03A9 GREEK CAPITAL LETTER OMEGA
;              U+212B ANGSTROM SIGN → U+00C5 LATIN CAPITAL LETTER A WITH RING
;
; 4. Non-starter decompositions (derived):
;    Characters whose decomposition begins with a non-starter (CCC != 0).
;    Composing these would violate canonical ordering constraints.
;
; The NFC algorithm must check: if a (starter, combining) pair has a
; canonical composition AND the composed result is NOT in the exclusion list,
; then compose. Otherwise, leave decomposed.
;
; Functions:
;   str_cp_is_composition_exclusion      — check if excluded from composition
;   str_cp_is_full_composition_exclusion — includes singletons + non-starters
;   str_cp_is_singleton_decomp           — decomposition is a single codepoint
;   str_cp_is_nonstarter_decomp          — decomposition starts with CCC != 0
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_cp_ccc
extern _ucd_decomp_index

section .text

; -----------------------------------------------------------------------------
; str_cp_is_composition_exclusion
;
; Check if a codepoint is excluded from canonical composition (NFC).
; This is the full exclusion list from CompositionExclusions.txt.
;
; Signature:
;   int64_t str_cp_is_composition_exclusion(uint32_t cp)
;
; Arguments:
;   EDI  — codepoint
;
; Returns:
;   RAX  = 1 if excluded, 0 if not excluded
; -----------------------------------------------------------------------------

STR_FUNC str_cp_is_composition_exclusion

    ; ---- Script-specific exclusions (CompositionExclusions.txt) ----

    ; Devanagari (9 entries)
    cmp     edi, 0x0958
    je      .ce_yes
    cmp     edi, 0x0959
    je      .ce_yes
    cmp     edi, 0x095A
    je      .ce_yes
    cmp     edi, 0x095B
    je      .ce_yes
    cmp     edi, 0x095C
    je      .ce_yes
    cmp     edi, 0x095D
    je      .ce_yes
    cmp     edi, 0x095E
    je      .ce_yes
    cmp     edi, 0x095F
    je      .ce_yes

    ; Bengali
    cmp     edi, 0x09DC
    je      .ce_yes
    cmp     edi, 0x09DD
    je      .ce_yes
    cmp     edi, 0x09DF
    je      .ce_yes

    ; Gurmukhi
    cmp     edi, 0x0A33
    je      .ce_yes
    cmp     edi, 0x0A36
    je      .ce_yes
    cmp     edi, 0x0A59
    je      .ce_yes
    cmp     edi, 0x0A5A
    je      .ce_yes
    cmp     edi, 0x0A5B
    je      .ce_yes
    cmp     edi, 0x0A5E
    je      .ce_yes

    ; Oriya
    cmp     edi, 0x0B5C
    je      .ce_yes
    cmp     edi, 0x0B5D
    je      .ce_yes

    ; Tibetan
    cmp     edi, 0x0F43
    je      .ce_yes
    cmp     edi, 0x0F4D
    je      .ce_yes
    cmp     edi, 0x0F52
    je      .ce_yes
    cmp     edi, 0x0F57
    je      .ce_yes
    cmp     edi, 0x0F5C
    je      .ce_yes
    cmp     edi, 0x0F69
    je      .ce_yes
    cmp     edi, 0x0F76
    je      .ce_yes
    cmp     edi, 0x0F78
    je      .ce_yes
    cmp     edi, 0x0F93
    je      .ce_yes
    cmp     edi, 0x0F9D
    je      .ce_yes
    cmp     edi, 0x0FA2
    je      .ce_yes
    cmp     edi, 0x0FA7
    je      .ce_yes
    cmp     edi, 0x0FAC
    je      .ce_yes
    cmp     edi, 0x0FB9
    je      .ce_yes

    ; ---- Post-composition version exclusions ----

    ; Hebrew
    cmp     edi, 0xFB1D
    je      .ce_yes
    cmp     edi, 0xFB1F
    je      .ce_yes
    cmp     edi, 0xFB2A
    jb      .ce_chk_fb2f
    cmp     edi, 0xFB36
    jbe     .ce_yes
.ce_chk_fb2f:
    cmp     edi, 0xFB38
    jb      .ce_chk_fb40
    cmp     edi, 0xFB3C
    jbe     .ce_yes
.ce_chk_fb40:
    cmp     edi, 0xFB3E
    je      .ce_yes
    cmp     edi, 0xFB40
    je      .ce_yes
    cmp     edi, 0xFB41
    je      .ce_yes
    cmp     edi, 0xFB43
    je      .ce_yes
    cmp     edi, 0xFB44
    je      .ce_yes
    cmp     edi, 0xFB46
    jb      .ce_chk_fb4e
    cmp     edi, 0xFB4E
    jbe     .ce_yes
.ce_chk_fb4e:

    ; Arabic presentation forms (post-composition)
    cmp     edi, 0x2ADC
    je      .ce_yes             ; FORKING

    ; ---- Singleton decompositions ----
    ; Characters that decompose to exactly one codepoint

    cmp     edi, 0x2126
    je      .ce_yes             ; OHM SIGN → Ω
    cmp     edi, 0x212A
    je      .ce_yes             ; KELVIN SIGN → K
    cmp     edi, 0x212B
    je      .ce_yes             ; ANGSTROM SIGN → Å

    ; CJK Compatibility Ideographs (F900-FA0D range with singleton decomps)
    cmp     edi, 0xF900
    jb      .ce_chk_more_singletons
    cmp     edi, 0xFA0D
    jbe     .ce_yes             ; most CJK compat ideographs
    cmp     edi, 0xFA10
    je      .ce_yes
    cmp     edi, 0xFA12
    je      .ce_yes
    cmp     edi, 0xFA15
    jb      .ce_chk_fa20
    cmp     edi, 0xFA1E
    jbe     .ce_yes
.ce_chk_fa20:
    cmp     edi, 0xFA20
    je      .ce_yes
    cmp     edi, 0xFA22
    je      .ce_yes
    cmp     edi, 0xFA25
    je      .ce_yes
    cmp     edi, 0xFA26
    je      .ce_yes
    cmp     edi, 0xFA2A
    jb      .ce_chk_more_singletons
    cmp     edi, 0xFA6D
    jbe     .ce_yes
    cmp     edi, 0xFA70
    jb      .ce_chk_more_singletons
    cmp     edi, 0xFAD9
    jbe     .ce_yes

.ce_chk_more_singletons:
    ; SMP CJK Compatibility Ideographs Supplement: U+2F800-U+2FA1D
    cmp     edi, 0x2F800
    jb      .ce_no
    cmp     edi, 0x2FA1D
    jbe     .ce_yes

.ce_no:
    xor     eax, eax
    pop     rbp
    ret

.ce_yes:
    mov     eax, 1
    pop     rbp
    ret

STR_ENDFUNC str_cp_is_composition_exclusion

; -----------------------------------------------------------------------------
; str_cp_is_full_composition_exclusion
;
; Full exclusion: CompositionExclusions + singletons + non-starters.
; This is what the NFC algorithm actually needs to check.
;
; Signature:
;   int64_t str_cp_is_full_composition_exclusion(uint32_t cp)
;
; Arguments:
;   EDI  — codepoint
;
; Returns:
;   RAX  = 1 if fully excluded, 0 otherwise
; -----------------------------------------------------------------------------

STR_FUNC str_cp_is_full_composition_exclusion

    push_regs rbx

    mov     ebx, edi

    ; first check the explicit list
    call    str_cp_is_composition_exclusion
    test    eax, eax
    jnz     .fce_yes

    ; then check singleton decompositions
    mov     edi, ebx
    call    str_cp_is_singleton_decomp
    test    eax, eax
    jnz     .fce_yes

    ; then check non-starter decompositions
    mov     edi, ebx
    call    str_cp_is_nonstarter_decomp
    test    eax, eax
    jnz     .fce_yes

    pop_regs rbx
    xor     eax, eax
    pop     rbp
    ret

.fce_yes:
    pop_regs rbx
    mov     eax, 1
    pop     rbp
    ret

STR_ENDFUNC str_cp_is_full_composition_exclusion

; -----------------------------------------------------------------------------
; str_cp_is_singleton_decomp
;
; Check if a codepoint decomposes to exactly one codepoint (singleton).
; Singletons are excluded from composition because composing back would
; lose the original codepoint identity.
;
; Signature:
;   int64_t str_cp_is_singleton_decomp(uint32_t cp)
;
; Arguments:
;   EDI  — codepoint
;
; Returns:
;   RAX  = 1 if singleton decomposition, 0 otherwise
; -----------------------------------------------------------------------------

STR_FUNC str_cp_is_singleton_decomp

    cmp     edi, CODEPOINT_MAX
    ja      .sd_no

    ; well-known singletons
    cmp     edi, 0x2126
    je      .sd_yes             ; OHM SIGN
    cmp     edi, 0x212A
    je      .sd_yes             ; KELVIN SIGN
    cmp     edi, 0x212B
    je      .sd_yes             ; ANGSTROM SIGN

    ; CJK Compatibility Ideographs: U+F900-U+FAD9 (most are singletons)
    cmp     edi, 0xF900
    jb      .sd_chk_smp
    cmp     edi, 0xFAD9
    jbe     .sd_yes

.sd_chk_smp:
    ; CJK Compat Ideographs Supplement: U+2F800-U+2FA1D
    cmp     edi, 0x2F800
    jb      .sd_chk_table
    cmp     edi, 0x2FA1D
    jbe     .sd_yes

.sd_chk_table:
    ; generic check via table: length == 1 and type == canonical
    cmp     edi, 0x10000
    jae     .sd_no

    lea     rax, [rel _ucd_decomp_index]
    mov     eax, [rax + rdi * 4]

    mov     ecx, eax
    and     ecx, 0x0F
    cmp     ecx, 1              ; DECOMP_CANONICAL
    jne     .sd_no

    shr     eax, 4
    and     eax, 0x0F
    cmp     eax, 1              ; length == 1 → singleton
    jne     .sd_no

.sd_yes:
    mov     eax, 1
    pop     rbp
    ret

.sd_no:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_cp_is_singleton_decomp

; -----------------------------------------------------------------------------
; str_cp_is_nonstarter_decomp
;
; Check if a codepoint's canonical decomposition starts with a non-starter
; (a character with Canonical_Combining_Class != 0).
; Such codepoints are excluded from composition.
;
; Examples:
;   U+0344 COMBINING GREEK DIALYTIKA TONOS (decomposes to 0308 + 0301,
;   both are non-starters — CCC=230 and CCC=230)
;
; Signature:
;   int64_t str_cp_is_nonstarter_decomp(uint32_t cp)
;
; Arguments:
;   EDI  — codepoint
;
; Returns:
;   RAX  = 1 if decomposition starts with non-starter, 0 otherwise
; -----------------------------------------------------------------------------

STR_FUNC str_cp_is_nonstarter_decomp

    cmp     edi, CODEPOINT_MAX
    ja      .nsd_no

    ; Skip BMP codepoints without decomposition
    cmp     edi, 0x10000
    jae     .nsd_no             ; SMP: simplified — assume no non-starter decomps

    push_regs rbx, r12

    mov     ebx, edi

    ; get decomposition from table
    lea     rax, [rel _ucd_decomp_index]
    mov     eax, [rax + rbx * 4]

    ; check if has canonical decomposition
    mov     ecx, eax
    and     ecx, 0x0F
    cmp     ecx, 1              ; DECOMP_CANONICAL
    jne     .nsd_no_pop

    ; get offset to first decomposed codepoint
    mov     r12d, eax
    shr     r12d, 8             ; offset

    lea     rax, [rel _ucd_decomp_data]
    mov     edi, [rax + r12 * 4] ; first codepoint of decomposition

    ; check CCC of that first codepoint
    call    str_cp_ccc
    movzx   eax, al

    test    eax, eax
    jz      .nsd_no_pop         ; CCC == 0 → starter → not excluded

    pop_regs r12, rbx
    mov     eax, 1
    pop     rbp
    ret

.nsd_no_pop:
    pop_regs r12, rbx
.nsd_no:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_cp_is_nonstarter_decomp
