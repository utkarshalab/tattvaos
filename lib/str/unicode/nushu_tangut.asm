%ifndef GUARD_LIB_STR_UNICODE_NUSHU_TANGUT_ASM
%define GUARD_LIB_STR_UNICODE_NUSHU_TANGUT_ASM
; =============================================================================
; str/unicode/nushu_tangut.asm
; Nushu and Tangut script support (NushuSources.txt, TangutSources.txt).
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Source: NushuSources.txt, TangutSources.txt
;
; -----------------------------------------------------------------------------
; Nushu (女書 "women's writing"):
;   A syllabic script historically used exclusively by women in Jiangyong
;   County, Hunan, China. One of the world's only gender-specific writing
;   systems. Encoded in Unicode 10.0 (2017).
;
;   Block: U+1B170..U+1B2FB (Nushu, 396 characters)
;   Nushu Radical-Stroke data provides radical + stroke count for each char.
;
; Tangut (西夏文 "Western Xia writing"):
;   A logographic script used by the Western Xia dynasty (1038-1227 CE)
;   in what is now northwestern China. Contains ~6000 characters.
;   Encoded in Unicode 9.0 (2016).
;
;   Blocks:
;     U+17000..U+187FF  — Tangut (main block, 6136 characters)
;     U+18800..U+18AFF  — Tangut Components (768 characters)
;     U+18D00..U+18D7F  — Tangut Supplement (9 characters)
;
;   Tangut radical-stroke data maps each character to its radical and
;   remaining stroke count, similar to CJK ideographs.
;
; Functions:
;   str_cp_is_nushu              — is this a Nushu codepoint?
;   str_cp_is_tangut             — is this a Tangut codepoint?
;   str_cp_is_tangut_component   — is this a Tangut component?
;   str_cp_nushu_radical         — get Nushu radical index
;   str_cp_nushu_strokes         — get Nushu remaining stroke count
;   str_cp_tangut_radical        — get Tangut radical index
;   str_cp_tangut_strokes        — get Tangut remaining stroke count
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

section .text

; -----------------------------------------------------------------------------
; str_cp_is_nushu
;
; Check if a codepoint is a Nushu character.
;
; Signature:
;   int64_t str_cp_is_nushu(uint32_t cp)
;
; Arguments:
;   EDI  — codepoint
;
; Returns:
;   RAX  = 1 if Nushu, 0 otherwise
; -----------------------------------------------------------------------------

STR_FUNC str_cp_is_nushu

    cmp     edi, 0x1B170
    jb      .nu_no
    cmp     edi, 0x1B2FB
    jbe     .nu_yes

.nu_no:
    xor     eax, eax
    pop     rbp
    ret

.nu_yes:
    mov     eax, 1
    pop     rbp
    ret

STR_ENDFUNC str_cp_is_nushu

; -----------------------------------------------------------------------------
; str_cp_is_tangut
;
; Check if a codepoint is a Tangut character (main block or supplement).
;
; Signature:
;   int64_t str_cp_is_tangut(uint32_t cp)
;
; Arguments:
;   EDI  — codepoint
;
; Returns:
;   RAX  = 1 if Tangut, 0 otherwise
; -----------------------------------------------------------------------------

STR_FUNC str_cp_is_tangut

    ; main block: U+17000-U+187FF
    cmp     edi, 0x17000
    jb      .tg_chk_supp
    cmp     edi, 0x187FF
    jbe     .tg_yes

.tg_chk_supp:
    ; supplement: U+18D00-U+18D7F
    cmp     edi, 0x18D00
    jb      .tg_no
    cmp     edi, 0x18D7F
    jbe     .tg_yes

.tg_no:
    xor     eax, eax
    pop     rbp
    ret

.tg_yes:
    mov     eax, 1
    pop     rbp
    ret

STR_ENDFUNC str_cp_is_tangut

; -----------------------------------------------------------------------------
; str_cp_is_tangut_component
;
; Check if a codepoint is a Tangut component (used for decomposition).
;
; Signature:
;   int64_t str_cp_is_tangut_component(uint32_t cp)
;
; Arguments:
;   EDI  — codepoint
;
; Returns:
;   RAX  = 1 if Tangut component, 0 otherwise
; -----------------------------------------------------------------------------

STR_FUNC str_cp_is_tangut_component

    ; Tangut Components: U+18800-U+18AFF
    cmp     edi, 0x18800
    jb      .tc_no
    cmp     edi, 0x18AFF
    jbe     .tc_yes

.tc_no:
    xor     eax, eax
    pop     rbp
    ret

.tc_yes:
    mov     eax, 1
    pop     rbp
    ret

STR_ENDFUNC str_cp_is_tangut_component

; -----------------------------------------------------------------------------
; str_cp_nushu_radical
;
; Get the radical index for a Nushu character.
; Nushu has a radical-stroke system similar to CJK ideographs.
;
; Signature:
;   int64_t str_cp_nushu_radical(uint32_t cp, uint8_t *out_radical)
;
; Arguments:
;   EDI  — codepoint
;   RSI  — pointer to receive radical index (0-based)
;
; Returns:
;   RAX  = STR_OK if found
;   RAX  = STR_ERR_INVALID_ARG if not a Nushu character
; -----------------------------------------------------------------------------

STR_FUNC str_cp_nushu_radical

    guard_null rsi, STR_ERR_NULL

    ; validate range
    cmp     edi, 0x1B170
    jb      .nr_invalid
    cmp     edi, 0x1B2FB
    ja      .nr_invalid

    ; look up radical from table
    ; For full implementation, this uses a generated table from NushuSources.txt.
    ; The table maps (cp - 0x1B170) → radical index.

    ; Simplified: compute index and look up
    mov     eax, edi
    sub     eax, 0x1B170        ; character index (0-based)

    ; stub: would index into _nushu_radical_table[idx]
    ; For now, return a placeholder radical based on position
    ; Real table would be: movzx ecx, byte [rel _nushu_radical_table + rax]
    xor     ecx, ecx            ; placeholder

    mov     [rsi], cl

    xor     eax, eax            ; STR_OK
    pop     rbp
    ret

.nr_invalid:
    mov     rax, STR_ERR_INVALID_ARG
    pop     rbp
    ret

STR_ENDFUNC str_cp_nushu_radical

; -----------------------------------------------------------------------------
; str_cp_nushu_strokes
;
; Get the remaining stroke count for a Nushu character.
;
; Signature:
;   int64_t str_cp_nushu_strokes(uint32_t cp, uint8_t *out_strokes)
;
; Arguments:
;   EDI  — codepoint
;   RSI  — pointer to receive stroke count
;
; Returns:
;   RAX  = STR_OK or STR_ERR_INVALID_ARG
; -----------------------------------------------------------------------------

STR_FUNC str_cp_nushu_strokes

    guard_null rsi, STR_ERR_NULL

    cmp     edi, 0x1B170
    jb      .ns_invalid
    cmp     edi, 0x1B2FB
    ja      .ns_invalid

    mov     eax, edi
    sub     eax, 0x1B170

    ; stub: _nushu_stroke_table[idx]
    xor     ecx, ecx            ; placeholder
    mov     [rsi], cl

    xor     eax, eax
    pop     rbp
    ret

.ns_invalid:
    mov     rax, STR_ERR_INVALID_ARG
    pop     rbp
    ret

STR_ENDFUNC str_cp_nushu_strokes

; -----------------------------------------------------------------------------
; str_cp_tangut_radical
;
; Get the radical index for a Tangut character.
;
; Signature:
;   int64_t str_cp_tangut_radical(uint32_t cp, uint16_t *out_radical)
;
; Arguments:
;   EDI  — codepoint
;   RSI  — pointer to receive radical index (0-based, 16-bit for Tangut's
;          large radical set)
;
; Returns:
;   RAX  = STR_OK or STR_ERR_INVALID_ARG
; -----------------------------------------------------------------------------

STR_FUNC str_cp_tangut_radical

    guard_null rsi, STR_ERR_NULL

    ; validate: must be in Tangut main block or supplement
    cmp     edi, 0x17000
    jb      .tr_invalid
    cmp     edi, 0x187FF
    jbe     .tr_main

    cmp     edi, 0x18D00
    jb      .tr_invalid
    cmp     edi, 0x18D7F
    jbe     .tr_supp

    jmp     .tr_invalid

.tr_main:
    mov     eax, edi
    sub     eax, 0x17000
    jmp     .tr_lookup

.tr_supp:
    mov     eax, edi
    sub     eax, 0x18D00
    add     eax, 0x87FF         ; offset past main block
    ; fall through

.tr_lookup:
    ; stub: _tangut_radical_table[idx] (16-bit entries)
    ; Real table from TangutSources.txt
    xor     ecx, ecx            ; placeholder
    mov     [rsi], cx

    xor     eax, eax
    pop     rbp
    ret

.tr_invalid:
    mov     rax, STR_ERR_INVALID_ARG
    pop     rbp
    ret

STR_ENDFUNC str_cp_tangut_radical

; -----------------------------------------------------------------------------
; str_cp_tangut_strokes
;
; Get the remaining stroke count for a Tangut character.
;
; Signature:
;   int64_t str_cp_tangut_strokes(uint32_t cp, uint8_t *out_strokes)
;
; Arguments:
;   EDI  — codepoint
;   RSI  — pointer to receive stroke count
;
; Returns:
;   RAX  = STR_OK or STR_ERR_INVALID_ARG
; -----------------------------------------------------------------------------

STR_FUNC str_cp_tangut_strokes

    guard_null rsi, STR_ERR_NULL

    cmp     edi, 0x17000
    jb      .ts_invalid
    cmp     edi, 0x187FF
    jbe     .ts_main

    cmp     edi, 0x18D00
    jb      .ts_invalid
    cmp     edi, 0x18D7F
    jbe     .ts_supp

    jmp     .ts_invalid

.ts_main:
    mov     eax, edi
    sub     eax, 0x17000
    jmp     .ts_lookup

.ts_supp:
    mov     eax, edi
    sub     eax, 0x18D00
    add     eax, 0x87FF

.ts_lookup:
    ; stub: _tangut_stroke_table[idx]
    xor     ecx, ecx
    mov     [rsi], cl

    xor     eax, eax
    pop     rbp
    ret

.ts_invalid:
    mov     rax, STR_ERR_INVALID_ARG
    pop     rbp
    ret

STR_ENDFUNC str_cp_tangut_strokes

%endif ; GUARD_LIB_STR_UNICODE_NUSHU_TANGUT_ASM
