; =============================================================================
; str/unicode/special_case.asm
; Locale-aware special casing (SpecialCasing.txt).
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
; Source: SpecialCasing.txt
;
; -----------------------------------------------------------------------------
; Special casing handles characters whose case mapping depends on context
; or locale. The standard cases:
;
;   ß (U+00DF) uppercase → "SS" (1:2 mapping)
;   ﬁ (U+FB01) uppercase → "FI"
;   ΐ (U+0390) uppercase → "Ϊ́" (3 codepoints)
;
; Locale-specific:
;   Turkish:  i (U+0069) uppercase → İ (U+0130), not I
;             I (U+0049) lowercase → ı (U+0131), not i
;             İ (U+0130) lowercase → i
;             ı (U+0131) uppercase → I
;
;   Lithuanian: certain accented letters get dot above when lowercased
;
; Functions:
;   str_special_upper     — uppercase with special/context rules
;   str_special_lower     — lowercase with special/context rules
;   str_special_title     — titlecase with special rules
;   str_locale_upper      — locale-specific uppercase
;   str_locale_lower      — locale-specific lowercase
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_utf8_encode_unchecked
extern str_utf8_decode_unchecked

; Locale IDs
LOCALE_DEFAULT  equ 0
LOCALE_TR       equ 1       ; Turkish
LOCALE_AZ       equ 2       ; Azerbaijani (same as Turkish for casing)
LOCALE_LT       equ 3       ; Lithuanian

section .text

; -----------------------------------------------------------------------------
; str_special_upper
;
; Uppercase a codepoint with special 1:N mappings.
; Writes up to 3 codepoints to the output buffer.
;
; Signature:
;   int64_t str_special_upper(uint32_t cp, uint32_t *out,
;                              uint64_t *out_count)
; -----------------------------------------------------------------------------

STR_FUNC str_special_upper

    guard_null rsi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    ; ß → SS
    cmp     edi, 0x00DF
    je      .su_eszett

    ; ﬁ → FI
    cmp     edi, 0xFB01
    je      .su_fi

    ; ﬂ → FL
    cmp     edi, 0xFB02
    je      .su_fl

    ; ﬀ → FF
    cmp     edi, 0xFB00
    je      .su_ff

    ; ﬃ → FFI
    cmp     edi, 0xFB03
    je      .su_ffi

    ; ﬄ → FFL
    cmp     edi, 0xFB04
    je      .su_ffl

    ; ﬅ → ST
    cmp     edi, 0xFB05
    je      .su_st

    ; regular ASCII lowercase → uppercase
    cmp     edi, 'a'
    jb      .su_identity
    cmp     edi, 'z'
    ja      .su_chk_latin1
    mov     eax, edi
    sub     eax, 32
    mov     [rsi], eax
    mov     qword [rdx], 1
    xor     eax, eax
    pop     rbp
    ret

.su_chk_latin1:
    ; Latin-1 lowercase: 0xE0-0xFE (except 0xF7) → subtract 32
    cmp     edi, 0xE0
    jb      .su_identity
    cmp     edi, 0xFE
    ja      .su_identity
    cmp     edi, 0xF7
    je      .su_identity
    mov     eax, edi
    sub     eax, 32
    mov     [rsi], eax
    mov     qword [rdx], 1
    xor     eax, eax
    pop     rbp
    ret

.su_identity:
    mov     [rsi], edi
    mov     qword [rdx], 1
    xor     eax, eax
    pop     rbp
    ret

.su_eszett:
    mov     dword [rsi], 'S'
    mov     dword [rsi + 4], 'S'
    mov     qword [rdx], 2
    xor     eax, eax
    pop     rbp
    ret

.su_fi:
    mov     dword [rsi], 'F'
    mov     dword [rsi + 4], 'I'
    mov     qword [rdx], 2
    xor     eax, eax
    pop     rbp
    ret

.su_fl:
    mov     dword [rsi], 'F'
    mov     dword [rsi + 4], 'L'
    mov     qword [rdx], 2
    xor     eax, eax
    pop     rbp
    ret

.su_ff:
    mov     dword [rsi], 'F'
    mov     dword [rsi + 4], 'F'
    mov     qword [rdx], 2
    xor     eax, eax
    pop     rbp
    ret

.su_ffi:
    mov     dword [rsi], 'F'
    mov     dword [rsi + 4], 'F'
    mov     dword [rsi + 8], 'I'
    mov     qword [rdx], 3
    xor     eax, eax
    pop     rbp
    ret

.su_ffl:
    mov     dword [rsi], 'F'
    mov     dword [rsi + 4], 'F'
    mov     dword [rsi + 8], 'L'
    mov     qword [rdx], 3
    xor     eax, eax
    pop     rbp
    ret

.su_st:
    mov     dword [rsi], 'S'
    mov     dword [rsi + 4], 'T'
    mov     qword [rdx], 2
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_special_upper

; -----------------------------------------------------------------------------
; str_locale_upper / str_locale_lower
;
; Locale-specific casing. Currently supports Turkish/Azerbaijani.
;
; Signature:
;   uint32_t str_locale_upper(uint32_t cp, uint8_t locale)
;   uint32_t str_locale_lower(uint32_t cp, uint8_t locale)
; -----------------------------------------------------------------------------

STR_FUNC str_locale_upper

    cmp     sil, LOCALE_TR
    je      .lu_turkish
    cmp     sil, LOCALE_AZ
    je      .lu_turkish

    ; default: simple uppercase
    mov     eax, edi
    cmp     eax, 'a'
    jb      .lu_ret
    cmp     eax, 'z'
    ja      .lu_ret
    sub     eax, 32
.lu_ret:
    pop     rbp
    ret

.lu_turkish:
    ; Turkish: i → İ (U+0130), not I
    cmp     edi, 'i'
    je      .lu_tr_i
    ; ı (U+0131) → I
    cmp     edi, 0x0131
    je      .lu_tr_dotless

    mov     eax, edi
    cmp     eax, 'a'
    jb      .lu_ret
    cmp     eax, 'z'
    ja      .lu_ret
    sub     eax, 32
    pop     rbp
    ret

.lu_tr_i:
    mov     eax, 0x0130         ; İ
    pop     rbp
    ret
.lu_tr_dotless:
    mov     eax, 'I'
    pop     rbp
    ret

STR_ENDFUNC str_locale_upper

STR_FUNC str_locale_lower

    cmp     sil, LOCALE_TR
    je      .ll_turkish
    cmp     sil, LOCALE_AZ
    je      .ll_turkish

    mov     eax, edi
    cmp     eax, 'A'
    jb      .ll_ret
    cmp     eax, 'Z'
    ja      .ll_ret
    add     eax, 32
.ll_ret:
    pop     rbp
    ret

.ll_turkish:
    ; Turkish: I → ı (U+0131), not i
    cmp     edi, 'I'
    je      .ll_tr_I
    ; İ (U+0130) → i
    cmp     edi, 0x0130
    je      .ll_tr_dotted

    mov     eax, edi
    cmp     eax, 'A'
    jb      .ll_ret
    cmp     eax, 'Z'
    ja      .ll_ret
    add     eax, 32
    pop     rbp
    ret

.ll_tr_I:
    mov     eax, 0x0131         ; ı
    pop     rbp
    ret
.ll_tr_dotted:
    mov     eax, 'i'
    pop     rbp
    ret

STR_ENDFUNC str_locale_lower