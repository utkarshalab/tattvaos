%ifndef GUARD_LIB_STR_UNICODE_IDNA_ASM
%define GUARD_LIB_STR_UNICODE_IDNA_ASM
; =============================================================================
; str/unicode/idna.asm
; Internationalized Domain Names (IDNA2008 / UTS #46).
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   unicode/punycode.asm   (str_punycode_encode, str_punycode_decode)
;   unicode/normalize.asm  (str_normalize_nfc)
;   unicode/casefold.asm   (str_cp_fold_simple)
;   utf8/decode.asm        (str_utf8_decode_unchecked)
;
; -----------------------------------------------------------------------------
; IDNA converts internationalized domain names between Unicode form and
; ASCII-Compatible Encoding (ACE) form using Punycode with "xn--" prefix.
;
;   "münchen.de"  ⟷  "xn--mnchen-3ya.de"
;   "例え.テスト"  ⟷  "xn--r8jz45g.xn--zckzah"
;
; Processing (UTS #46):
;   to_ascii:
;     1. For each label (split on '.'):
;        a. Map characters (case fold, normalize NFC)
;        b. If contains non-ASCII: punycode-encode, prepend "xn--"
;        c. Validate label length (<= 63 octets)
;   to_unicode:
;     1. For each label:
;        a. If starts with "xn--": strip prefix, punycode-decode
;        b. Otherwise: leave as-is
;
; Functions:
;   str_idna_to_ascii     — Unicode domain → ACE (xn-- form)
;   str_idna_to_unicode   — ACE domain → Unicode
;   str_idna_label_ascii  — convert a single label to ACE
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"



MAX_LABEL_LEN   equ 63       ; DNS label octet limit

section .rodata
_idna_prefix: db "xn--", 0   ; ACE prefix

section .text

; -----------------------------------------------------------------------------
; _label_is_ascii  (internal)
;
; Check if a label (byte range) is pure ASCII.
;
; Arguments: RDI = ptr, RSI = len
; Returns:   EAX = 1 if all ASCII, 0 otherwise
; -----------------------------------------------------------------------------

_label_is_ascii:
    xor     ecx, ecx
.lia_loop:
    cmp     rcx, rsi
    jae     .lia_yes
    movzx   eax, byte [rdi + rcx]
    test    al, 0x80
    jnz     .lia_no
    inc     rcx
    jmp     .lia_loop
.lia_yes:
    mov     eax, 1
    ret
.lia_no:
    xor     eax, eax
    ret

; -----------------------------------------------------------------------------
; str_idna_label_ascii
;
; Convert a single domain label to ASCII-Compatible Encoding.
; If the label is already ASCII, it's copied as-is.
; If it contains non-ASCII, it's punycode-encoded with "xn--" prefix.
;
; Signature:
;   int64_t str_idna_label_ascii(const StrSlice *label, uint8_t *dst,
;                                 uint64_t dst_cap, uint64_t *out_len)
; -----------------------------------------------------------------------------

STR_FUNC str_idna_label_ascii

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, [rdi + StrSlice.ptr]   ; label ptr
    mov     r12, [rdi + StrSlice.len]   ; label len
    mov     r13, rsi            ; dst
    mov     r14, rdx            ; cap
    mov     r15, rcx            ; out_len

    ; check if pure ASCII
    mov     rdi, rbx
    mov     rsi, r12
    call    _label_is_ascii
    test    eax, eax
    jz      .ila_encode

    ; pure ASCII — copy as-is
    cmp     r12, r14
    ja      .ila_overflow

    xor     rcx, rcx
.ila_copy:
    cmp     rcx, r12
    jae     .ila_copy_done
    movzx   eax, byte [rbx + rcx]
    mov     [r13 + rcx], al
    inc     rcx
    jmp     .ila_copy

.ila_copy_done:
    test    r15, r15
    jz      .ila_ok
    mov     [r15], r12

.ila_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.ila_encode:
    ; non-ASCII — prepend "xn--" then punycode encode
    cmp     r14, 4
    jb      .ila_overflow

    ; write "xn--"
    mov     byte [r13 + 0], 'x'
    mov     byte [r13 + 1], 'n'
    mov     byte [r13 + 2], '-'
    mov     byte [r13 + 3], '-'

    ; punycode-encode label into dst+4
    sub     rsp, STRSLICE_SIZE + 16
    and     rsp, -16

    mov     [rsp + StrSlice.ptr], rbx
    mov     [rsp + StrSlice.len], r12

    lea     rdi, [rsp]
    lea     rsi, [r13 + 4]
    mov     rdx, r14
    sub     rdx, 4
    lea     rcx, [rsp + STRSLICE_SIZE]
    call    str_punycode_encode
    test    rax, rax
    jnz     .ila_encode_err

    mov     r9, [rsp + STRSLICE_SIZE]   ; encoded length
    mov     rsp, rbp

    ; total length = 4 + encoded
    add     r9, 4

    ; validate against MAX_LABEL_LEN
    cmp     r9, MAX_LABEL_LEN
    ja      .ila_too_long

    test    r15, r15
    jz      .ila_ok2
    mov     [r15], r9

.ila_ok2:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.ila_encode_err:
    mov     rsp, rbp
    pop_regs r15, r14, r13, r12, rbx
    pop     rbp
    ret

.ila_too_long:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_INVALID
    pop     rbp
    ret

.ila_overflow:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_idna_label_ascii

; -----------------------------------------------------------------------------
; str_idna_to_ascii
;
; Convert a full Unicode domain name to ACE form.
; Splits on '.', converts each label, rejoins with '.'.
;
; Signature:
;   int64_t str_idna_to_ascii(const StrSlice *domain, uint8_t *dst,
;                              uint64_t dst_cap, uint64_t *out_len)
; -----------------------------------------------------------------------------

STR_FUNC str_idna_to_ascii

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, [rdi + StrSlice.ptr]   ; domain ptr
    mov     r12, [rdi + StrSlice.len]   ; domain len
    mov     r13, rsi            ; dst
    mov     r14, rdx            ; cap
    mov     r15, rcx            ; out_len

    xor     r9, r9              ; src index
    xor     r10, r10            ; dst index
    xor     r11, r11            ; label start

.ita_loop:
    cmp     r9, r12
    jae     .ita_last_label

    movzx   eax, byte [rbx + r9]
    cmp     al, '.'
    jne     .ita_next_char

    ; found '.' — process label [r11, r9)
    sub     rsp, STRSLICE_SIZE + 16
    and     rsp, -16

    lea     rax, [rbx + r11]
    mov     [rsp + StrSlice.ptr], rax
    mov     rax, r9
    sub     rax, r11
    mov     [rsp + StrSlice.len], rax

    lea     rdi, [rsp]
    lea     rsi, [r13 + r10]
    mov     rdx, r14
    sub     rdx, r10
    lea     rcx, [rsp + STRSLICE_SIZE]
    push    r9
    push    r10
    push    r11
    call    str_idna_label_ascii
    pop     r11
    pop     r10
    pop     r9
    test    rax, rax
    jnz     .ita_err

    add     r10, [rsp + STRSLICE_SIZE]  ; advance dst by label len
    mov     rsp, rbp

    ; write '.'
    cmp     r10, r14
    jae     .ita_overflow
    mov     byte [r13 + r10], '.'
    inc     r10

    inc     r9
    mov     r11, r9             ; next label start
    jmp     .ita_loop

.ita_next_char:
    inc     r9
    jmp     .ita_loop

.ita_last_label:
    ; process final label [r11, r12)
    cmp     r11, r12
    jae     .ita_done           ; empty trailing label

    sub     rsp, STRSLICE_SIZE + 16
    and     rsp, -16

    lea     rax, [rbx + r11]
    mov     [rsp + StrSlice.ptr], rax
    mov     rax, r12
    sub     rax, r11
    mov     [rsp + StrSlice.len], rax

    lea     rdi, [rsp]
    lea     rsi, [r13 + r10]
    mov     rdx, r14
    sub     rdx, r10
    lea     rcx, [rsp + STRSLICE_SIZE]
    push    r10
    call    str_idna_label_ascii
    pop     r10
    test    rax, rax
    jnz     .ita_err2

    add     r10, [rsp + STRSLICE_SIZE]
    mov     rsp, rbp

.ita_done:
    test    r15, r15
    jz      .ita_ok
    mov     [r15], r10

.ita_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.ita_err2:
    mov     rsp, rbp
.ita_err:
    pop_regs r15, r14, r13, r12, rbx
    pop     rbp
    ret

.ita_overflow:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_idna_to_ascii

; -----------------------------------------------------------------------------
; str_idna_to_unicode
;
; Convert an ACE domain name back to Unicode.
; For each label starting with "xn--", strip prefix and punycode-decode.
;
; Signature:
;   int64_t str_idna_to_unicode(const StrSlice *domain, uint8_t *dst,
;                                uint64_t dst_cap, uint64_t *out_len)
; -----------------------------------------------------------------------------

STR_FUNC str_idna_to_unicode

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, [rdi + StrSlice.len]
    mov     r13, rsi
    mov     r14, rdx
    mov     r15, rcx

    xor     r9, r9              ; src index
    xor     r10, r10            ; dst index
    xor     r11, r11            ; label start

.itu_loop:
    cmp     r9, r12
    jae     .itu_last

    movzx   eax, byte [rbx + r9]
    cmp     al, '.'
    jne     .itu_next

    ; process label [r11, r9)
    call    .itu_process_label
    test    rax, rax
    jnz     .itu_err

    ; write '.'
    cmp     r10, r14
    jae     .itu_overflow
    mov     byte [r13 + r10], '.'
    inc     r10

    inc     r9
    mov     r11, r9
    jmp     .itu_loop

.itu_next:
    inc     r9
    jmp     .itu_loop

.itu_last:
    cmp     r11, r12
    jae     .itu_done

    mov     r9, r12             ; label end = domain end
    call    .itu_process_label
    test    rax, rax
    jnz     .itu_err

.itu_done:
    test    r15, r15
    jz      .itu_ok
    mov     [r15], r10

.itu_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.itu_err:
    pop_regs r15, r14, r13, r12, rbx
    pop     rbp
    ret

.itu_overflow:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

; internal: process label [r11, r9), write decoded form to dst[r10]
; updates r10. Returns rax = error code.
.itu_process_label:
    push    rbp
    mov     rbp, rsp

    mov     rcx, r9
    sub     rcx, r11            ; label len

    ; check for "xn--" prefix (need >= 4 chars)
    cmp     rcx, 4
    jb      .ipl_copy_plain

    cmp     byte [rbx + r11 + 0], 'x'
    jne     .ipl_copy_plain
    cmp     byte [rbx + r11 + 1], 'n'
    jne     .ipl_copy_plain
    cmp     byte [rbx + r11 + 2], '-'
    jne     .ipl_copy_plain
    cmp     byte [rbx + r11 + 3], '-'
    jne     .ipl_copy_plain

    ; xn-- label — punycode decode [r11+4, r9)
    sub     rsp, STRSLICE_SIZE + 16
    and     rsp, -16

    lea     rax, [rbx + r11 + 4]
    mov     [rsp + StrSlice.ptr], rax
    mov     rax, r9
    sub     rax, r11
    sub     rax, 4
    mov     [rsp + StrSlice.len], rax

    lea     rdi, [rsp]
    lea     rsi, [r13 + r10]
    mov     rdx, r14
    sub     rdx, r10
    lea     rcx, [rsp + STRSLICE_SIZE]
    call    str_punycode_decode
    test    rax, rax
    jnz     .ipl_err

    add     r10, [rsp + STRSLICE_SIZE]
    mov     rsp, rbp
    xor     eax, eax
    pop     rbp
    ret

.ipl_copy_plain:
    ; copy label as-is
    xor     rdx, rdx
.ipl_copy_loop:
    lea     rax, [r11 + rdx]
    cmp     rax, r9
    jae     .ipl_copy_done
    cmp     r10, r14
    jae     .ipl_of
    movzx   eax, byte [rbx + r11 + rdx]
    mov     [r13 + r10], al
    inc     r10
    inc     rdx
    jmp     .ipl_copy_loop

.ipl_copy_done:
    xor     eax, eax
    pop     rbp
    ret

.ipl_of:
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

.ipl_err:
    mov     rsp, rbp
    pop     rbp
    ret

STR_ENDFUNC str_idna_to_unicode
%endif ; GUARD_LIB_STR_UNICODE_IDNA_ASM
