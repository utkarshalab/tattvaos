; =============================================================================
; str/escape/json.asm
; JSON string escaping and unescaping (RFC 8259).
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   inspect/is_hex_digit.asm  (str_hex_digit_value)
;   utf8/encode.asm           (str_utf8_encode_unchecked)
;   utf8/decode.asm           (str_utf8_decode_unchecked)
;
; -----------------------------------------------------------------------------
; JSON string escaping rules (RFC 8259 §7):
;
;   '"'   → \"
;   '\'   → \\
;   '/'   → \/     (optional but valid)
;   BS    → \b     (0x08)
;   FF    → \f     (0x0C)
;   LF    → \n     (0x0A)
;   CR    → \r     (0x0D)
;   HT    → \t     (0x09)
;   0x00..0x1F → \uXXXX  (all other control chars)
;
; When unescaping:
;   \uXXXX sequences are decoded to UTF-8
;   \uD800..\uDFFF surrogate pairs: \uD83D\uDE00 → 🀀 emoji
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_hex_digit_value
extern str_utf8_encode_unchecked
extern str_utf8_decode_unchecked

section .rodata
_json_hex: db "0123456789abcdef"

section .text

; -----------------------------------------------------------------------------
; str_json_escape
;
; Escape a string for use as a JSON string value (without surrounding quotes).
;
; Signature:
;   int64_t str_json_escape(const StrSlice *src, uint8_t *dst,
;                            uint64_t dst_cap, uint64_t *out_len)
; -----------------------------------------------------------------------------

STR_FUNC str_json_escape

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
    lea     r11, [rel _json_hex]

.je_loop:
    cmp     r9, r12
    jae     .je_done

    movzx   eax, byte [rbx + r9]
    inc     r9

    ; check for characters needing escaping
    cmp     al, '"'
    je      .je_dquote
    cmp     al, 0x5C            ; backslash
    je      .je_backslash
    cmp     al, 0x08            ; BS
    je      .je_bs
    cmp     al, 0x0C            ; FF
    je      .je_ff
    cmp     al, 0x0A            ; LF
    je      .je_lf
    cmp     al, 0x0D            ; CR
    je      .je_cr
    cmp     al, 0x09            ; HT
    je      .je_ht
    cmp     al, 0x20            ; control chars 0x00..0x1F
    jb      .je_control

    ; regular byte — copy
    cmp     r10, r14
    jae     .je_overflow
    mov     [r13 + r10], al
    inc     r10
    jmp     .je_loop

; Helper: write 2-char escape sequence
%macro JE_ESC2 1            ; %1 = second char byte
    lea     rcx, [r10 + 2]
    cmp     rcx, r14
    ja      .je_overflow
    mov     byte [r13 + r10], '\'
    mov     byte [r13 + r10 + 1], %1
    add     r10, 2
    jmp     .je_loop
%endmacro

.je_dquote:     JE_ESC2 '"'
.je_backslash:  JE_ESC2 '\'
.je_bs:         JE_ESC2 'b'
.je_ff:         JE_ESC2 'f'
.je_lf:         JE_ESC2 'n'
.je_cr:         JE_ESC2 'r'
.je_ht:         JE_ESC2 't'

.je_control:
    ; \uXXXX for 0x00..0x1F
    lea     rcx, [r10 + 6]
    cmp     rcx, r14
    ja      .je_overflow

    mov     byte [r13 + r10],     '\'
    mov     byte [r13 + r10 + 1], 'u'
    mov     byte [r13 + r10 + 2], '0'
    mov     byte [r13 + r10 + 3], '0'

    ; high nibble of byte
    mov     ecx, eax
    shr     ecx, 4
    movzx   ecx, byte [r11 + rcx]
    mov     [r13 + r10 + 4], cl

    ; low nibble
    and     eax, 0xF
    movzx   eax, byte [r11 + rax]
    mov     [r13 + r10 + 5], al

    add     r10, 6
    jmp     .je_loop

.je_done:
    test    r15, r15
    jz      .je_ok
    mov     [r15], r10

.je_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.je_overflow:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_json_escape

; -----------------------------------------------------------------------------
; str_json_unescape
;
; Unescape a JSON string value (without surrounding quotes).
; Handles all JSON escape sequences including \uXXXX and surrogate pairs.
;
; Signature:
;   int64_t str_json_unescape(const StrSlice *src, uint8_t *dst,
;                              uint64_t dst_cap, uint64_t *out_len)
; -----------------------------------------------------------------------------

STR_FUNC str_json_unescape

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, [rdi + StrSlice.len]
    mov     r13, rsi
    mov     r14, rdx
    mov     r15, rcx

    xor     r9, r9
    xor     r10, r10

.ju_loop:
    cmp     r9, r12
    jae     .ju_done

    movzx   eax, byte [rbx + r9]
    inc     r9

    cmp     al, 0x5C            ; backslash
    je      .ju_escape

    ; regular byte — copy
    cmp     r10, r14
    jae     .ju_overflow
    mov     [r13 + r10], al
    inc     r10
    jmp     .ju_loop

.ju_escape:
    ; need at least one more char
    cmp     r9, r12
    jae     .ju_parse_err

    movzx   eax, byte [rbx + r9]
    inc     r9

    cmp     al, '"'
    je      .ju_esc_char
    cmp     al, 0x5C
    je      .ju_esc_char
    cmp     al, '/'
    je      .ju_esc_char

    cmp     al, 'b'
    je      .ju_esc_bs
    cmp     al, 'f'
    je      .ju_esc_ff
    cmp     al, 'n'
    je      .ju_esc_lf
    cmp     al, 'r'
    je      .ju_esc_cr
    cmp     al, 't'
    je      .ju_esc_ht

    cmp     al, 'u'
    je      .ju_unicode

    ; unknown escape — pass through as-is
    jmp     .ju_esc_char

.ju_esc_char:
    cmp     r10, r14
    jae     .ju_overflow
    mov     [r13 + r10], al
    inc     r10
    jmp     .ju_loop

.ju_esc_bs:
    mov     al, 0x08
    jmp     .ju_esc_char
.ju_esc_ff:
    mov     al, 0x0C
    jmp     .ju_esc_char
.ju_esc_lf:
    mov     al, 0x0A
    jmp     .ju_esc_char
.ju_esc_cr:
    mov     al, 0x0D
    jmp     .ju_esc_char
.ju_esc_ht:
    mov     al, 0x09
    jmp     .ju_esc_char

.ju_unicode:
    ; parse 4 hex digits
    lea     rcx, [r9 + 4]
    cmp     rcx, r12
    ja      .ju_parse_err

    ; parse 4-digit hex into r8d
    xor     r8d, r8d
    mov     rcx, 4

.ju_hex4:
    test    rcx, rcx
    jz      .ju_hex4_done

    movzx   edi, byte [rbx + r9]
    push    r9
    push    rcx
    push    r8
    call    str_hex_digit_value
    pop     r8
    pop     rcx
    pop     r9
    test    rax, rax
    js      .ju_parse_err

    shl     r8d, 4
    or      r8d, eax
    inc     r9
    dec     ecx
    jmp     .ju_hex4

.ju_hex4_done:
    ; r8d = codepoint (may be surrogate)

    ; check for surrogate pair: D800..DBFF = high surrogate
    cmp     r8d, 0xD800
    jb      .ju_emit_cp
    cmp     r8d, 0xDBFF
    ja      .ju_emit_cp

    ; high surrogate — need \uXXXX for low surrogate
    cmp     r9 + 6, r12
    ja      .ju_emit_cp         ; no room for \uDxxx — emit replacement

    cmp     byte [rbx + r9], '\'
    jne     .ju_emit_cp
    cmp     byte [rbx + r9 + 1], 'u'
    jne     .ju_emit_cp

    add     r9, 2               ; skip \u

    ; parse low surrogate
    xor     r11d, r11d
    mov     rcx, 4

.ju_low_hex4:
    test    ecx, ecx
    jz      .ju_low_done

    movzx   edi, byte [rbx + r9]
    push    r9
    push    rcx
    push    r8
    push    r11
    call    str_hex_digit_value
    pop     r11
    pop     r8
    pop     rcx
    pop     r9
    test    rax, rax
    js      .ju_emit_cp

    shl     r11d, 4
    or      r11d, eax
    inc     r9
    dec     ecx
    jmp     .ju_low_hex4

.ju_low_done:
    ; validate low surrogate: DC00..DFFF
    cmp     r11d, 0xDC00
    jb      .ju_emit_cp
    cmp     r11d, 0xDFFF
    ja      .ju_emit_cp

    ; combine surrogates: cp = 0x10000 + (high-0xD800)*0x400 + (low-0xDC00)
    sub     r8d, 0xD800
    shl     r8d, 10
    sub     r11d, 0xDC00
    or      r8d, r11d
    add     r8d, 0x10000

.ju_emit_cp:
    ; encode r8d as UTF-8 into dst
    lea     rcx, [r10 + 4]
    cmp     rcx, r14
    ja      .ju_overflow

    mov     edi, r8d
    lea     rsi, [r13 + r10]
    push    r9
    push    r10
    call    str_utf8_encode_unchecked
    pop     r10
    pop     r9
    add     r10, rax
    jmp     .ju_loop

.ju_done:
    test    r15, r15
    jz      .ju_ok
    mov     [r15], r10

.ju_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.ju_parse_err:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_PARSE
    pop     rbp
    ret

.ju_overflow:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_json_unescape

; -----------------------------------------------------------------------------
; str_json_escape_into_buf
;
; Like str_json_escape but includes surrounding double quotes.
; Produces: "content"
;
; Signature:
;   int64_t str_json_escape_into_buf(const StrSlice *src,
;                                     uint8_t *dst, uint64_t dst_cap,
;                                     uint64_t *out_len)
; -----------------------------------------------------------------------------

STR_FUNC str_json_escape_into_buf

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    ; need at least 2 bytes for the quotes
    cmp     rdx, 2
    jb      .jeb_too_small

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
    mov     r14, rcx

    ; write opening quote
    mov     byte [r12], '"'

    ; escape into dst+1 with cap-2
    mov     rdi, rbx
    lea     rsi, [r12 + 1]
    mov     rdx, r13
    sub     rdx, 2
    sub     rsp, 8
    and     rsp, -8
    mov     rcx, rsp
    call    str_json_escape
    test    rax, rax
    jnz     .jeb_err

    mov     r15, [rsp]          ; inner length
    add     rsp, 8

    ; write closing quote
    lea     rax, [r12 + 1 + r15]
    cmp     rax, r12
    ; always have room (we reserved 2 bytes total)
    mov     byte [rax], '"'

    ; total = 1 + inner + 1
    add     r15, 2

    test    r14, r14
    jz      .jeb_ok
    mov     [r14], r15

.jeb_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.jeb_err:
    add     rsp, 8
    pop_regs r15, r14, r13, r12, rbx
    pop     rbp
    ret

.jeb_too_small:
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_json_escape_into_buf