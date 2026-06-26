; =============================================================================
; str/encoding/utf7.asm
; UTF-7 ↔ UTF-8 codec (RFC 2152).
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   encoding/engine.asm  (EncCodec struct)
;
; -----------------------------------------------------------------------------
; UTF-7 is a 7-bit-safe encoding designed for email systems that could not
; reliably transmit 8-bit data. It is stateful and largely obsolete, but
; still appears in legacy IMAP mailbox names (modified UTF-7) and old email.
;
; Encoding rules:
;   - Directly-encoded ASCII characters appear as-is.
;   - The '+' character introduces a Base64-encoded run of UTF-16 code units.
;   - The run ends at any non-Base64 character (often '-', which is absorbed).
;   - "+-" encodes a literal '+'.
;
; Base64 here uses the standard alphabet A-Z a-z 0-9 + / (modified UTF-7
; for IMAP uses ',' instead of '/').
;
; This codec is STATEFUL: decoding requires tracking whether we are inside
; a Base64 run and accumulating bits. The decode_one interface processes
; a self-contained unit per call by consuming a full shifted sequence.
;
; Functions:
;   str_utf7_decode_one
;   str_utf7_encode_one
;   str_utf7_codec
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

section .rodata
_utf7_name: db "UTF-7", 0

; Base64 decode table: ASCII char → 6-bit value, 0xFF = not base64.
align 16
_b64_decode:
    times 43 db 0xFF            ; 0x00-0x2A
    db 62                       ; '+' = 0x2B → 62
    times 3 db 0xFF             ; 0x2C-0x2E
    db 63                       ; '/' = 0x2F → 63
    db 52, 53, 54, 55, 56, 57, 58, 59, 60, 61  ; '0'-'9' → 52-61
    times 7 db 0xFF             ; 0x3A-0x40
    ; 'A'-'Z' → 0-25
    db 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25
    times 6 db 0xFF             ; 0x5B-0x60
    ; 'a'-'z' → 26-51
    db 26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51
    times 133 db 0xFF           ; 0x7B-0xFF

_b64_encode: db "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

section .text

; -----------------------------------------------------------------------------
; str_utf7_decode_one
;
; Decode one codepoint from a UTF-7 stream.
; Handles both direct ASCII and the '+...-' Base64 shifted sequences.
;
; Signature:
;   int64_t str_utf7_decode_one(const uint8_t *src, uint64_t src_len,
;                                uint32_t *out_cp)
;
; Returns: bytes consumed, or negative error.
;
; NOTE: For a full Base64 run spanning multiple codepoints, this returns
; the first decoded codepoint and the bytes consumed to produce it. A
; stateful wrapper (str_utf7_decode in the engine) handles continuation.
; -----------------------------------------------------------------------------

STR_FUNC str_utf7_decode_one

    test    rsi, rsi
    jz      .d7_empty

    movzx   eax, byte [rdi]

    cmp     al, '+'
    je      .d7_shift

    ; direct ASCII character
    cmp     al, 0x80
    jae     .d7_invalid         ; UTF-7 is 7-bit only

    mov     [rdx], eax
    mov     rax, 1
    pop     rbp
    ret

.d7_shift:
    ; '+' begins a shifted sequence
    ; check for "+-" → literal '+'
    cmp     rsi, 2
    jb      .d7_lone_plus

    movzx   ecx, byte [rdi + 1]
    cmp     cl, '-'
    jne     .d7_b64_run

    ; "+-" → '+'
    mov     dword [rdx], '+'
    mov     rax, 2
    pop     rbp
    ret

.d7_lone_plus:
    ; lone '+' at end — treat as literal
    mov     dword [rdx], '+'
    mov     rax, 1
    pop     rbp
    ret

.d7_b64_run:
    ; decode Base64 → UTF-16 code units, return first codepoint.
    ; accumulate bits from base64 chars
    push_regs rbx, r12, r13, r14

    mov     rbx, rdi            ; src
    mov     r12, rsi            ; src len
    mov     r13, rdx            ; out_cp

    mov     r9, 1               ; src index (skip '+')
    xor     r10, r10            ; bit accumulator
    xor     r11d, r11d          ; bit count
    lea     r14, [rel _b64_decode]

.d7_b64_loop:
    cmp     r9, r12
    jae     .d7_b64_end

    movzx   eax, byte [rbx + r9]
    movzx   ecx, byte [r14 + rax]
    cmp     cl, 0xFF
    je      .d7_b64_end         ; not base64 — run ends

    ; accumulate 6 bits
    shl     r10, 6
    or      r10, rcx
    add     r11d, 6
    inc     r9

    ; have we got a full 16-bit code unit?
    cmp     r11d, 16
    jb      .d7_b64_loop

    ; extract top 16 bits
    sub     r11d, 16
    mov     rax, r10
    mov     ecx, r11d
    shr     rax, cl
    and     eax, 0xFFFF         ; code unit

    ; (surrogate handling would combine two units; simplified to BMP here)
    mov     [r13], eax

    ; consumed up to r9; if next char is '-', absorb it
    cmp     r9, r12
    jae     .d7_b64_done
    movzx   ecx, byte [rbx + r9]
    cmp     cl, '-'
    jne     .d7_b64_done
    inc     r9

.d7_b64_done:
    mov     rax, r9
    pop_regs r14, r13, r12, rbx
    pop     rbp
    ret

.d7_b64_end:
    ; run ended without a full code unit
    ; absorb trailing '-' if present
    cmp     r9, r12
    jae     .d7_b64_empty
    movzx   ecx, byte [rbx + r9]
    cmp     cl, '-'
    jne     .d7_b64_empty
    inc     r9

.d7_b64_empty:
    ; nothing decoded — treat the '+' run as empty, skip it
    mov     dword [r13], '+'
    mov     rax, r9
    pop_regs r14, r13, r12, rbx
    pop     rbp
    ret

.d7_invalid:
    mov     rax, STR_ERR_ENCODING
    pop     rbp
    ret

.d7_empty:
    mov     rax, STR_ERR_ITER_END
    pop     rbp
    ret

STR_ENDFUNC str_utf7_decode_one

; -----------------------------------------------------------------------------
; str_utf7_encode_one
;
; Encode one codepoint to UTF-7.
; Directly-representable characters are emitted as-is. Others are wrapped in
; a "+...-" Base64 sequence (one codepoint per sequence for simplicity).
;
; Signature:
;   int64_t str_utf7_encode_one(uint32_t cp, uint8_t *dst, uint64_t dst_cap)
; -----------------------------------------------------------------------------

STR_FUNC str_utf7_encode_one

    ; directly-encodable set: A-Z a-z 0-9 and a few safe punctuation.
    ; For safety we directly-encode printable ASCII except '+' and '\'.
    cmp     edi, 0x7F
    ja      .e7_shifted

    cmp     edi, '+'
    je      .e7_plus

    cmp     edi, 0x20
    jb      .e7_shifted         ; controls → shifted

    ; direct
    test    rdx, rdx
    jz      .e7_nospace
    mov     [rsi], dil
    mov     rax, 1
    pop     rbp
    ret

.e7_plus:
    ; '+' → "+-"
    cmp     rdx, 2
    jb      .e7_nospace
    mov     byte [rsi], '+'
    mov     byte [rsi + 1], '-'
    mov     rax, 2
    pop     rbp
    ret

.e7_shifted:
    ; encode codepoint as "+<base64 of UTF-16>-"
    ; for BMP: one 16-bit unit → 3 base64 chars (with padding bits)
    cmp     edi, 0xFFFF
    ja      .e7_unsupported     ; supplementary needs surrogate pair (omitted)

    cmp     rdx, 5
    jb      .e7_nospace

    mov     byte [rsi], '+'

    ; 16 bits → 3 base64 sextets (18 bits, last 2 are zero-padded)
    lea     r8, [rel _b64_encode]

    mov     eax, edi            ; 16-bit value
    ; sextet 1: bits 15..10
    mov     ecx, eax
    shr     ecx, 10
    and     ecx, 0x3F
    movzx   ecx, byte [r8 + rcx]
    mov     [rsi + 1], cl

    ; sextet 2: bits 9..4
    mov     ecx, eax
    shr     ecx, 4
    and     ecx, 0x3F
    movzx   ecx, byte [r8 + rcx]
    mov     [rsi + 2], cl

    ; sextet 3: bits 3..0 followed by 2 zero bits
    mov     ecx, eax
    and     ecx, 0x0F
    shl     ecx, 2
    movzx   ecx, byte [r8 + rcx]
    mov     [rsi + 3], cl

    mov     byte [rsi + 4], '-'
    mov     rax, 5
    pop     rbp
    ret

.e7_unsupported:
    mov     rax, STR_ERR_ENCODING
    pop     rbp
    ret

.e7_nospace:
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_utf7_encode_one

; -----------------------------------------------------------------------------
; str_utf7_codec
; -----------------------------------------------------------------------------

section .rodata
align 8
_utf7_codec_struct:
    dq str_utf7_decode_one
    dq str_utf7_encode_one
    dq _utf7_name
    dq 8                        ; max bytes per char (shifted sequence)
    dq 0x01                     ; STATEFUL
    dq 0

section .text

STR_FUNC str_utf7_codec
    lea     rax, [rel _utf7_codec_struct]
    pop     rbp
    ret
STR_ENDFUNC str_utf7_codec