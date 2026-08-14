%ifndef GUARD_LIB_STR_ENCODING_EUC_JP_ASM
%define GUARD_LIB_STR_ENCODING_EUC_JP_ASM
; =============================================================================
; str/encoding/euc_jp.asm
; EUC-JP (Japanese) ↔ UTF-8 codec.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   encoding/engine.asm                (EncCodec struct)
;   encoding/tables/euc_jp_table.s     (generated mapping, shares JIS X 0208)
;
; -----------------------------------------------------------------------------
; EUC-JP (Extended Unix Code, Japanese) is the standard Japanese encoding on
; Unix systems.
;
; Structure:
;   - 0x00-0x7F:  ASCII
;   - 0x8E + byte (0xA1-0xDF):  half-width Katakana (2 bytes)
;   - 0x8F + 2 bytes:           JIS X 0212 (supplementary kanji, 3 bytes)
;   - lead 0xA1-0xFE + trail 0xA1-0xFE: JIS X 0208 kanji/kana (2 bytes)
;
; The JIS X 0208 plane shares the same character set as Shift-JIS but uses
; a different byte arrangement (EUC packing: each JIS byte + 0x80).
;
; Functions:
;   str_euc_jp_decode_one
;   str_euc_jp_encode_one
;   str_euc_jp_codec
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

section .rodata
_euc_jp_name: db "EUC-JP", 0

; EUC-JP maps to the same JIS X 0208 set; the table is indexed by the JIS
; row/cell derived from (lead-0xA1, trail-0xA1).
extern _eucjp_to_unicode            ; 94×94 indexed table


section .text

; -----------------------------------------------------------------------------
; str_euc_jp_decode_one
; -----------------------------------------------------------------------------

STR_FUNC str_euc_jp_decode_one

    test    rsi, rsi
    jz      .ed_empty

    movzx   eax, byte [rdi]

    cmp     al, 0x80
    jb      .ed_ascii

    ; 0x8E → half-width katakana
    cmp     al, 0x8E
    je      .ed_katakana

    ; 0x8F → JIS X 0212 (3-byte)
    cmp     al, 0x8F
    je      .ed_jisx0212

    ; lead 0xA1-0xFE → JIS X 0208
    cmp     al, 0xA1
    jb      .ed_invalid
    cmp     al, 0xFE
    ja      .ed_invalid

    cmp     rsi, 2
    jb      .ed_short

    movzx   ecx, byte [rdi + 1]     ; trail
    cmp     cl, 0xA1
    jb      .ed_invalid
    cmp     cl, 0xFE
    ja      .ed_invalid

    ; index = (lead-0xA1)*94 + (trail-0xA1)
    sub     eax, 0xA1
    imul    eax, eax, 94
    sub     ecx, 0xA1
    add     eax, ecx

    lea     r8, [rel _eucjp_to_unicode]
    movzx   eax, word [r8 + rax * 2]
    test    eax, eax
    jz      .ed_invalid

    mov     [rdx], eax
    mov     rax, 2
    pop     rbp
    ret

.ed_katakana:
    ; 0x8E + (0xA1-0xDF) → U+FF61-U+FF9F
    cmp     rsi, 2
    jb      .ed_short
    movzx   ecx, byte [rdi + 1]
    cmp     cl, 0xA1
    jb      .ed_invalid
    cmp     cl, 0xDF
    ja      .ed_invalid
    sub     ecx, 0xA1
    add     ecx, 0xFF61
    mov     [rdx], ecx
    mov     rax, 2
    pop     rbp
    ret

.ed_jisx0212:
    ; 0x8F + 2 bytes — supplementary plane (table lookup omitted in stub)
    cmp     rsi, 3
    jb      .ed_short
    ; map via _eucjp_to_unicode supplementary section (offset >= 94*94)
    ; for the stub: mark invalid until table populated
    mov     rax, STR_ERR_ENCODING
    pop     rbp
    ret

.ed_ascii:
    mov     [rdx], eax
    mov     rax, 1
    pop     rbp
    ret

.ed_invalid:
    mov     rax, STR_ERR_ENCODING
    pop     rbp
    ret

.ed_short:
    mov     rax, STR_ERR_ITER_END
    pop     rbp
    ret

.ed_empty:
    mov     rax, STR_ERR_ITER_END
    pop     rbp
    ret

STR_ENDFUNC str_euc_jp_decode_one

; -----------------------------------------------------------------------------
; str_euc_jp_encode_one
; -----------------------------------------------------------------------------

STR_FUNC str_euc_jp_encode_one

    test    rdx, rdx
    jz      .ee_nospace

    cmp     edi, 0x7F
    jbe     .ee_ascii

    ; half-width katakana U+FF61-FF9F → 0x8E + byte
    cmp     edi, 0xFF61
    jb      .ee_kanji
    cmp     edi, 0xFF9F
    ja      .ee_kanji
    cmp     rdx, 2
    jb      .ee_nospace
    mov     byte [rsi], 0x8E
    mov     eax, edi
    sub     eax, 0xFF61
    add     eax, 0xA1
    mov     [rsi + 1], al
    mov     rax, 2
    pop     rbp
    ret

.ee_kanji:
    ; binary search reverse table
    lea     r8, [rel _eucjp_from_unicode_keys]
    lea     r9, [rel _eucjp_from_unicode_vals]
    mov     r10, [rel _eucjp_from_unicode_count]
    xor     r11, r11

.ee_search:
    cmp     r11, r10
    jae     .ee_unmappable
    mov     rcx, r11
    add     rcx, r10
    shr     rcx, 1
    movzx   eax, word [r8 + rcx * 2]
    cmp     eax, edi
    je      .ee_found
    jb      .ee_right
    mov     r10, rcx
    jmp     .ee_search
.ee_right:
    lea     r11, [rcx + 1]
    jmp     .ee_search

.ee_found:
    cmp     rdx, 2
    jb      .ee_nospace
    movzx   eax, word [r9 + rcx * 2]
    mov     ecx, eax
    shr     ecx, 8
    mov     [rsi], cl
    mov     [rsi + 1], al
    mov     rax, 2
    pop     rbp
    ret

.ee_ascii:
    mov     [rsi], dil
    mov     rax, 1
    pop     rbp
    ret

.ee_unmappable:
    mov     rax, STR_ERR_ENCODING
    pop     rbp
    ret

.ee_nospace:
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_euc_jp_encode_one

; -----------------------------------------------------------------------------
; str_euc_jp_codec
; -----------------------------------------------------------------------------

section .rodata
align 8
_euc_jp_codec_struct:
    dq str_euc_jp_decode_one
    dq str_euc_jp_encode_one
    dq _euc_jp_name
    dq 3
    dq 0x02
    dq 0

section .text

STR_FUNC str_euc_jp_codec
    lea     rax, [rel _euc_jp_codec_struct]
    pop     rbp
    ret
STR_ENDFUNC str_euc_jp_codec
%endif ; GUARD_LIB_STR_ENCODING_EUC_JP_ASM
