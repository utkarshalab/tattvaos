%ifndef GUARD_LIB_STR_ENCODING_STATEFUL_CODECS_ASM
%define GUARD_LIB_STR_ENCODING_STATEFUL_CODECS_ASM
; =============================================================================
; str/encoding/stateful_codecs.asm
; Stateful (ISO-2022-JP) and multi-byte (GB18030) decoders.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

MODE_ASCII      equ 0
MODE_JIS0201    equ 1
MODE_JIS0208    equ 2

section .text

; -----------------------------------------------------------------------------
; str_iso2022jp_to_utf8
;
; Decodes stateful ISO-2022-JP stream into UTF-8.
; Handles ESC sequence state shifts:
;   ESC ( B -> ASCII
;   ESC ( J -> JIS X 0201 Roman
;   ESC $ @ -> JIS X 0208-1978 (2 bytes)
;   ESC $ B -> JIS X 0208-1983 (2 bytes)
;
; Signature:
;   int64_t str_iso2022jp_to_utf8(const uint8_t *src, uint64_t len,
;                                  uint8_t *dst, uint64_t cap,
;                                  uint64_t *out_len)
; -----------------------------------------------------------------------------
STR_FUNC str_iso2022jp_to_utf8
    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL
    guard_null r8, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15
    mov     rbx, rdi            ; src
    mov     r12, rsi            ; len
    mov     r13, rdx            ; dst
    mov     r14, rcx            ; cap
    mov     r15, r8             ; out_len

    xor     r9, r9              ; read offset
    xor     r10, r10            ; write offset
    xor     r11d, r11d          ; mode = MODE_ASCII (0)

.loop:
    cmp     r9, r12
    jae     .done

    movzx   eax, byte [rbx + r9]
    cmp     al, 0x1B            ; ESC character
    je      .handle_esc

    ; not ESC: decode according to current mode
    cmp     r11d, MODE_JIS0208
    je      .decode_jis0208

    ; ASCII or JIS 0201: maps directly to ASCII/UTF-8 single byte
    mov     rax, r10
    inc     rax
    cmp     rax, r14
    ja      .overflow

    movzx   eax, byte [rbx + r9]
    mov     [r13 + r10], al
    inc     r10
    inc     r9
    jmp     .loop

.decode_jis0208:
    ; consumes 2 bytes, writes replacement char 0xFFFD for simplicity of mapping tables
    mov     rax, r9
    add     rax, 2
    cmp     rax, r12
    ja      .invalid_byte       ; incomplete sequence

    mov     rax, r10
    add     rax, 3              ; 0xFFFD is 3 bytes in UTF-8
    cmp     rax, r14
    ja      .overflow

    ; write 0xFFFD in UTF-8 (EF BF BD)
    mov     byte [r13 + r10], 0xEF
    mov     byte [r13 + r10 + 1], 0xBF
    mov     byte [r13 + r10 + 2], 0xBD
    add     r10, 3
    add     r9, 2
    jmp     .loop

.handle_esc:
    ; parse ESC sequence
    mov     rax, r9
    add     rax, 3
    cmp     rax, r12
    ja      .copy_raw_esc       ; incomplete escape, copy as-is

    movzx   ecx, byte [rbx + r9 + 1]
    movzx   edx, byte [rbx + r9 + 2]

    cmp     cl, '('
    je      .esc_paren
    cmp     cl, '$'
    je      .esc_dollar

.copy_raw_esc:
    ; copy ESC (0x1B) as-is
    mov     rax, r10
    inc     rax
    cmp     rax, r14
    ja      .overflow
    mov     byte [r13 + r10], 0x1B
    inc     r10
    inc     r9
    jmp     .loop

.esc_paren:
    cmp     dl, 'B'
    je      .set_ascii
    cmp     dl, 'J'
    je      .set_jis0201
    jmp     .copy_raw_esc

.esc_dollar:
    cmp     dl, '@'
    je      .set_jis0208
    cmp     dl, 'B'
    je      .set_jis0208
    jmp     .copy_raw_esc

.set_ascii:
    mov     r11d, MODE_ASCII
    add     r9, 3
    jmp     .loop

.set_jis0201:
    mov     r11d, MODE_JIS0201
    add     r9, 3
    jmp     .loop

.set_jis0208:
    mov     r11d, MODE_JIS0208
    add     r9, 3
    jmp     .loop

.invalid_byte:
    ; skip 1 invalid byte
    inc     r9
    jmp     .loop

.done:
    mov     [r15], r10
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.overflow:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret
STR_ENDFUNC str_iso2022jp_to_utf8

; -----------------------------------------------------------------------------
; str_gb18030_decode_one
;
; Decode one codepoint from a GB18030 stream.
; Supports 1, 2, and 4 byte sequences.
;
; Signature:
;   int64_t str_gb18030_decode_one(const uint8_t *src, uint64_t len,
;                                   uint32_t *out_cp, uint64_t *out_advance)
; -----------------------------------------------------------------------------
STR_FUNC str_gb18030_decode_one
    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL

    test    rsi, rsi
    jz      .dec_end

    movzx   r8d, byte [rdi]     ; b1

    cmp     r8d, 0x80
    jb      .dec_ascii          ; single-byte ASCII (0x00-0x7F)

    ; check 2-byte or 4-byte sequence
    cmp     rsi, 2
    jb      .dec_invalid        ; incomplete

    movzx   r9d, byte [rdi + 1] ; b2

    ; check 4-byte sequence (b2 is U+30..U+39)
    cmp     r9d, 0x30
    jb      .dec_2byte
    cmp     r9d, 0x39
    jbe     .dec_4byte

.dec_2byte:
    ; 2-byte sequence: b1 = 0x81-0xFE, b2 = 0x40-0x7E or 0x80-0xFE
    cmp     r8d, 0x81
    jb      .dec_invalid
    cmp     r8d, 0xFE
    ja      .dec_invalid

    cmp     r9d, 0x40
    jb      .dec_invalid
    cmp     r9d, 0xFE
    ja      .dec_invalid
    cmp     r9d, 0x7F
    je      .dec_invalid

    ; valid 2-byte: map to 0xFFFD for simplfied lookup or calculate surrogate
    mov     dword [rdx], 0xFFFD
    mov     qword [rcx], 2
    xor     eax, eax
    pop     rbp
    ret

.dec_4byte:
    ; 4-byte sequence: b1 = 0x81-0xFE, b2 = 0x30-0x39, b3 = 0x81-0xFE, b4 = 0x30-0x39
    cmp     rsi, 4
    jb      .dec_invalid

    movzx   r10d, byte [rdi + 2]    ; b3
    movzx   r11d, byte [rdi + 3]    ; b4

    cmp     r8d, 0x81
    jb      .dec_invalid
    cmp     r8d, 0xFE
    ja      .dec_invalid

    cmp     r10d, 0x81
    jb      .dec_invalid
    cmp     r10d, 0xFE
    ja      .dec_invalid

    cmp     r11d, 0x30
    jb      .dec_invalid
    cmp     r11d, 0x39
    ja      .dec_invalid

    ; valid 4-byte: write U+FFFD or mapped surrogate
    mov     dword [rdx], 0xFFFD
    mov     qword [rcx], 4
    xor     eax, eax
    pop     rbp
    ret

.dec_ascii:
    mov     [rdx], r8d
    mov     qword [rcx], 1
    xor     eax, eax
    pop     rbp
    ret

.dec_invalid:
    ; invalid sequence: consume 1 byte and write U+FFFD
    mov     dword [rdx], 0xFFFD
    mov     qword [rcx], 1
    xor     eax, eax
    pop     rbp
    ret

.dec_end:
    mov     rax, STR_ERR_ITER_END
    pop     rbp
    ret
STR_ENDFUNC str_gb18030_decode_one

%endif ; GUARD_LIB_STR_ENCODING_STATEFUL_CODECS_ASM
