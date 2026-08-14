%ifndef GUARD_LIB_STR_DEVANAGARI_ASM
%define GUARD_LIB_STR_DEVANAGARI_ASM
; =============================================================================
; str/devanagari.asm
; Devanagari script-specific string operations.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   utf8/decode.asm   (str_utf8_decode_unchecked)
;   utf8/encode.asm   (str_utf8_encode_unchecked)
;
; -----------------------------------------------------------------------------
; Devanagari is the script used for Nepali, Hindi, Marathi, Sanskrit, and
; many other South Asian languages. It has unique text-processing needs
; that generic Unicode operations don't fully address:
;
;   1. Conjunct detection: consonant clusters joined by virama (halant)
;      form visual ligatures (e.g. क + ् + ष → क्ष). Splitting between
;      them breaks text visually.
;
;   2. Akshar (syllable) counting: the user-perceived unit in Devanagari
;      is the akshar (consonant cluster + vowel sign), not the codepoint
;      or even the grapheme cluster.
;
;   3. Virama handling: the virama (्, U+094D) is a combining mark that
;      suppresses the inherent vowel. It's invisible but critical for
;      correct conjunct formation.
;
;   4. Nepali-specific: Nepali Devanagari uses the same block as Hindi
;      (U+0900-U+097F) plus Devanagari Extended (U+A8E0-U+A8FF).
;
; Devanagari block (U+0900-U+097F) structure:
;   0900-0903  Various signs (candrabindu, anusvara, visarga)
;   0904-0914  Independent vowels (अ आ इ ई उ ऊ ऋ ए ऐ ओ औ)
;   0915-0939  Consonants (क ख ग ... ह)
;   093A-094F  Dependent vowel signs (matras) + virama
;   0950       OM (ॐ)
;   0951-0957  Various signs (stress, accents)
;   0958-095F  Additional consonants
;   0960-0963  Additional vowels
;   0964-0965  Danda (।) and double danda (॥)
;   0966-096F  Digits (०-९)
;   0970-097F  Additional signs
;
; Functions:
;   str_deva_is_consonant     — check if codepoint is a consonant
;   str_deva_is_vowel         — check if codepoint is an independent vowel
;   str_deva_is_matra         — check if codepoint is a dependent vowel sign
;   str_deva_is_virama        — check if codepoint is the halant
;   str_deva_akshar_count     — count aksharas (syllabic units)
;   str_deva_akshar_next      — find next akshar boundary
;   str_deva_has_conjunct     — check if string contains conjuncts
;   str_deva_split_conjuncts  — insert ZWJ between conjunct members
;   str_deva_to_digits        — convert ASCII digits to Devanagari digits
;   str_deva_from_digits      — convert Devanagari digits to ASCII
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"


; Devanagari codepoint ranges
DEVA_BLOCK_START    equ 0x0900
DEVA_BLOCK_END      equ 0x097F
DEVA_EXT_START      equ 0xA8E0
DEVA_EXT_END        equ 0xA8FF

; Key codepoints
DEVA_VIRAMA         equ 0x094D     ; ्  (halant)
DEVA_ANUSVARA       equ 0x0902     ; ं
DEVA_VISARGA        equ 0x0903     ; ः
DEVA_CANDRABINDU    equ 0x0901     ; ँ
DEVA_OM             equ 0x0950     ; ॐ
DEVA_DANDA          equ 0x0964     ; ।
DEVA_DOUBLE_DANDA   equ 0x0965     ; ॥

; Ranges
DEVA_VOWEL_START    equ 0x0904     ; अ
DEVA_VOWEL_END      equ 0x0914     ; औ
DEVA_CONS_START     equ 0x0915     ; क
DEVA_CONS_END       equ 0x0939     ; ह
DEVA_CONS_EXT_START equ 0x0958     ; additional consonants
DEVA_CONS_EXT_END   equ 0x095F
DEVA_MATRA_START    equ 0x093E     ; dependent vowels start (ा)
DEVA_MATRA_END      equ 0x094C     ; ौ
DEVA_DIGIT_START    equ 0x0966     ; ०
DEVA_DIGIT_END      equ 0x096F     ; ९

section .text

; -----------------------------------------------------------------------------
; str_deva_is_consonant
; Returns: RAX = 1 if codepoint is a Devanagari consonant
; -----------------------------------------------------------------------------

STR_FUNC str_deva_is_consonant

    cmp     edi, DEVA_CONS_START
    jb      .dic_ext
    cmp     edi, DEVA_CONS_END
    jbe     .dic_yes

.dic_ext:
    cmp     edi, DEVA_CONS_EXT_START
    jb      .dic_no
    cmp     edi, DEVA_CONS_EXT_END
    jbe     .dic_yes

.dic_no:
    xor     eax, eax
    pop     rbp
    ret
.dic_yes:
    mov     eax, 1
    pop     rbp
    ret

STR_ENDFUNC str_deva_is_consonant

; -----------------------------------------------------------------------------
; str_deva_is_vowel
; Returns: RAX = 1 if codepoint is an independent Devanagari vowel
; -----------------------------------------------------------------------------

STR_FUNC str_deva_is_vowel

    cmp     edi, DEVA_VOWEL_START
    jb      .div_no
    cmp     edi, DEVA_VOWEL_END
    ja      .div_no

    mov     eax, 1
    pop     rbp
    ret
.div_no:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_deva_is_vowel

; -----------------------------------------------------------------------------
; str_deva_is_matra
; Returns: RAX = 1 if codepoint is a dependent vowel sign (matra)
; -----------------------------------------------------------------------------

STR_FUNC str_deva_is_matra

    cmp     edi, DEVA_MATRA_START
    jb      .dim_no
    cmp     edi, DEVA_MATRA_END
    ja      .dim_no

    mov     eax, 1
    pop     rbp
    ret
.dim_no:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_deva_is_matra

; -----------------------------------------------------------------------------
; str_deva_is_virama
; Returns: RAX = 1 if codepoint is the virama/halant (U+094D)
; -----------------------------------------------------------------------------

STR_FUNC str_deva_is_virama

    cmp     edi, DEVA_VIRAMA
    sete    al
    movzx   eax, al
    pop     rbp
    ret

STR_ENDFUNC str_deva_is_virama

; -----------------------------------------------------------------------------
; str_deva_akshar_count
;
; Count the number of aksharas (syllabic units) in a Devanagari string.
;
; An akshar is: consonant cluster (C + virama + C + ... ) + optional matra
; or a standalone vowel or a non-Devanagari character.
;
; Rule: a new akshar starts at each:
;   - Independent vowel
;   - Consonant NOT preceded by virama
;   - Non-Devanagari character
;
; Signature:
;   int64_t str_deva_akshar_count(const StrSlice *src, uint64_t *out_count)
; -----------------------------------------------------------------------------

STR_FUNC str_deva_akshar_count

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, rbx
    add     r12, [rdi + StrSlice.len]
    mov     r13, rsi            ; out_count

    xor     r14, r14            ; akshar count
    xor     r9d, r9d            ; prev_was_virama flag

.dac_loop:
    cmp     rbx, r12
    jae     .dac_done

    sub     rsp, 16
    and     rsp, -16
    mov     rdi, rbx
    lea     rsi, [rsp]
    call    str_utf8_decode_unchecked
    mov     r8d, eax
    add     rbx, [rsp]
    mov     rsp, rbp

    ; is this a virama?
    cmp     r8d, DEVA_VIRAMA
    je      .dac_virama

    ; is this a matra?
    cmp     r8d, DEVA_MATRA_START
    jb      .dac_check_sign
    cmp     r8d, DEVA_MATRA_END
    jbe     .dac_matra

.dac_check_sign:
    ; anusvara, visarga, candrabindu — part of current akshar
    cmp     r8d, DEVA_ANUSVARA
    je      .dac_continue
    cmp     r8d, DEVA_VISARGA
    je      .dac_continue
    cmp     r8d, DEVA_CANDRABINDU
    je      .dac_continue

    ; is this a consonant?
    mov     edi, r8d
    push    r8
    push    r9
    call    str_deva_is_consonant
    pop     r9
    pop     r8
    test    eax, eax
    jnz     .dac_consonant

    ; is this a vowel?
    mov     edi, r8d
    push    r8
    push    r9
    call    str_deva_is_vowel
    pop     r9
    pop     r8
    test    eax, eax
    jnz     .dac_new_akshar

    ; non-Devanagari or other char: new akshar
    jmp     .dac_new_akshar

.dac_consonant:
    ; consonant after virama → conjunct continuation (same akshar)
    test    r9d, r9d
    jnz     .dac_continue       ; virama + consonant = same akshar

    ; consonant not after virama → new akshar
    jmp     .dac_new_akshar

.dac_virama:
    mov     r9d, 1
    jmp     .dac_loop

.dac_matra:
    ; matra is part of current akshar
    jmp     .dac_continue

.dac_new_akshar:
    inc     r14
    xor     r9d, r9d
    jmp     .dac_loop

.dac_continue:
    xor     r9d, r9d
    jmp     .dac_loop

.dac_done:
    mov     [r13], r14
    pop_regs r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_deva_akshar_count

; -----------------------------------------------------------------------------
; str_deva_to_digits
;
; Convert ASCII digits 0-9 to Devanagari digits ०-९ in a UTF-8 string.
;
; Signature:
;   int64_t str_deva_to_digits(const StrSlice *src, uint8_t *dst,
;                               uint64_t dst_cap, uint64_t *out_len)
; -----------------------------------------------------------------------------

STR_FUNC str_deva_to_digits

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, rbx
    add     r12, [rdi + StrSlice.len]
    mov     r13, rsi
    mov     r14, rdx
    mov     r15, rcx

    xor     r9, r9              ; dst offset

.dtd_loop:
    cmp     rbx, r12
    jae     .dtd_done

    sub     rsp, 16
    and     rsp, -16
    mov     rdi, rbx
    lea     rsi, [rsp]
    call    str_utf8_decode_unchecked
    mov     r8d, eax
    add     rbx, [rsp]
    mov     rsp, rbp

    ; if ASCII digit 0-9: convert to Devanagari
    cmp     r8d, '0'
    jb      .dtd_passthrough
    cmp     r8d, '9'
    ja      .dtd_passthrough

    ; Devanagari digit = ASCII digit - '0' + 0x0966
    sub     r8d, '0'
    add     r8d, DEVA_DIGIT_START

.dtd_passthrough:
    ; encode codepoint to dst
    lea     rax, [r9 + 4]
    cmp     rax, r14
    ja      .dtd_overflow

    mov     edi, r8d
    lea     rsi, [r13 + r9]
    call    str_utf8_encode_unchecked
    add     r9, rax
    jmp     .dtd_loop

.dtd_done:
    test    r15, r15
    jz      .dtd_ok
    mov     [r15], r9

.dtd_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.dtd_overflow:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_deva_to_digits

; -----------------------------------------------------------------------------
; str_deva_from_digits
;
; Convert Devanagari digits ०-९ to ASCII digits 0-9.
;
; Signature:
;   int64_t str_deva_from_digits(const StrSlice *src, uint8_t *dst,
;                                 uint64_t dst_cap, uint64_t *out_len)
; -----------------------------------------------------------------------------

STR_FUNC str_deva_from_digits

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, rbx
    add     r12, [rdi + StrSlice.len]
    mov     r13, rsi
    mov     r14, rdx
    mov     r15, rcx

    xor     r9, r9

.dfd_loop:
    cmp     rbx, r12
    jae     .dfd_done

    sub     rsp, 16
    and     rsp, -16
    mov     rdi, rbx
    lea     rsi, [rsp]
    call    str_utf8_decode_unchecked
    mov     r8d, eax
    add     rbx, [rsp]
    mov     rsp, rbp

    ; if Devanagari digit: convert to ASCII
    cmp     r8d, DEVA_DIGIT_START
    jb      .dfd_passthrough
    cmp     r8d, DEVA_DIGIT_END
    ja      .dfd_passthrough

    sub     r8d, DEVA_DIGIT_START
    add     r8d, '0'

.dfd_passthrough:
    lea     rax, [r9 + 4]
    cmp     rax, r14
    ja      .dfd_overflow

    mov     edi, r8d
    lea     rsi, [r13 + r9]
    call    str_utf8_encode_unchecked
    add     r9, rax
    jmp     .dfd_loop

.dfd_done:
    test    r15, r15
    jz      .dfd_ok
    mov     [r15], r9

.dfd_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.dfd_overflow:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_deva_from_digits
%endif ; GUARD_LIB_STR_DEVANAGARI_ASM
