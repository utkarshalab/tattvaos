%ifndef GUARD_LIB_STR_ESCAPE_XML_ASM
%define GUARD_LIB_STR_ESCAPE_XML_ASM
; =============================================================================
; str/escape/xml.asm
; XML character escaping and unescaping.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   core/copy.asm             (str_copy_bytes)
;   utf8/encode.asm           (str_utf8_encode_unchecked)
;
; -----------------------------------------------------------------------------
; XML escaping (XML 1.0 §2.4, §3.3.3):
;
;   '&'  → "&amp;"    (REQUIRED)
;   '<'  → "&lt;"     (REQUIRED in text and attr)
;   '>'  → "&gt;"     (REQUIRED after ]]  in text, recommended elsewhere)
;   '"'  → "&quot;"   (REQUIRED in double-quoted attr values)
;   '\'' → "&apos;"   (REQUIRED in single-quoted attr values)
;
; Also handles numeric character references: &#N; and &#xN;
;
; Context modes:
;   CONTEXT_TEXT  — escape &, <, > only
;   CONTEXT_ATTR  — escape &, <, >, ", '
;   CONTEXT_CDATA — no escaping (inside <![CDATA[...]]>)
;
; Functions:
;   str_xml_escape        — escape for text content
;   str_xml_escape_attr   — escape for attribute values
;   str_xml_unescape      — unescape XML entities
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"


section .rodata
_xml_amp:  db "&amp;",  0       ; 5
_xml_lt:   db "&lt;",   0       ; 4
_xml_gt:   db "&gt;",   0       ; 4
_xml_quot: db "&quot;", 0       ; 6
_xml_apos: db "&apos;", 0       ; 6

section .text

; Internal helper: write a static string to dst
; RDI = dst base, R10 = dst offset, R14 = cap
; RSI = src ptr, RDX = len
; Returns updated R10, or jumps to .xe_overflow
%macro XML_WRITE_ESC 2      ; %1 = rodata label, %2 = length
    lea     rcx, [r10 + %2]
    cmp     rcx, r14
    ja      .xe_overflow
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
    jmp     .xe_loop
%endmacro

; -----------------------------------------------------------------------------
; str_xml_escape
;
; Escape text content (escapes & < >).
;
; Signature:
;   int64_t str_xml_escape(const StrSlice *src, uint8_t *dst,
;                           uint64_t dst_cap, uint64_t *out_len)
; -----------------------------------------------------------------------------

STR_FUNC str_xml_escape

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

.xe_loop:
    cmp     r9, r12
    jae     .xe_done

    movzx   eax, byte [rbx + r9]
    inc     r9

    cmp     al, '&'
    je      .xe_amp
    cmp     al, '<'
    je      .xe_lt
    cmp     al, '>'
    je      .xe_gt

    ; copy as-is
    cmp     r10, r14
    jae     .xe_overflow
    mov     [r13 + r10], al
    inc     r10
    jmp     .xe_loop

.xe_amp: XML_WRITE_ESC _xml_amp, 5
.xe_lt:  XML_WRITE_ESC _xml_lt, 4
.xe_gt:  XML_WRITE_ESC _xml_gt, 4

.xe_done:
    test    r15, r15
    jz      .xe_ok
    mov     [r15], r10

.xe_ok:
    pop_regs r15, r14, r13, r12, rbx
    ret_ok

.xe_overflow:
    pop_regs r15, r14, r13, r12, rbx
    ret_err STR_ERR_BUF_TOO_SMALL

STR_ENDFUNC str_xml_escape

; -----------------------------------------------------------------------------
; str_xml_escape_attr
;
; Escape attribute value (escapes & < > " ').
;
; Signature:
;   int64_t str_xml_escape_attr(const StrSlice *src, uint8_t *dst,
;                                uint64_t dst_cap, uint64_t *out_len)
; -----------------------------------------------------------------------------

STR_FUNC str_xml_escape_attr

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

.xea_loop:
    cmp     r9, r12
    jae     .xea_done

    movzx   eax, byte [rbx + r9]
    inc     r9

    cmp     al, '&'
    je      .xea_amp
    cmp     al, '<'
    je      .xea_lt
    cmp     al, '>'
    je      .xea_gt
    cmp     al, '"'
    je      .xea_quot
    cmp     al, 0x27
    je      .xea_apos

    cmp     r10, r14
    jae     .xea_overflow
    mov     [r13 + r10], al
    inc     r10
    jmp     .xea_loop

%macro XEA_WRITE_ESC 2
    lea     rcx, [r10 + %2]
    cmp     rcx, r14
    ja      .xea_overflow
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
    jmp     .xea_loop
%endmacro

.xea_amp:  XEA_WRITE_ESC _xml_amp, 5
.xea_lt:   XEA_WRITE_ESC _xml_lt, 4
.xea_gt:   XEA_WRITE_ESC _xml_gt, 4
.xea_quot: XEA_WRITE_ESC _xml_quot, 6
.xea_apos: XEA_WRITE_ESC _xml_apos, 6

.xea_done:
    test    r15, r15
    jz      .xea_ok
    mov     [r15], r10

.xea_ok:
    pop_regs r15, r14, r13, r12, rbx
    ret_ok

.xea_overflow:
    pop_regs r15, r14, r13, r12, rbx
    ret_err STR_ERR_BUF_TOO_SMALL

STR_ENDFUNC str_xml_escape_attr

; -----------------------------------------------------------------------------
; str_xml_unescape
;
; Unescape XML entities. Handles: &amp; &lt; &gt; &quot; &apos; &#N; &#xN;
;
; Signature:
;   int64_t str_xml_unescape(const StrSlice *src, uint8_t *dst,
;                             uint64_t dst_cap, uint64_t *out_len)
; -----------------------------------------------------------------------------

STR_FUNC str_xml_unescape

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

.xu_loop:
    cmp     r9, r12
    jae     .xu_done

    movzx   eax, byte [rbx + r9]

    cmp     al, '&'
    je      .xu_entity

    cmp     r10, r14
    jae     .xu_overflow
    mov     [r13 + r10], al
    inc     r9
    inc     r10
    jmp     .xu_loop

.xu_entity:
    ; scan for ';'
    mov     r11, r9
    inc     r11

.xu_find_semi:
    cmp     r11, r12
    jae     .xu_pass_amp

    mov     rax, r11
    sub     rax, r9
    cmp     rax, 16
    ja      .xu_pass_amp        ; entity name too long -> treat '&' as literal

    movzx   ecx, byte [rbx + r11]
    cmp     cl, ';'
    je      .xu_parse_entity
    inc     r11
    jmp     .xu_find_semi

.xu_parse_entity:
    ; entity from r9+1..r11-1 (r11 = ';' position)
    movzx   ecx, byte [rbx + r9 + 1]

    cmp     cl, '#'
    je      .xu_numeric

    ; calculate entity name length
    mov     rdx, r11
    sub     rdx, r9
    dec     rdx                 ; name length

    ; "amp" (3)
    cmp     rdx, 3
    jne     .xu_chk_lt
    cmp     byte [rbx + r9 + 1], 'a'
    jne     .xu_chk_lt
    cmp     byte [rbx + r9 + 2], 'm'
    jne     .xu_chk_lt
    cmp     byte [rbx + r9 + 3], 'p'
    jne     .xu_chk_lt
    mov     al, '&'
    jmp     .xu_emit_byte

.xu_chk_lt:
    cmp     rdx, 2
    jne     .xu_chk_gt
    cmp     byte [rbx + r9 + 1], 'l'
    jne     .xu_chk_gt
    cmp     byte [rbx + r9 + 2], 't'
    jne     .xu_chk_gt
    mov     al, '<'
    jmp     .xu_emit_byte

.xu_chk_gt:
    cmp     rdx, 2
    jne     .xu_chk_quot
    cmp     byte [rbx + r9 + 1], 'g'
    jne     .xu_chk_quot
    cmp     byte [rbx + r9 + 2], 't'
    jne     .xu_chk_quot
    mov     al, '>'
    jmp     .xu_emit_byte

.xu_chk_quot:
    cmp     rdx, 4
    jne     .xu_chk_apos
    cmp     byte [rbx + r9 + 1], 'q'
    jne     .xu_chk_apos
    cmp     byte [rbx + r9 + 2], 'u'
    jne     .xu_chk_apos
    cmp     byte [rbx + r9 + 3], 'o'
    jne     .xu_chk_apos
    cmp     byte [rbx + r9 + 4], 't'
    jne     .xu_chk_apos
    mov     al, '"'
    jmp     .xu_emit_byte

.xu_chk_apos:
    cmp     rdx, 4
    jne     .xu_pass_amp
    cmp     byte [rbx + r9 + 1], 'a'
    jne     .xu_pass_amp
    cmp     byte [rbx + r9 + 2], 'p'
    jne     .xu_pass_amp
    cmp     byte [rbx + r9 + 3], 'o'
    jne     .xu_pass_amp
    cmp     byte [rbx + r9 + 4], 's'
    jne     .xu_pass_amp
    mov     al, 0x27

.xu_emit_byte:
    cmp     r10, r14
    jae     .xu_overflow
    mov     [r13 + r10], al
    inc     r10
    mov     r9, r11
    inc     r9
    jmp     .xu_loop

.xu_pass_amp:
    cmp     r10, r14
    jae     .xu_overflow
    mov     byte [r13 + r10], '&'
    inc     r9
    inc     r10
    jmp     .xu_loop

.xu_numeric:
    ; &#N; or &#xN;
    movzx   ecx, byte [rbx + r9 + 2]
    xor     r8d, r8d            ; accumulator

    cmp     cl, 'x'
    je      .xu_hex_ref

    ; decimal
    mov     rcx, r9
    add     rcx, 2

.xu_dec_ref:
    cmp     rcx, r11
    jae     .xu_emit_cp
    movzx   edx, byte [rbx + rcx]
    sub     edx, '0'
    cmp     edx, 9
    ja      .xu_pass_amp
    
    ; check overflow: r8 * 10 + edx > 0x10FFFF
    mov     rax, r8
    imul    rax, rax, 10
    jc      .xu_pass_amp
    add     rax, rdx
    jc      .xu_pass_amp
    cmp     rax, 0x10FFFF
    ja      .xu_pass_amp
    mov     r8, rax

    inc     rcx
    jmp     .xu_dec_ref

.xu_hex_ref:
    mov     rcx, r9
    add     rcx, 3              ; skip &#x

.xu_hex_ref_loop:
    cmp     rcx, r11
    jae     .xu_emit_cp
    movzx   edx, byte [rbx + rcx]
    cmp     dl, '0'
    jb      .xu_pass_amp
    cmp     dl, '9'
    jbe     .xu_hex_d
    or      dl, 0x20
    cmp     dl, 'a'
    jb      .xu_pass_amp
    cmp     dl, 'f'
    ja      .xu_pass_amp
    sub     dl, 'a'
    add     dl, 10
    jmp     .xu_hex_acc

.xu_hex_d:
    sub     dl, '0'

.xu_hex_acc:
    ; check overflow: (r8 << 4) | edx > 0x10FFFF
    mov     rax, r8
    shl     rax, 4
    jc      .xu_pass_amp
    or      rax, rdx
    cmp     rax, 0x10FFFF
    ja      .xu_pass_amp
    mov     r8, rax

    inc     rcx
    jmp     .xu_hex_ref_loop

.xu_emit_cp:
    ; validate codepoint in r8d
    mov     edi, r8d
    CODEPOINT_IS_VALID edi      ; clobbers edi, sets ZF
    jz      .xu_pass_amp        ; invalid codepoint -> output literal

    ; calculate required UTF-8 bytes in EAX
    mov     eax, 1
    cmp     r8d, 0x7F
    jbe     .xu_len_ok
    inc     eax                 ; 2 bytes
    cmp     r8d, 0x7FF
    jbe     .xu_len_ok
    inc     eax                 ; 3 bytes
    cmp     r8d, 0xFFFF
    jbe     .xu_len_ok
    inc     eax                 ; 4 bytes
.xu_len_ok:
    ; check capacity: r10 + rax <= r14
    mov     rdx, r10
    add     rdx, rax
    cmp     rdx, r14
    ja      .xu_overflow

    ; save caller-saved registers we need
    push    r9
    push    r10
    push    r11

    ; call str_utf8_encode_unchecked(cp=r8d, dst=r13 + r10)
    mov     edi, r8d
    lea     rsi, [r13 + r10]
    call    str_utf8_encode_unchecked

    ; restore registers
    pop     r11
    pop     r10
    pop     r9

    add     r10, rax            ; advance dst offset (using actual written length)

    ; advance pattern past semicolon
    mov     r9, r11
    inc     r9
    jmp     .xu_loop

.xu_done:
    test    r15, r15
    jz      .xu_ok
    mov     [r15], r10

.xu_ok:
    pop_regs r15, r14, r13, r12, rbx
    ret_ok

.xu_overflow:
    pop_regs r15, r14, r13, r12, rbx
    ret_err STR_ERR_BUF_TOO_SMALL

STR_ENDFUNC str_xml_unescape
%endif ; GUARD_LIB_STR_ESCAPE_XML_ASM
