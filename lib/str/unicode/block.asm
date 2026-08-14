%ifndef GUARD_LIB_STR_UNICODE_BLOCK_ASM
%define GUARD_LIB_STR_UNICODE_BLOCK_ASM
; =============================================================================
; str/unicode/block.asm
; Unicode block lookup (Blocks.txt).
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
; A Unicode "block" is a contiguous range of codepoints assigned to a
; script or purpose (e.g. "Basic Latin" 0x0000-0x007F, "Cyrillic"
; 0x0400-0x04FF, "Devanagari" 0x0900-0x097F).
;
; Blocks are useful for: script detection, font selection, input method
; routing, and rough language identification.
;
; Unlike categories, blocks are simple ranges — we can store them as a
; sorted range table and binary search.
;
; Functions:
;   str_cp_block          — get block ID for a codepoint
;   str_cp_block_name     — get block name string
;   str_cp_in_block       — test if codepoint is in a named block
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

; Block IDs (subset of ~300 Unicode blocks — common ones)
BLOCK_UNKNOWN           equ 0
BLOCK_BASIC_LATIN       equ 1
BLOCK_LATIN1_SUPPLEMENT equ 2
BLOCK_LATIN_EXT_A       equ 3
BLOCK_LATIN_EXT_B       equ 4
BLOCK_IPA_EXTENSIONS    equ 5
BLOCK_GREEK_COPTIC      equ 6
BLOCK_CYRILLIC          equ 7
BLOCK_ARMENIAN          equ 8
BLOCK_HEBREW            equ 9
BLOCK_ARABIC            equ 10
BLOCK_DEVANAGARI        equ 11
BLOCK_BENGALI           equ 12
BLOCK_GURMUKHI          equ 13
BLOCK_GUJARATI          equ 14
BLOCK_TAMIL             equ 15
BLOCK_THAI              equ 16
BLOCK_TIBETAN           equ 17
BLOCK_HANGUL_JAMO       equ 18
BLOCK_CJK_UNIFIED       equ 19
BLOCK_HIRAGANA          equ 20
BLOCK_KATAKANA          equ 21
BLOCK_HANGUL_SYLLABLES  equ 22
BLOCK_GENERAL_PUNCT     equ 23
BLOCK_CURRENCY_SYMBOLS  equ 24
BLOCK_ARROWS            equ 25
BLOCK_MATH_OPERATORS    equ 26
BLOCK_BOX_DRAWING       equ 27
BLOCK_EMOTICONS         equ 28
BLOCK_MISC_SYMBOLS      equ 29
BLOCK_DINGBATS          equ 30

section .rodata

; Block range table: each entry is (start, end, block_id)
; Sorted by start codepoint for binary search.
; Format: dd start, dd end, dd block_id
align 16
_block_ranges:
    dd 0x0000, 0x007F, BLOCK_BASIC_LATIN
    dd 0x0080, 0x00FF, BLOCK_LATIN1_SUPPLEMENT
    dd 0x0100, 0x017F, BLOCK_LATIN_EXT_A
    dd 0x0180, 0x024F, BLOCK_LATIN_EXT_B
    dd 0x0250, 0x02AF, BLOCK_IPA_EXTENSIONS
    dd 0x0370, 0x03FF, BLOCK_GREEK_COPTIC
    dd 0x0400, 0x04FF, BLOCK_CYRILLIC
    dd 0x0530, 0x058F, BLOCK_ARMENIAN
    dd 0x0590, 0x05FF, BLOCK_HEBREW
    dd 0x0600, 0x06FF, BLOCK_ARABIC
    dd 0x0900, 0x097F, BLOCK_DEVANAGARI
    dd 0x0980, 0x09FF, BLOCK_BENGALI
    dd 0x0A00, 0x0A7F, BLOCK_GURMUKHI
    dd 0x0A80, 0x0AFF, BLOCK_GUJARATI
    dd 0x0B80, 0x0BFF, BLOCK_TAMIL
    dd 0x0E00, 0x0E7F, BLOCK_THAI
    dd 0x0F00, 0x0FFF, BLOCK_TIBETAN
    dd 0x1100, 0x11FF, BLOCK_HANGUL_JAMO
    dd 0x2000, 0x206F, BLOCK_GENERAL_PUNCT
    dd 0x20A0, 0x20CF, BLOCK_CURRENCY_SYMBOLS
    dd 0x2190, 0x21FF, BLOCK_ARROWS
    dd 0x2200, 0x22FF, BLOCK_MATH_OPERATORS
    dd 0x2500, 0x257F, BLOCK_BOX_DRAWING
    dd 0x2600, 0x26FF, BLOCK_MISC_SYMBOLS
    dd 0x2700, 0x27BF, BLOCK_DINGBATS
    dd 0x3040, 0x309F, BLOCK_HIRAGANA
    dd 0x30A0, 0x30FF, BLOCK_KATAKANA
    dd 0x4E00, 0x9FFF, BLOCK_CJK_UNIFIED
    dd 0xAC00, 0xD7AF, BLOCK_HANGUL_SYLLABLES
    dd 0x1F600, 0x1F64F, BLOCK_EMOTICONS
_block_ranges_end:

BLOCK_RANGE_COUNT equ (_block_ranges_end - _block_ranges) / 12

; Block names (null-terminated, indexed by block ID)
_block_names:
    dq .unknown, .basic_latin, .latin1, .latin_ext_a, .latin_ext_b
    dq .ipa, .greek, .cyrillic, .armenian, .hebrew, .arabic
    dq .devanagari, .bengali, .gurmukhi, .gujarati, .tamil
    dq .thai, .tibetan, .hangul_jamo, .cjk, .hiragana, .katakana
    dq .hangul_syl, .gen_punct, .currency, .arrows, .math
    dq .box, .emoticons, .misc_sym, .dingbats

.unknown:       db "Unknown", 0
.basic_latin:   db "Basic Latin", 0
.latin1:        db "Latin-1 Supplement", 0
.latin_ext_a:   db "Latin Extended-A", 0
.latin_ext_b:   db "Latin Extended-B", 0
.ipa:           db "IPA Extensions", 0
.greek:         db "Greek and Coptic", 0
.cyrillic:      db "Cyrillic", 0
.armenian:      db "Armenian", 0
.hebrew:        db "Hebrew", 0
.arabic:        db "Arabic", 0
.devanagari:    db "Devanagari", 0
.bengali:       db "Bengali", 0
.gurmukhi:      db "Gurmukhi", 0
.gujarati:      db "Gujarati", 0
.tamil:         db "Tamil", 0
.thai:          db "Thai", 0
.tibetan:       db "Tibetan", 0
.hangul_jamo:   db "Hangul Jamo", 0
.cjk:           db "CJK Unified Ideographs", 0
.hiragana:      db "Hiragana", 0
.katakana:      db "Katakana", 0
.hangul_syl:    db "Hangul Syllables", 0
.gen_punct:     db "General Punctuation", 0
.currency:      db "Currency Symbols", 0
.arrows:        db "Arrows", 0
.math:          db "Mathematical Operators", 0
.box:           db "Box Drawing", 0
.emoticons:     db "Emoticons", 0
.misc_sym:      db "Miscellaneous Symbols", 0
.dingbats:      db "Dingbats", 0

section .text

; -----------------------------------------------------------------------------
; str_cp_block
;
; Get the block ID for a codepoint using binary search over range table.
;
; Signature:
;   uint32_t str_cp_block(uint32_t cp)
;
; Arguments: EDI = codepoint
; Returns:   EAX = block ID (BLOCK_UNKNOWN if not in any known block)
; -----------------------------------------------------------------------------

STR_FUNC str_cp_block

    lea     r8, [rel _block_ranges]
    xor     r9, r9              ; lo = 0
    mov     r10, BLOCK_RANGE_COUNT  ; hi = count

.cb_search:
    cmp     r9, r10
    jae     .cb_not_found

    ; mid = (lo + hi) / 2
    mov     r11, r9
    add     r11, r10
    shr     r11, 1

    ; entry = _block_ranges + mid*12
    mov     rax, r11
    imul    rax, rax, 12

    mov     ecx, [r8 + rax]         ; start
    mov     edx, [r8 + rax + 4]     ; end

    cmp     edi, ecx
    jb      .cb_go_left

    cmp     edi, edx
    ja      .cb_go_right

    ; found: cp in [start, end]
    mov     eax, [r8 + rax + 8]     ; block_id
    pop     rbp
    ret

.cb_go_left:
    mov     r10, r11            ; hi = mid
    jmp     .cb_search

.cb_go_right:
    lea     r9, [r11 + 1]       ; lo = mid + 1
    jmp     .cb_search

.cb_not_found:
    mov     eax, BLOCK_UNKNOWN
    pop     rbp
    ret

STR_ENDFUNC str_cp_block

; -----------------------------------------------------------------------------
; str_cp_block_name
;
; Get a pointer to the null-terminated block name for a codepoint.
;
; Signature:
;   const char *str_cp_block_name(uint32_t cp)
;
; Arguments: EDI = codepoint
; Returns:   RAX = pointer to null-terminated block name string
; -----------------------------------------------------------------------------

STR_FUNC str_cp_block_name

    call    str_cp_block        ; eax = block id

    lea     r8, [rel _block_names]
    mov     rax, [r8 + rax * 8]

    pop     rbp
    ret

STR_ENDFUNC str_cp_block_name
%endif ; GUARD_LIB_STR_UNICODE_BLOCK_ASM
