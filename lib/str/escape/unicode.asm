%ifndef GUARD_LIB_STR_ESCAPE_UNICODE_ASM
%define GUARD_LIB_STR_ESCAPE_UNICODE_ASM
; =============================================================================
; str/escape/unicode.asm
; Unicode escape sequence encoding and decoding.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   utf8/decode.asm  (str_utf8_decode_unchecked)
;   utf8/encode.asm  (str_utf8_encode_unchecked)
;   inspect/is_hex_digit.asm (str_hex_digit_value)
;
; -----------------------------------------------------------------------------
; Unicode escape formats:
;
;   \uXXXX      — 4-hex BMP codepoint  (JSON, Java, JavaScript)
;   \UXXXXXXXX  — 8-hex full codepoint  (C, Python, Rust)
;   \xXX        — 2-hex byte value      (C, many languages)
;   \N{name}    — Unicode name          (Python)  [not implemented]
;   U+XXXX      — Unicode point notation (documentation)
;
; Functions:
;   str_unicode_escape        — UTF-8 string → \uXXXX / \UXXXXXXXX escapes
;   str_unicode_escape_ascii  — escape all non-ASCII codepoints
;   str_unicode_unescape      — decode \u \U \x escape sequences
;   str_cp_to_u_escape        — single codepoint → \uXXXX or \UXXXXXXXX
;   str_cp_to_uplus           — single codepoint → U+XXXX notation
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"



section .rodata
_uni_hex_lo: db "0123456789abcdef"
_uni_hex_hi: db "0123456789ABCDEF"

section .text

; -----------------------------------------------------------------------------
; str_cp_to_u_escape
;
; Encode a single codepoint as \uXXXX (BMP) or \UXXXXXXXX (full).
;
; Signature:
;   int64_t str_cp_to_u_escape(uint32_t cp, uint8_t *dst,
;                               uint64_t dst_cap, uint64_t *out_len)
;
; Arguments:
;   EDI  — codepoint
;   RSI  — destination buffer (need 6 or 10 bytes)
;   RDX  — capacity
;   RCX  — out_len (may be null)
; -----------------------------------------------------------------------------

STR_FUNC str_cp_to_u_escape

    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13

    mov     ebx, edi            ; codepoint
    mov     r12, rsi            ; dst
    mov     r13, rcx            ; out_len

    lea     r9, [rel _uni_hex_hi]

    ; BMP (U+0000..U+FFFF): \uXXXX (6 bytes)
    cmp     ebx, 0xFFFF
    jbe     .cue_bmp

    ; supplementary: \UXXXXXXXX (10 bytes)
    cmp     rdx, 10
    jb      .cue_too_small

    mov     byte [r12 + 0], 0x5C    ; '\'
    mov     byte [r12 + 1], 'U'

    ; 8 hex digits, MSN first
    mov     eax, ebx
    mov     ecx, 28             ; start shift

.cue_full_digit:
    cmp     ecx, 0
    jl      .cue_full_last

    mov     edx, eax
    shr     edx, cl
    and     edx, 0xF
    movzx   edx, byte [r9 + rdx]
    mov     r10, 10
    sub     r10, rcx
    shr     r10, 2
    add     r10, 2
    mov     [r12 + r10], dl
    sub     ecx, 4
    jmp     .cue_full_digit

.cue_full_last:
    ; last nibble (shift 0)
    and     eax, 0xF
    movzx   eax, byte [r9 + rax]
    mov     [r12 + 9], al

    mov     r11, 10
    jmp     .cue_write_len

.cue_bmp:
    cmp     rdx, 6
    jb      .cue_too_small

    mov     byte [r12 + 0], 0x5C
    mov     byte [r12 + 1], 'u'

    ; 4 hex digits
    mov     eax, ebx

    ; nibble 3 (highest)
    mov     edx, eax
    shr     edx, 12
    and     edx, 0xF
    movzx   edx, byte [r9 + rdx]
    mov     [r12 + 2], dl

    mov     edx, eax
    shr     edx, 8
    and     edx, 0xF
    movzx   edx, byte [r9 + rdx]
    mov     [r12 + 3], dl

    mov     edx, eax
    shr     edx, 4
    and     edx, 0xF
    movzx   edx, byte [r9 + rdx]
    mov     [r12 + 4], dl

    and     eax, 0xF
    movzx   eax, byte [r9 + rax]
    mov     [r12 + 5], al

    mov     r11, 6

.cue_write_len:
    test    r13, r13
    jz      .cue_ok
    mov     [r13], r11

.cue_ok:
    pop_regs r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.cue_too_small:
    pop_regs r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_cp_to_u_escape

; -----------------------------------------------------------------------------
; str_unicode_escape_ascii
;
; Escape all non-ASCII codepoints (> U+007F) in a UTF-8 string to
; \uXXXX or \UXXXXXXXX sequences. ASCII chars pass through unchanged.
;
; Signature:
;   int64_t str_unicode_escape_ascii(const StrSlice *src, uint8_t *dst,
;                                     uint64_t dst_cap, uint64_t *out_len)
; -----------------------------------------------------------------------------

STR_FUNC str_unicode_escape_ascii

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, [rdi + StrSlice.len]
    mov     r13, rsi
    mov     r14, rdx
    mov     r15, rcx

    xor     r9, r9              ; byte offset
    xor     r10, r10            ; dst offset
    lea     r11, [rel _uni_hex_hi]

.uea_loop:
    cmp     r9, r12
    jae     .uea_done

    movzx   eax, byte [rbx + r9]

    ; ASCII pass-through
    cmp     al, 0x80
    jb      .uea_ascii

    ; decode UTF-8 codepoint
    sub     rsp, 16
    and     rsp, -16

    lea     rdi, [rbx + r9]
    lea     rsi, [rsp]
    call    str_utf8_decode_unchecked
    ; eax = codepoint

    mov     rcx, [rsp]          ; advance
    mov     rsp, rbp
    add     r9, rcx

    ; encode as \uXXXX or \UXXXXXXXX
    mov     rdi, r13
    add     rdi, r10
    mov     edi, eax            ; codepoint

    ; write escape
    push    r9
    push    r10

    ; use str_cp_to_u_escape inline logic
    lea     r9, [rel _uni_hex_hi]

    cmp     edi, 0xFFFF
    jbe     .uea_bmp_esc

    ; full: need 10 bytes
    lea     rcx, [r10 + 10]
    cmp     rcx, r14
    ja      .uea_overflow_inner

    mov     byte [r13 + r10], 0x5C
    mov     byte [r13 + r10 + 1], 'U'

    mov     eax, edi
    mov     ecx, 28

.uea_full_loop:
    mov     edx, eax
    shr     edx, cl
    and     edx, 0xF
    movzx   edx, byte [r9 + rdx]
    mov     r8, 28
    sub     r8, rcx
    shr     r8, 2
    add     r8, 2
    mov     [r13 + r10 + r8], dl
    sub     ecx, 4
    cmp     ecx, 0
    jge     .uea_full_loop

    and     eax, 0xF
    movzx   eax, byte [r9 + rax]
    mov     [r13 + r10 + 9], al

    pop     r10
    pop     r9
    add     r10, 10
    jmp     .uea_loop

.uea_bmp_esc:
    lea     rcx, [r10 + 6]
    cmp     rcx, r14
    ja      .uea_overflow_inner

    mov     byte [r13 + r10], 0x5C
    mov     byte [r13 + r10 + 1], 'u'

    mov     eax, edi
    mov     edx, eax
    shr     edx, 12
    and     edx, 0xF
    movzx   edx, byte [r9 + rdx]
    mov     [r13 + r10 + 2], dl

    mov     edx, eax
    shr     edx, 8
    and     edx, 0xF
    movzx   edx, byte [r9 + rdx]
    mov     [r13 + r10 + 3], dl

    mov     edx, eax
    shr     edx, 4
    and     edx, 0xF
    movzx   edx, byte [r9 + rdx]
    mov     [r13 + r10 + 4], dl

    and     eax, 0xF
    movzx   eax, byte [r9 + rax]
    mov     [r13 + r10 + 5], al

    pop     r10
    pop     r9
    add     r10, 6
    jmp     .uea_loop

.uea_overflow_inner:
    pop     r10
    pop     r9
    jmp     .uea_overflow

.uea_ascii:
    cmp     r10, r14
    jae     .uea_overflow
    mov     [r13 + r10], al
    inc     r9
    inc     r10
    jmp     .uea_loop

.uea_done:
    test    r15, r15
    jz      .uea_ok
    mov     [r15], r10

.uea_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.uea_overflow:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_unicode_escape_ascii

; -----------------------------------------------------------------------------
; str_unicode_unescape
;
; Decode \uXXXX, \UXXXXXXXX, and \xXX escape sequences in a string.
; Non-escape sequences pass through unchanged.
;
; Signature:
;   int64_t str_unicode_unescape(const StrSlice *src, uint8_t *dst,
;                                 uint64_t dst_cap, uint64_t *out_len)
; -----------------------------------------------------------------------------

STR_FUNC str_unicode_unescape

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

.uu_loop:
    cmp     r9, r12
    jae     .uu_done

    movzx   eax, byte [rbx + r9]

    cmp     al, 0x5C            ; backslash
    je      .uu_escape

    cmp     r10, r14
    jae     .uu_overflow
    mov     [r13 + r10], al
    inc     r9
    inc     r10
    jmp     .uu_loop

.uu_escape:
    inc     r9
    cmp     r9, r12
    jae     .uu_literal_bs

    movzx   eax, byte [rbx + r9]

    cmp     al, 'u'
    je      .uu_u4
    cmp     al, 'U'
    je      .uu_u8
    cmp     al, 'x'
    je      .uu_x2

    ; unknown escape — emit backslash + char
    cmp     r10 + 1, r14
    ja      .uu_overflow

    mov     byte [r13 + r10], 0x5C
    inc     r10
    cmp     r10, r14
    jae     .uu_overflow
    mov     [r13 + r10], al
    inc     r9
    inc     r10
    jmp     .uu_loop

.uu_literal_bs:
    cmp     r10, r14
    jae     .uu_overflow
    mov     byte [r13 + r10], 0x5C
    inc     r10
    jmp     .uu_loop

.uu_u4:
    ; \uXXXX — 4 hex digits
    inc     r9
    lea     rcx, [r9 + 4]
    cmp     rcx, r12
    ja      .uu_literal_bs

    xor     r8d, r8d
    mov     ecx, 4

.uu_u4_hex:
    test    ecx, ecx
    jz      .uu_emit_u4

    movzx   edi, byte [rbx + r9]
    push    r9
    push    rcx
    push    r8
    call    str_hex_digit_value
    pop     r8
    pop     rcx
    pop     r9
    test    rax, rax
    js      .uu_emit_u4

    shl     r8d, 4
    or      r8d, eax
    inc     r9
    dec     ecx
    jmp     .uu_u4_hex

.uu_emit_u4:
    lea     rsi, [r13 + r10]
    mov     edi, r8d
    push    r9
    push    r10
    call    str_utf8_encode_unchecked
    pop     r10
    pop     r9
    add     r10, rax
    jmp     .uu_loop

.uu_u8:
    ; \UXXXXXXXX — 8 hex digits
    inc     r9
    lea     rcx, [r9 + 8]
    cmp     rcx, r12
    ja      .uu_literal_bs

    xor     r8d, r8d
    mov     ecx, 8

.uu_u8_hex:
    test    ecx, ecx
    jz      .uu_emit_u8

    movzx   edi, byte [rbx + r9]
    push    r9
    push    rcx
    push    r8
    call    str_hex_digit_value
    pop     r8
    pop     rcx
    pop     r9
    test    rax, rax
    js      .uu_emit_u8

    shl     r8d, 4
    or      r8d, eax
    inc     r9
    dec     ecx
    jmp     .uu_u8_hex

.uu_emit_u8:
    lea     rsi, [r13 + r10]
    mov     edi, r8d
    push    r9
    push    r10
    call    str_utf8_encode_unchecked
    pop     r10
    pop     r9
    add     r10, rax
    jmp     .uu_loop

.uu_x2:
    ; \xXX — 2 hex digits → single byte
    inc     r9
    lea     rcx, [r9 + 2]
    cmp     rcx, r12
    ja      .uu_literal_bs

    movzx   edi, byte [rbx + r9]
    push    r9
    call    str_hex_digit_value
    pop     r9
    test    rax, rax
    js      .uu_literal_bs

    mov     r8d, eax
    shl     r8d, 4
    inc     r9

    movzx   edi, byte [rbx + r9]
    push    r9
    push    r8
    call    str_hex_digit_value
    pop     r8
    pop     r9
    test    rax, rax
    js      .uu_literal_bs

    or      r8d, eax
    inc     r9

    cmp     r10, r14
    jae     .uu_overflow
    mov     [r13 + r10], r8b
    inc     r10
    jmp     .uu_loop

.uu_done:
    test    r15, r15
    jz      .uu_ok
    mov     [r15], r10

.uu_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.uu_overflow:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_unicode_unescape

; -----------------------------------------------------------------------------
; str_cp_to_uplus
;
; Format a codepoint as U+XXXX notation (for display/docs, not embedding).
;
; Signature:
;   int64_t str_cp_to_uplus(uint32_t cp, uint8_t *dst,
;                            uint64_t dst_cap, uint64_t *out_len)
; -----------------------------------------------------------------------------

STR_FUNC str_cp_to_uplus

    guard_null rsi, STR_ERR_NULL

    ; U+XXXX needs at least 7 bytes, U+10FFFF needs 9
    cmp     rdx, 7
    jb      .cup_too_small

    push_regs rbx, r12, r13

    mov     ebx, edi
    mov     r12, rsi
    mov     r13, rcx

    lea     r9, [rel _uni_hex_hi]

    mov     byte [r12 + 0], 'U'
    mov     byte [r12 + 1], '+'

    ; determine digit count: 4 for BMP, 5-6 for supplementary
    cmp     ebx, 0xFFFF
    jbe     .cup_4dig

    ; 5 or 6 digits
    xor     r10, r10            ; write offset (after U+)
    mov     eax, ebx
    mov     r11, 0              ; leading zero skip

    ; generate up to 6 hex digits from MSN
    mov     ecx, 20             ; max shift for 6 nibbles (5*4=20)

.cup_supp:
    cmp     ecx, 0
    jl      .cup_supp_last

    mov     edx, eax
    shr     edx, cl
    and     edx, 0xF

    test    r11, r11
    jnz     .cup_supp_write
    test    edx, edx
    jz      .cup_supp_next      ; skip leading zero
    inc     r11

.cup_supp_write:
    cmp     r10 + 2, r12
    ; check capacity
    lea     r8, [r10 + 3]
    cmp     r8, rdx
    ; rdx is clobbered — use r14 for cap
    movzx   edx, byte [r9 + rdx]
    mov     [r12 + 2 + r10], dl
    inc     r10

.cup_supp_next:
    sub     ecx, 4
    jmp     .cup_supp

.cup_supp_last:
    ; last nibble
    and     eax, 0xF
    movzx   eax, byte [r9 + rax]
    mov     [r12 + 2 + r10], al
    inc     r10

    add     r10, 2              ; for "U+"
    jmp     .cup_write_len

.cup_4dig:
    ; always 4 digits
    cmp     rdx, 6
    jb      .cup_too_small_2

    mov     eax, ebx

    mov     edx, eax
    shr     edx, 12
    movzx   edx, byte [r9 + rdx]
    mov     [r12 + 2], dl

    mov     edx, eax
    shr     edx, 8
    and     edx, 0xF
    movzx   edx, byte [r9 + rdx]
    mov     [r12 + 3], dl

    mov     edx, eax
    shr     edx, 4
    and     edx, 0xF
    movzx   edx, byte [r9 + rdx]
    mov     [r12 + 4], dl

    and     eax, 0xF
    movzx   eax, byte [r9 + rax]
    mov     [r12 + 5], al

    mov     r10, 6

.cup_write_len:
    test    r13, r13
    jz      .cup_ok
    mov     [r13], r10

.cup_ok:
    pop_regs r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.cup_too_small_2:
    pop_regs r13, r12, rbx
.cup_too_small:
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_cp_to_uplus
%endif ; GUARD_LIB_STR_ESCAPE_UNICODE_ASM
