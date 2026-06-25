; =============================================================================
; str/escape/url.asm
; URL percent-encoding (RFC 3986) encode and decode.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   inspect/is_hex_digit.asm  (str_hex_digit_value)
;
; -----------------------------------------------------------------------------
; Percent-encoding: replace non-unreserved bytes with %XX hex sequences.
;
; Unreserved characters (RFC 3986 §2.3) — never encoded:
;   A-Z a-z 0-9 - _ . ~
;
; Two modes:
;   URL encode  — encode everything except unreserved
;   Form encode — like URL but ' ' → '+' (application/x-www-form-urlencoded)
;
; Functions:
;   str_url_encode         — percent-encode a StrSlice
;   str_url_encode_form    — form-encode (space → +)
;   str_url_decode         — percent-decode %XX sequences
;   str_url_decode_form    — form-decode (+ → space)
;   str_url_encode_path    — encode path component (preserve /)
;   str_url_encode_query   — encode query component (preserve = & ?)
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_hex_digit_value

section .rodata

_url_hex: db "0123456789ABCDEF"

; Unreserved character lookup table: 1 = safe, 0 = must encode
; Index 0..127 covering ASCII
_url_unreserved:
    times 256 db 0              ; default: encode everything

section .text

; Initialize unreserved table at module load — or use compile-time table.
; Here we use a precomputed table via a macro approach.

; Simpler: inline check in encode loop

; Safe byte check: A-Z a-z 0-9 - _ . ~
%macro IS_URL_SAFE 1        ; %1 = byte reg (8-bit)
    ; sets ZF if safe (unreserved), clears if must-encode
    ; A-Z
    cmp     %1, 'A'
    jb      %%check_lower
    cmp     %1, 'Z'
    jbe     %%safe
%%check_lower:
    cmp     %1, 'a'
    jb      %%check_digit
    cmp     %1, 'z'
    jbe     %%safe
%%check_digit:
    cmp     %1, '0'
    jb      %%check_special
    cmp     %1, '9'
    jbe     %%safe
%%check_special:
    cmp     %1, '-'
    je      %%safe
    cmp     %1, '_'
    je      %%safe
    cmp     %1, '.'
    je      %%safe
    cmp     %1, '~'
    je      %%safe
    ; not safe
    jmp     %%done
%%safe:
    ; set ZF by comparing equal value
%%done:
%endmacro

section .text

; -----------------------------------------------------------------------------
; str_url_encode
;
; Percent-encode a string. Unreserved chars pass through, all others → %XX.
;
; Signature:
;   int64_t str_url_encode(const StrSlice *src, uint8_t *dst,
;                           uint64_t dst_cap, uint64_t *out_len)
;
; Arguments:
;   RDI  — source StrSlice
;   RSI  — destination buffer
;   RDX  — capacity (worst case: src_len * 3)
;   RCX  — out_len (may be null)
; -----------------------------------------------------------------------------

STR_FUNC str_url_encode

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
    lea     r11, [rel _url_hex]

.ue_loop:
    cmp     r9, r12
    jae     .ue_done

    movzx   eax, byte [rbx + r9]
    inc     r9

    ; check if unreserved
    ; A-Z
    cmp     al, 'A'
    jb      .ue_chk_lower
    cmp     al, 'Z'
    jbe     .ue_safe
.ue_chk_lower:
    cmp     al, 'a'
    jb      .ue_chk_digit
    cmp     al, 'z'
    jbe     .ue_safe
.ue_chk_digit:
    cmp     al, '0'
    jb      .ue_chk_special
    cmp     al, '9'
    jbe     .ue_safe
.ue_chk_special:
    cmp     al, '-'
    je      .ue_safe
    cmp     al, '_'
    je      .ue_safe
    cmp     al, '.'
    je      .ue_safe
    cmp     al, '~'
    je      .ue_safe

    ; must encode as %XX
    ; need 3 bytes
    lea     rcx, [r10 + 3]
    cmp     rcx, r14
    ja      .ue_overflow

    mov     byte [r13 + r10], '%'
    inc     r10

    ; high nibble
    mov     ecx, eax
    shr     ecx, 4
    movzx   ecx, byte [r11 + rcx]
    mov     [r13 + r10], cl
    inc     r10

    ; low nibble
    and     eax, 0xF
    movzx   eax, byte [r11 + rax]
    mov     [r13 + r10], al
    inc     r10
    jmp     .ue_loop

.ue_safe:
    cmp     r10, r14
    jae     .ue_overflow
    mov     [r13 + r10], al
    inc     r10
    jmp     .ue_loop

.ue_done:
    test    r15, r15
    jz      .ue_ok
    mov     [r15], r10

.ue_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.ue_overflow:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_url_encode

; -----------------------------------------------------------------------------
; str_url_encode_form
;
; Form-encode: like url_encode but space → '+'.
; -----------------------------------------------------------------------------

STR_FUNC str_url_encode_form

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
    lea     r11, [rel _url_hex]

.uef_loop:
    cmp     r9, r12
    jae     .uef_done

    movzx   eax, byte [rbx + r9]
    inc     r9

    ; space → '+'
    cmp     al, ' '
    jne     .uef_not_space
    cmp     r10, r14
    jae     .uef_overflow
    mov     byte [r13 + r10], '+'
    inc     r10
    jmp     .uef_loop

.uef_not_space:
    ; unreserved check
    cmp     al, 'A'
    jb      .uef_chk_lower
    cmp     al, 'Z'
    jbe     .uef_safe
.uef_chk_lower:
    cmp     al, 'a'
    jb      .uef_chk_digit
    cmp     al, 'z'
    jbe     .uef_safe
.uef_chk_digit:
    cmp     al, '0'
    jb      .uef_chk_special
    cmp     al, '9'
    jbe     .uef_safe
.uef_chk_special:
    cmp     al, '-'
    je      .uef_safe
    cmp     al, '_'
    je      .uef_safe
    cmp     al, '.'
    je      .uef_safe
    cmp     al, '~'
    je      .uef_safe

    ; encode %XX
    lea     rcx, [r10 + 3]
    cmp     rcx, r14
    ja      .uef_overflow
    mov     byte [r13 + r10], '%'
    inc     r10
    mov     ecx, eax
    shr     ecx, 4
    movzx   ecx, byte [r11 + rcx]
    mov     [r13 + r10], cl
    inc     r10
    and     eax, 0xF
    movzx   eax, byte [r11 + rax]
    mov     [r13 + r10], al
    inc     r10
    jmp     .uef_loop

.uef_safe:
    cmp     r10, r14
    jae     .uef_overflow
    mov     [r13 + r10], al
    inc     r10
    jmp     .uef_loop

.uef_done:
    test    r15, r15
    jz      .uef_ok
    mov     [r15], r10

.uef_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.uef_overflow:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_url_encode_form

; -----------------------------------------------------------------------------
; str_url_decode
;
; Decode percent-encoded string. %XX → byte.
;
; Signature:
;   int64_t str_url_decode(const StrSlice *src, uint8_t *dst,
;                           uint64_t dst_cap, uint64_t *out_len)
; -----------------------------------------------------------------------------

STR_FUNC str_url_decode

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

.ud_loop:
    cmp     r9, r12
    jae     .ud_done

    movzx   eax, byte [rbx + r9]

    cmp     al, '%'
    je      .ud_encoded

    ; regular byte
    cmp     r10, r14
    jae     .ud_overflow
    mov     [r13 + r10], al
    inc     r9
    inc     r10
    jmp     .ud_loop

.ud_encoded:
    ; need %XX — two more bytes
    lea     rcx, [r9 + 3]
    cmp     rcx, r12
    ja      .ud_literal_pct     ; not enough chars → keep literal

    ; decode high nibble
    movzx   edi, byte [rbx + r9 + 1]
    push    r9
    push    r10
    call    str_hex_digit_value
    pop     r10
    pop     r9
    test    rax, rax
    js      .ud_literal_pct

    mov     r8d, eax
    shl     r8d, 4

    ; decode low nibble
    movzx   edi, byte [rbx + r9 + 2]
    push    r9
    push    r10
    push    r8
    call    str_hex_digit_value
    pop     r8
    pop     r10
    pop     r9
    test    rax, rax
    js      .ud_literal_pct

    or      r8d, eax

    cmp     r10, r14
    jae     .ud_overflow
    mov     [r13 + r10], r8b
    add     r9, 3
    inc     r10
    jmp     .ud_loop

.ud_literal_pct:
    cmp     r10, r14
    jae     .ud_overflow
    mov     byte [r13 + r10], '%'
    inc     r9
    inc     r10
    jmp     .ud_loop

.ud_done:
    test    r15, r15
    jz      .ud_ok
    mov     [r15], r10

.ud_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.ud_overflow:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_url_decode

; -----------------------------------------------------------------------------
; str_url_decode_form
;
; Form-decode: like url_decode but '+' → space.
; -----------------------------------------------------------------------------

STR_FUNC str_url_decode_form

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

.udf_loop:
    cmp     r9, r12
    jae     .udf_done

    movzx   eax, byte [rbx + r9]

    cmp     al, '+'
    jne     .udf_not_plus
    cmp     r10, r14
    jae     .udf_overflow
    mov     byte [r13 + r10], ' '
    inc     r9
    inc     r10
    jmp     .udf_loop

.udf_not_plus:
    cmp     al, '%'
    jne     .udf_copy

    lea     rcx, [r9 + 3]
    cmp     rcx, r12
    ja      .udf_copy

    movzx   edi, byte [rbx + r9 + 1]
    push    r9
    push    r10
    call    str_hex_digit_value
    pop     r10
    pop     r9
    test    rax, rax
    js      .udf_copy

    mov     r8d, eax
    shl     r8d, 4

    movzx   edi, byte [rbx + r9 + 2]
    push    r9
    push    r10
    push    r8
    call    str_hex_digit_value
    pop     r8
    pop     r10
    pop     r9
    test    rax, rax
    js      .udf_copy

    or      r8d, eax
    cmp     r10, r14
    jae     .udf_overflow
    mov     [r13 + r10], r8b
    add     r9, 3
    inc     r10
    jmp     .udf_loop

.udf_copy:
    cmp     r10, r14
    jae     .udf_overflow
    mov     [r13 + r10], al
    inc     r9
    inc     r10
    jmp     .udf_loop

.udf_done:
    test    r15, r15
    jz      .udf_ok
    mov     [r15], r10

.udf_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.udf_overflow:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_url_decode_form

; -----------------------------------------------------------------------------
; str_url_encode_path
;
; Encode a URL path component. Preserves '/' between segments.
; Encodes everything else except unreserved + /
; -----------------------------------------------------------------------------

STR_FUNC str_url_encode_path

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
    lea     r11, [rel _url_hex]

.uep_loop:
    cmp     r9, r12
    jae     .uep_done

    movzx   eax, byte [rbx + r9]
    inc     r9

    ; preserve '/'
    cmp     al, '/'
    je      .uep_safe

    ; unreserved check
    cmp     al, 'A'
    jb      .uep_chk_lower_p
    cmp     al, 'Z'
    jbe     .uep_safe
.uep_chk_lower_p:
    cmp     al, 'a'
    jb      .uep_chk_digit_p
    cmp     al, 'z'
    jbe     .uep_safe
.uep_chk_digit_p:
    cmp     al, '0'
    jb      .uep_chk_sp
    cmp     al, '9'
    jbe     .uep_safe
.uep_chk_sp:
    cmp     al, '-'
    je      .uep_safe
    cmp     al, '_'
    je      .uep_safe
    cmp     al, '.'
    je      .uep_safe
    cmp     al, '~'
    je      .uep_safe
    ; also preserve ':' '@' '!' '$' '&' '\'' '(' ')' '*' '+' ',' ';' '='
    ; for sub-delims/pchar — full RFC 3986 path chars
    cmp     al, ':'
    je      .uep_safe
    cmp     al, '@'
    je      .uep_safe

    ; encode
    lea     rcx, [r10 + 3]
    cmp     rcx, r14
    ja      .uep_overflow
    mov     byte [r13 + r10], '%'
    inc     r10
    mov     ecx, eax
    shr     ecx, 4
    movzx   ecx, byte [r11 + rcx]
    mov     [r13 + r10], cl
    inc     r10
    and     eax, 0xF
    movzx   eax, byte [r11 + rax]
    mov     [r13 + r10], al
    inc     r10
    jmp     .uep_loop

.uep_safe:
    cmp     r10, r14
    jae     .uep_overflow
    mov     [r13 + r10], al
    inc     r10
    jmp     .uep_loop

.uep_done:
    test    r15, r15
    jz      .uep_ok
    mov     [r15], r10

.uep_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.uep_overflow:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_url_encode_path

; -----------------------------------------------------------------------------
; str_url_encode_query
;
; Encode a URL query string value. Preserves = & ? for structure.
; Encodes spaces and other special chars.
; -----------------------------------------------------------------------------

STR_FUNC str_url_encode_query

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
    lea     r11, [rel _url_hex]

.ueq_loop:
    cmp     r9, r12
    jae     .ueq_done

    movzx   eax, byte [rbx + r9]
    inc     r9

    ; preserve query structure chars
    cmp     al, '='
    je      .ueq_safe
    cmp     al, '&'
    je      .ueq_safe
    cmp     al, '?'
    je      .ueq_safe

    ; unreserved
    cmp     al, 'A'
    jb      .ueq_chk_l
    cmp     al, 'Z'
    jbe     .ueq_safe
.ueq_chk_l:
    cmp     al, 'a'
    jb      .ueq_chk_d
    cmp     al, 'z'
    jbe     .ueq_safe
.ueq_chk_d:
    cmp     al, '0'
    jb      .ueq_chk_s
    cmp     al, '9'
    jbe     .ueq_safe
.ueq_chk_s:
    cmp     al, '-'
    je      .ueq_safe
    cmp     al, '_'
    je      .ueq_safe
    cmp     al, '.'
    je      .ueq_safe
    cmp     al, '~'
    je      .ueq_safe

    ; encode
    lea     rcx, [r10 + 3]
    cmp     rcx, r14
    ja      .ueq_overflow
    mov     byte [r13 + r10], '%'
    inc     r10
    mov     ecx, eax
    shr     ecx, 4
    movzx   ecx, byte [r11 + rcx]
    mov     [r13 + r10], cl
    inc     r10
    and     eax, 0xF
    movzx   eax, byte [r11 + rax]
    mov     [r13 + r10], al
    inc     r10
    jmp     .ueq_loop

.ueq_safe:
    cmp     r10, r14
    jae     .ueq_overflow
    mov     [r13 + r10], al
    inc     r10
    jmp     .ueq_loop

.ueq_done:
    test    r15, r15
    jz      .ueq_ok
    mov     [r15], r10

.ueq_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.ueq_overflow:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_url_encode_query