%ifndef GUARD_LIB_STR_UNICODE_CASING_TAILORING_ASM
%define GUARD_LIB_STR_UNICODE_CASING_TAILORING_ASM
; =============================================================================
; str/unicode/casing_tailoring.asm
; Locale-tailored string case conversions (Dutch, Turkish, German, Lithuanian).
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"





LOCALE_DEFAULT  equ 0
LOCALE_TR       equ 1       ; Turkish / Azerbaijani
LOCALE_NL       equ 2       ; Dutch
LOCALE_LT       equ 3       ; Lithuanian
LOCALE_DE       equ 4       ; German

section .text

; -----------------------------------------------------------------------------
; _parse_locale
;
; Parse a C-locale string into an internal integer ID.
; RDI = const char *locale
; Returns EAX = LOCALE_*
; -----------------------------------------------------------------------------
_parse_locale:
    test    rdi, rdi
    jz      .default
    movzx   eax, byte [rdi]
    test    al, al
    jz      .default

    cmp     al, 't'
    je      .check_tr
    cmp     al, 'T'
    je      .check_tr
    cmp     al, 'a'
    je      .check_az
    cmp     al, 'A'
    je      .check_az
    cmp     al, 'n'
    je      .check_nl
    cmp     al, 'N'
    je      .check_nl
    cmp     al, 'l'
    je      .check_lt
    cmp     al, 'L'
    je      .check_lt
    cmp     al, 'd'
    je      .check_de
    cmp     al, 'D'
    je      .check_de

.default:
    xor     eax, eax
    ret

.check_tr:
    movzx   ecx, byte [rdi + 1]
    cmp     cl, 'r'
    je      .ret_tr
    cmp     cl, 'R'
    je      .ret_tr
    jmp     .default
.ret_tr:
    mov     eax, LOCALE_TR
    ret

.check_az:
    movzx   ecx, byte [rdi + 1]
    cmp     cl, 'z'
    je      .ret_tr
    cmp     cl, 'Z'
    je      .ret_tr
    jmp     .default

.check_nl:
    movzx   ecx, byte [rdi + 1]
    cmp     cl, 'l'
    je      .ret_nl
    cmp     cl, 'L'
    je      .ret_nl
    jmp     .default
.ret_nl:
    mov     eax, LOCALE_NL
    ret

.check_lt:
    movzx   ecx, byte [rdi + 1]
    cmp     cl, 't'
    je      .ret_lt
    cmp     cl, 'T'
    je      .ret_lt
    jmp     .default
.ret_lt:
    mov     eax, LOCALE_LT
    ret

.check_de:
    movzx   ecx, byte [rdi + 1]
    cmp     cl, 'e'
    je      .ret_de
    cmp     cl, 'E'
    je      .ret_de
    jmp     .default
.ret_de:
    mov     eax, LOCALE_DE
    ret

; -----------------------------------------------------------------------------
; str_to_upper_tailored
;
; Convert string to uppercase, applying locale-specific overrides.
;
; Signature:
;   int64_t str_to_upper_tailored(const StrSlice *src, uint8_t *buf,
;                                  uint64_t buf_cap, StrSlice *out,
;                                  const char *locale)
; -----------------------------------------------------------------------------
STR_FUNC str_to_upper_tailored
    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15
    sub     rsp, 32             ; 16 bytes for out_advance + 8 bytes padding + 8 bytes locale_id

    mov     rbx, rdi            ; src
    mov     r12, rsi            ; buf
    mov     r13, rdx            ; cap
    mov     r14, rcx            ; out

    ; parse locale
    mov     rdi, r8
    call    _parse_locale
    mov     [rsp + 16], rax     ; save locale_id

    mov     r15, [rbx + StrSlice.ptr]
    mov     r9,  [rbx + StrSlice.len]
    mov     r10, r15
    add     r10, r9             ; end ptr
    mov     r11, r12            ; write cursor

.up_loop:
    cmp     r15, r10
    jae     .up_done

    ; decode
    mov     rdi, r15
    lea     rsi, [rsp]          ; out_advance is at [rsp]
    call    str_utf8_decode_unchecked
    mov     r8, [rsp]
    add     r15, r8

    ; check overrides
    mov     rdi, [rsp + 16]     ; locale_id
    cmp     rdi, LOCALE_TR
    je      .up_turkish
    cmp     rdi, LOCALE_DE
    je      .up_german

.up_std:
    mov     edi, eax
    push    rax                 ; dummy alignment (4 registers pushed = 32 bytes)
    push    r15
    push    r10
    push    r11
    call    str_cp_to_upper
    pop     r11
    pop     r10
    pop     r15
    pop     rcx
    jmp     .up_encode

.up_turkish:
    cmp     eax, 'i'
    je      .up_tr_dotted
    cmp     eax, 0x0131         ; ı
    je      .up_tr_dotless
    jmp     .up_std

.up_tr_dotted:
    mov     eax, 0x0130         ; İ
    jmp     .up_encode
.up_tr_dotless:
    mov     eax, 'I'
    jmp     .up_encode

.up_german:
    cmp     eax, 0x00DF         ; ß
    je      .up_de_sz
    jmp     .up_std
.up_de_sz:
    mov     eax, 0x1E9E         ; ẞ (Capital Sharp S)
    jmp     .up_encode

.up_encode:
    ; capacity check
    mov     rcx, r11
    sub     rcx, r12
    mov     rdx, r13
    sub     rdx, rcx
    cmp     rdx, 4
    jb      .up_too_small

    mov     edi, eax
    mov     rsi, r11
    push    rax                 ; dummy alignment
    push    rax
    push    r15
    push    r10
    call    str_utf8_encode_unchecked
    pop     r10
    pop     r15
    pop     rcx
    pop     rcx

    add     r11, rax
    jmp     .up_loop

.up_done:
    mov     [r14 + StrSlice.ptr], r12
    mov     rax, r11
    sub     rax, r12
    mov     [r14 + StrSlice.len], rax

    add     rsp, 32
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.up_too_small:
    add     rsp, 32
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret
STR_ENDFUNC str_to_upper_tailored

; -----------------------------------------------------------------------------
; str_to_lower_tailored
;
; Convert string to lowercase, applying locale-specific overrides.
;
; Signature:
;   int64_t str_to_lower_tailored(const StrSlice *src, uint8_t *buf,
;                                  uint64_t buf_cap, StrSlice *out,
;                                  const char *locale)
; -----------------------------------------------------------------------------
STR_FUNC str_to_lower_tailored
    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15
    sub     rsp, 32             ; 16 bytes for out_advance + 8 bytes padding + 8 bytes locale_id

    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
    mov     r14, rcx

    mov     rdi, r8
    call    _parse_locale
    mov     [rsp + 16], rax

    mov     r15, [rbx + StrSlice.ptr]
    mov     r9,  [rbx + StrSlice.len]
    mov     r10, r15
    add     r10, r9
    mov     r11, r12

.lo_loop:
    cmp     r15, r10
    jae     .lo_done

    mov     rdi, r15
    lea     rsi, [rsp]          ; out_advance is at [rsp]
    call    str_utf8_decode_unchecked
    mov     r8, [rsp]
    add     r15, r8

    ; check overrides
    mov     rdi, [rsp + 16]
    cmp     rdi, LOCALE_TR
    je      .lo_turkish

.lo_std:
    mov     edi, eax
    push    rax                 ; dummy alignment
    push    r15
    push    r10
    push    r11
    call    str_cp_to_lower
    pop     r11
    pop     r10
    pop     r15
    pop     rcx
    jmp     .lo_encode

.lo_turkish:
    cmp     eax, 'I'
    je      .lo_tr_dotless
    cmp     eax, 0x0130         ; İ
    je      .lo_tr_dotted
    jmp     .lo_std

.lo_tr_dotless:
    mov     eax, 0x0131         ; ı
    jmp     .lo_encode
.lo_tr_dotted:
    mov     eax, 'i'
    jmp     .lo_encode

.lo_encode:
    mov     rcx, r11
    sub     rcx, r12
    mov     rdx, r13
    sub     rdx, rcx
    cmp     rdx, 4
    jb      .lo_too_small

    mov     edi, eax
    mov     rsi, r11
    push    rax                 ; dummy alignment
    push    rax
    push    r15
    push    r10
    call    str_utf8_encode_unchecked
    pop     r10
    pop     r15
    pop     rcx
    pop     rcx

    add     r11, rax
    jmp     .lo_loop

.lo_done:
    mov     [r14 + StrSlice.ptr], r12
    mov     rax, r11
    sub     rax, r12
    mov     [r14 + StrSlice.len], rax

    add     rsp, 32
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.lo_too_small:
    add     rsp, 32
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret
STR_ENDFUNC str_to_lower_tailored

; -----------------------------------------------------------------------------
; str_to_title_tailored
;
; Convert string to titlecase, applying locale-specific overrides (Dutch IJ, etc.).
;
; Signature:
;   int64_t str_to_title_tailored(const StrSlice *src, uint8_t *buf,
;                                  uint64_t buf_cap, StrSlice *out,
;                                  const char *locale)
; -----------------------------------------------------------------------------
STR_FUNC str_to_title_tailored
    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15
    sub     rsp, 32             ; 16 bytes for out_advance + 8 bytes padding + 8 bytes locale_id

    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
    mov     r14, rcx

    mov     rdi, r8
    call    _parse_locale
    mov     [rsp + 16], rax

    mov     r15, [rbx + StrSlice.ptr]
    mov     r9,  [rbx + StrSlice.len]
    mov     r10, r15
    add     r10, r9
    mov     r11, r12

    mov     r8b, 1              ; at_word_start = true

.tt_loop:
    cmp     r15, r10
    jae     .tt_done

    mov     rdi, r15
    lea     rsi, [rsp]          ; out_advance is at [rsp]
    call    str_utf8_decode_unchecked
    mov     rcx, [rsp]          ; advance
    add     r15, rcx

    ; check if space
    mov     edi, eax
    push    rax
    push    r15
    push    r10
    push    r11
    push    r8
    push    rax                 ; dummy push for alignment (6 registers = 48 bytes)
    call    str_is_space_cp
    pop     rcx
    pop     r8
    pop     r11
    pop     r10
    pop     r15
    pop     rcx                 ; rcx = original codepoint

    test    eax, eax
    jnz     .tt_is_space

    ; not space: apply casing
    test    r8b, r8b
    jnz     .tt_do_upper

    ; lowercase (check Turkish overrides)
    mov     rax, [rsp + 16]     ; locale_id
    cmp     rax, LOCALE_TR
    je      .tt_lo_tr

.tt_lo_std:
    mov     edi, ecx
    push    r15
    push    r10
    push    r11
    push    r8
    call    str_cp_to_lower
    pop     r8
    pop     r11
    pop     r10
    pop     r15
    xor     r8b, r8b
    jmp     .tt_encode

.tt_lo_tr:
    cmp     ecx, 'I'
    je      .tt_lo_tr_dotless
    cmp     ecx, 0x0130         ; İ
    je      .tt_lo_tr_dotted
    jmp     .tt_lo_std

.tt_lo_tr_dotless:
    mov     eax, 0x0131         ; ı
    xor     r8b, r8b
    jmp     .tt_encode
.tt_lo_tr_dotted:
    mov     eax, 'i'
    xor     r8b, r8b
    jmp     .tt_encode

.tt_do_upper:
    mov     rax, [rsp + 16]     ; locale_id
    cmp     rax, LOCALE_NL
    je      .tt_up_nl
    cmp     rax, LOCALE_TR
    je      .tt_up_tr
    cmp     rax, LOCALE_DE
    je      .tt_up_de

.tt_up_std:
    mov     edi, ecx
    push    r15
    push    r10
    push    r11
    push    r8
    call    str_cp_to_upper
    pop     r8
    pop     r11
    pop     r10
    pop     r15
    xor     r8b, r8b
    jmp     .tt_encode

.tt_up_nl:
    ; Dutch: if starting with 'i' (or 'I') and next is 'j' (or 'J'), capitalize both!
    cmp     ecx, 'i'
    je      .tt_nl_ij
    cmp     ecx, 'I'
    je      .tt_nl_ij
    jmp     .tt_up_std

.tt_nl_ij:
    ; check next character
    cmp     r15, r10
    jae     .tt_up_std          ; no next char

    push    rcx
    mov     rdi, r15
    lea     rsi, [rsp]
    call    str_utf8_decode_unchecked
    pop     rcx

    cmp     eax, 'j'
    je      .tt_nl_match
    cmp     eax, 'J'
    je      .tt_nl_match
    jmp     .tt_up_std

.tt_nl_match:
    ; write 'I' and 'J'
    ; 1. Encode 'I'
    mov     rax, r11
    sub     rax, r12
    mov     rdx, r13
    sub     rdx, rax
    cmp     rdx, 8
    jb      .tt_too_small

    mov     byte [r11], 'I'
    mov     byte [r11 + 1], 'J'
    add     r11, 2

    ; advance past 'j' / 'J'
    mov     rax, [rsp]
    add     r15, rax
    xor     r8b, r8b
    jmp     .tt_loop            ; skip standard encode loop

.tt_up_tr:
    cmp     ecx, 'i'
    je      .tt_up_tr_dotted
    cmp     ecx, 0x0131
    je      .tt_up_tr_dotless
    jmp     .tt_up_std

.tt_up_tr_dotted:
    mov     eax, 0x0130         ; İ
    xor     r8b, r8b
    jmp     .tt_encode
.tt_up_tr_dotless:
    mov     eax, 'I'
    xor     r8b, r8b
    jmp     .tt_encode

.tt_up_de:
    cmp     ecx, 0x00DF         ; ß
    je      .tt_up_de_sz
    jmp     .tt_up_std
.tt_up_de_sz:
    mov     eax, 0x1E9E         ; ẞ
    xor     r8b, r8b
    jmp     .tt_encode

.tt_is_space:
    mov     eax, ecx
    mov     r8b, 1

.tt_encode:
    mov     rdx, r11
    sub     rdx, r12
    mov     rcx, r13
    sub     rcx, rdx
    cmp     rcx, 4
    jb      .tt_too_small

    mov     edi, eax
    mov     rsi, r11
    push    rax                 ; dummy alignment
    push    r15
    push    r10
    push    r8
    call    str_utf8_encode_unchecked
    pop     r8
    pop     r10
    pop     r15
    pop     rcx

    add     r11, rax
    jmp     .tt_loop

.tt_done:
    mov     [r14 + StrSlice.ptr], r12
    mov     rax, r11
    sub     rax, r12
    mov     [r14 + StrSlice.len], rax

    add     rsp, 32
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.tt_too_small:
    add     rsp, 32
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret
STR_ENDFUNC str_to_title_tailored

%endif ; GUARD_LIB_STR_UNICODE_CASING_TAILORING_ASM
