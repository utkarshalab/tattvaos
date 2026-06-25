; =============================================================================
; str/escape/html.asm
; HTML entity escaping and unescaping.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   buf/writer.asm  (str_writer_write, str_writer_write_byte)
;   core/copy.asm   (str_copy_bytes)
;
; -----------------------------------------------------------------------------
; HTML escaping: replace special characters with HTML entities.
;
;   '&'  → "&amp;"
;   '<'  → "&lt;"
;   '>'  → "&gt;"
;   '"'  → "&quot;"
;   '\'' → "&#39;" or "&apos;"
;
; HTML unescaping: reverse the above, plus named entities.
;
; Functions:
;   str_html_escape       — escape a StrSlice → buffer
;   str_html_escape_attr  — escape for HTML attribute context (also quotes)
;   str_html_unescape     — unescape HTML entities → buffer
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_copy_bytes

section .rodata

_html_amp:   db "&amp;",  0    ; 5 bytes
_html_lt:    db "&lt;",   0    ; 4 bytes
_html_gt:    db "&gt;",   0    ; 4 bytes
_html_quot:  db "&quot;", 0    ; 6 bytes
_html_apos:  db "&#39;",  0    ; 5 bytes

section .text

; -----------------------------------------------------------------------------
; str_html_escape
;
; Escape HTML special characters.
; Escapes: & < > " '
;
; Signature:
;   int64_t str_html_escape(const StrSlice *src, uint8_t *dst,
;                            uint64_t dst_cap, uint64_t *out_len)
;
; Arguments:
;   RDI  — source StrSlice
;   RSI  — destination buffer
;   RDX  — capacity
;   RCX  — out_len (may be null)
;
; Returns:
;   RAX  = STR_OK
;   RAX  = STR_ERR_NULL
;   RAX  = STR_ERR_BUF_TOO_SMALL
; -----------------------------------------------------------------------------

STR_FUNC str_html_escape

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, [rdi + StrSlice.len]
    mov     r13, rsi            ; dst
    mov     r14, rdx            ; cap
    mov     r15, rcx            ; out_len

    xor     r9, r9              ; src index
    xor     r10, r10            ; dst index

.he_loop:
    cmp     r9, r12
    jae     .he_done

    movzx   eax, byte [rbx + r9]
    inc     r9

    ; check for special chars
    cmp     al, '&'
    je      .he_amp
    cmp     al, '<'
    je      .he_lt
    cmp     al, '>'
    je      .he_gt
    cmp     al, '"'
    je      .he_quot
    cmp     al, 0x27            ; single quote
    je      .he_apos

    ; regular byte — copy directly
    cmp     r10, r14
    jae     .he_overflow
    mov     [r13 + r10], al
    inc     r10
    jmp     .he_loop

; Helper macro-like: write replacement string
%macro HE_WRITE_ESC 2       ; %1 = ptr to string, %2 = length
    mov     rcx, r10
    add     rcx, %2
    cmp     rcx, r14
    ja      .he_overflow
    mov     rdi, r13
    add     rdi, r10
    lea     rsi, [rel %1]
    mov     rdx, %2
    push    r9
    push    r10
    call    str_copy_bytes
    pop     r10
    pop     r9
    add     r10, %2
    jmp     .he_loop
%endmacro

.he_amp:
    HE_WRITE_ESC _html_amp, 5

.he_lt:
    HE_WRITE_ESC _html_lt, 4

.he_gt:
    HE_WRITE_ESC _html_gt, 4

.he_quot:
    HE_WRITE_ESC _html_quot, 6

.he_apos:
    HE_WRITE_ESC _html_apos, 5

.he_done:
    test    r15, r15
    jz      .he_ok
    mov     [r15], r10

.he_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.he_overflow:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_html_escape

; -----------------------------------------------------------------------------
; str_html_escape_attr
;
; Like str_html_escape but intended for attribute values.
; Escapes & < > " (no single quote — use double quotes for attributes).
; -----------------------------------------------------------------------------

STR_FUNC str_html_escape_attr

    ; identical to str_html_escape for our set — just delegate
    pop     rbp
    jmp     str_html_escape

STR_ENDFUNC str_html_escape_attr

; -----------------------------------------------------------------------------
; str_html_unescape
;
; Unescape HTML entities in a string.
; Handles: &amp; &lt; &gt; &quot; &apos; &#NNN; &#xHHH;
;
; Signature:
;   int64_t str_html_unescape(const StrSlice *src, uint8_t *dst,
;                              uint64_t dst_cap, uint64_t *out_len)
; -----------------------------------------------------------------------------

extern str_utf8_encode_unchecked

STR_FUNC str_html_unescape

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

.hu_loop:
    cmp     r9, r12
    jae     .hu_done

    movzx   eax, byte [rbx + r9]

    cmp     al, '&'
    je      .hu_entity

    ; regular byte
    cmp     r10, r14
    jae     .hu_overflow
    mov     [r13 + r10], al
    inc     r9
    inc     r10
    jmp     .hu_loop

.hu_entity:
    ; scan to ';'
    mov     r11, r9
    inc     r11                 ; skip '&'

.hu_scan_semi:
    cmp     r11, r12
    jae     .hu_literal         ; no ';' found — output literal '&'

    movzx   ecx, byte [rbx + r11]
    cmp     cl, ';'
    je      .hu_found_semi
    inc     r11
    jmp     .hu_scan_semi

.hu_found_semi:
    ; entity is from r9+1 to r11-1
    ; r11 points to ';'

    ; check numeric: &#NNN; or &#xHHH;
    movzx   ecx, byte [rbx + r9 + 1]
    cmp     cl, '#'
    je      .hu_numeric

    ; named entity — match against known set
    mov     rdx, r11
    sub     rdx, r9
    dec     rdx                 ; entity name length (without & and ;)

    ; check "&amp;" (len=3: "amp")
    cmp     rdx, 3
    jne     .hu_check_lt

    movzx   ecx, byte [rbx + r9 + 1]
    cmp     cl, 'a'
    jne     .hu_check_lt
    movzx   ecx, byte [rbx + r9 + 2]
    cmp     cl, 'm'
    jne     .hu_check_lt
    movzx   ecx, byte [rbx + r9 + 3]
    cmp     cl, 'p'
    jne     .hu_check_lt

    ; &amp; → '&'
    cmp     r10, r14
    jae     .hu_overflow
    mov     byte [r13 + r10], '&'
    inc     r10
    mov     r9, r11
    inc     r9
    jmp     .hu_loop

.hu_check_lt:
    cmp     rdx, 2
    jne     .hu_check_gt

    movzx   ecx, byte [rbx + r9 + 1]
    cmp     cl, 'l'
    jne     .hu_check_gt
    movzx   ecx, byte [rbx + r9 + 2]
    cmp     cl, 't'
    jne     .hu_check_gt

    cmp     r10, r14
    jae     .hu_overflow
    mov     byte [r13 + r10], '<'
    inc     r10
    mov     r9, r11
    inc     r9
    jmp     .hu_loop

.hu_check_gt:
    movzx   ecx, byte [rbx + r9 + 1]
    cmp     cl, 'g'
    jne     .hu_check_quot
    movzx   ecx, byte [rbx + r9 + 2]
    cmp     cl, 't'
    jne     .hu_check_quot

    cmp     r10, r14
    jae     .hu_overflow
    mov     byte [r13 + r10], '>'
    inc     r10
    mov     r9, r11
    inc     r9
    jmp     .hu_loop

.hu_check_quot:
    cmp     rdx, 4
    jne     .hu_check_apos

    ; "quot"
    movzx   ecx, byte [rbx + r9 + 1]
    cmp     cl, 'q'
    jne     .hu_literal
    movzx   ecx, byte [rbx + r9 + 2]
    cmp     cl, 'u'
    jne     .hu_literal
    movzx   ecx, byte [rbx + r9 + 3]
    cmp     cl, 'o'
    jne     .hu_literal
    movzx   ecx, byte [rbx + r9 + 4]
    cmp     cl, 't'
    jne     .hu_literal

    cmp     r10, r14
    jae     .hu_overflow
    mov     byte [r13 + r10], '"'
    inc     r10
    mov     r9, r11
    inc     r9
    jmp     .hu_loop

.hu_check_apos:
    cmp     rdx, 4
    jne     .hu_literal

    ; "apos"
    movzx   ecx, byte [rbx + r9 + 1]
    cmp     cl, 'a'
    jne     .hu_literal
    movzx   ecx, byte [rbx + r9 + 2]
    cmp     cl, 'p'
    jne     .hu_literal
    movzx   ecx, byte [rbx + r9 + 3]
    cmp     cl, 'o'
    jne     .hu_literal
    movzx   ecx, byte [rbx + r9 + 4]
    cmp     cl, 's'
    jne     .hu_literal

    cmp     r10, r14
    jae     .hu_overflow
    mov     byte [r13 + r10], 0x27
    inc     r10
    mov     r9, r11
    inc     r9
    jmp     .hu_loop

.hu_numeric:
    ; &#NNN; or &#xHHH;
    mov     r8, r9
    add     r8, 2               ; skip '&#'

    xor     ecx, ecx            ; codepoint accumulator
    xor     r8d, r8d            ; reuse r8 as base flag

    movzx   edx, byte [rbx + r9 + 2]
    cmp     dl, 'x'
    je      .hu_hex_entity
    cmp     dl, 'X'
    je      .hu_hex_entity

    ; decimal entity
    mov     r8, r9
    add     r8, 2

.hu_dec_loop:
    cmp     r8, r11
    jae     .hu_emit_cp

    movzx   edx, byte [rbx + r8]
    sub     edx, '0'
    cmp     edx, 9
    ja      .hu_literal

    imul    ecx, ecx, 10
    add     ecx, edx
    inc     r8
    jmp     .hu_dec_loop

.hu_hex_entity:
    mov     r8, r9
    add     r8, 3               ; skip '&#x'

.hu_hex_loop:
    cmp     r8, r11
    jae     .hu_emit_cp

    movzx   edx, byte [rbx + r8]
    cmp     dl, '0'
    jb      .hu_literal
    cmp     dl, '9'
    jbe     .hu_hex_digit

    or      dl, 0x20
    cmp     dl, 'a'
    jb      .hu_literal
    cmp     dl, 'f'
    ja      .hu_literal
    sub     dl, 'a'
    add     dl, 10

.hu_hex_digit:
    shl     ecx, 4
    or      ecx, edx
    inc     r8
    jmp     .hu_hex_loop

.hu_emit_cp:
    ; encode codepoint ecx as UTF-8 into dst
    cmp     r10 + 4, r14
    ja      .hu_overflow

    mov     edi, ecx
    lea     rsi, [r13 + r10]
    push    r9
    push    r10
    push    r11
    call    str_utf8_encode_unchecked
    pop     r11
    pop     r10
    pop     r9

    add     r10, rax
    mov     r9, r11
    inc     r9
    jmp     .hu_loop

.hu_literal:
    ; unknown entity — output literal '&'
    cmp     r10, r14
    jae     .hu_overflow
    mov     byte [r13 + r10], '&'
    inc     r10
    inc     r9
    jmp     .hu_loop

.hu_done:
    test    r15, r15
    jz      .hu_ok
    mov     [r15], r10

.hu_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.hu_overflow:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_html_unescape