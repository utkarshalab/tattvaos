; =============================================================================
; str/net/uri.asm
; RFC 3986 percent encoding and decoding functions.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

section .text

; Helper to check if a byte is unreserved in RFC 3986
; Unreserved: A-Z, a-z, 0-9, '-', '_', '.', '~'
_is_unreserved:
    cmp     dil, 'A'
    jb      .check_digit
    cmp     dil, 'Z'
    jbe     .yes

    cmp     dil, 'a'
    jb      .check_others
    cmp     dil, 'z'
    jbe     .yes

.check_others:
    cmp     dil, '-'
    je      .yes
    cmp     dil, '_'
    je      .yes
    cmp     dil, '.'
    je      .yes
    cmp     dil, '~'
    je      .yes
    jmp     .no

.check_digit:
    cmp     dil, '0'
    jb      .no
    cmp     dil, '9'
    jbe     .yes

.no:
    xor     eax, eax
    ret
.yes:
    mov     eax, 1
    ret

; Helper to convert 4-bit nibble to uppercase hex character
_nibble_to_hex:
    and     dil, 0x0F
    cmp     dil, 10
    jb      .digit
    add     dil, 'A' - 10
    mov     al, dil
    ret
.digit:
    add     dil, '0'
    mov     al, dil
    ret

; Helper to convert hex character to 4-bit value, or return -1 on error
_hex_to_nibble:
    cmp     dil, '0'
    jb      .not_digit
    cmp     dil, '9'
    ja      .not_digit
    sub     dil, '0'
    movzx   eax, dil
    ret

.not_digit:
    cmp     dil, 'A'
    jb      .not_upper
    cmp     dil, 'F'
    ja      .not_upper
    sub     dil, 'A' - 10
    movzx   eax, dil
    ret

.not_upper:
    cmp     dil, 'a'
    jb      .err
    cmp     dil, 'f'
    ja      .err
    sub     dil, 'a' - 10
    movzx   eax, dil
    ret

.err:
    mov     rax, -1
    ret

; -----------------------------------------------------------------------------
; str_uri_encode
;
; Percent-encode a string according to RFC 3986.
;
; Signature:
;   int64_t str_uri_encode(const StrSlice *src, uint8_t *dst,
;                          uint64_t cap, uint64_t *out_len)
;
; Arguments:
;   RDI  — src (StrSlice*)
;   RSI  — dst (uint8_t*)
;   RDX  — cap (uint64_t)
;   RCX  — out_len (uint64_t*)
; -----------------------------------------------------------------------------
STR_FUNC str_uri_encode
    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15
    sub     rsp, 8              ; align

    mov     rbx, [rdi + StrSlice.ptr]   ; src.ptr
    mov     r12, [rdi + StrSlice.len]   ; src.len
    mov     r13, rsi                    ; dst
    mov     r14, rdx                    ; cap
    mov     r15, rcx                    ; out_len ptr

    xor     rcx, rcx                    ; src_offset = 0
    xor     rdx, rdx                    ; dst_offset = 0

.loop:
    cmp     rcx, r12
    je      .done

    movzx   edi, byte [rbx + rcx]
    push    rcx
    push    rdx
    call    _is_unreserved
    pop     rdx
    pop     rcx
    test    rax, rax
    jz      .encode_byte

    ; unreserved: write as-is
    cmp     rdx, r14
    jae     .too_small
    movzx   eax, byte [rbx + rcx]
    mov     [r13 + rdx], al
    inc     rdx
    inc     rcx
    jmp     .loop

.encode_byte:
    ; check capacity: need 3 bytes
    mov     rax, rdx
    add     rax, 3
    cmp     rax, r14
    ja      .too_small

    movzx   r8d, byte [rbx + rcx]       ; byte to encode
    
    ; write '%'
    mov     byte [r13 + rdx], '%'
    
    ; hi nibble
    mov     edi, r8d
    shr     edi, 4
    push    rcx
    push    rdx
    push    r8
    call    _nibble_to_hex
    pop     r8
    pop     rdx
    pop     rcx
    mov     [r13 + rdx + 1], al

    ; lo nibble
    mov     edi, r8d
    push    rcx
    push    rdx
    call    _nibble_to_hex
    pop     rdx
    pop     rcx
    mov     [r13 + rdx + 2], al

    add     rdx, 3
    inc     rcx
    jmp     .loop

.done:
    mov     [r15], rdx                  ; write out_len
    add     rsp, 8
    pop_regs r15, r14, r13, r12, rbx
    ret_ok

.too_small:
    add     rsp, 8
    pop_regs r15, r14, r13, r12, rbx
    ret_err STR_ERR_BUF_TOO_SMALL
STR_ENDFUNC str_uri_encode

; -----------------------------------------------------------------------------
; str_uri_decode
;
; Percent-decode a string, converting %XX back to raw bytes.
;
; Signature:
;   int64_t str_uri_decode(const StrSlice *src, uint8_t *dst,
;                          uint64_t cap, uint64_t *out_len)
; -----------------------------------------------------------------------------
STR_FUNC str_uri_decode
    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15
    sub     rsp, 8

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, [rdi + StrSlice.len]
    mov     r13, rsi
    mov     r14, rdx
    mov     r15, rcx

    xor     rcx, rcx                    ; src_offset = 0
    xor     rdx, rdx                    ; dst_offset = 0

.loop:
    cmp     rcx, r12
    je      .done

    movzx   eax, byte [rbx + rcx]
    cmp     al, '%'
    jne     .normal_char

    ; % found: verify we have 2 more chars
    mov     rax, rcx
    add     rax, 2
    cmp     rax, r12
    jae     .invalid

    ; convert hi nibble
    movzx   edi, byte [rbx + rcx + 1]
    push    rcx
    push    rdx
    call    _hex_to_nibble
    pop     rdx
    pop     rcx
    cmp     rax, -1
    je      .invalid
    mov     r8, rax                     ; hi value

    ; convert lo nibble
    movzx   edi, byte [rbx + rcx + 2]
    push    rcx
    push    rdx
    push    r8
    call    _hex_to_nibble
    pop     r8
    pop     rdx
    pop     rcx
    cmp     rax, -1
    je      .invalid
    
    ; decoded byte = (hi << 4) | lo
    shl     r8, 4
    or      r8, rax

    cmp     rdx, r14
    jae     .too_small

    mov     [r13 + rdx], r8b
    inc     rdx
    add     rcx, 3
    jmp     .loop

.normal_char:
    cmp     rdx, r14
    jae     .too_small
    mov     [r13 + rdx], al
    inc     rdx
    inc     rcx
    jmp     .loop

.done:
    mov     [r15], rdx
    add     rsp, 8
    pop_regs r15, r14, r13, r12, rbx
    ret_ok

.invalid:
    add     rsp, 8
    pop_regs r15, r14, r13, r12, rbx
    ret_err STR_ERR_INVALID

.too_small:
    add     rsp, 8
    pop_regs r15, r14, r13, r12, rbx
    ret_err STR_ERR_BUF_TOO_SMALL
STR_ENDFUNC str_uri_decode
