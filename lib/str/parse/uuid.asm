%ifndef GUARD_LIB_STR_PARSE_UUID_ASM
%define GUARD_LIB_STR_PARSE_UUID_ASM
; =============================================================================
; str/parse/uuid.asm
; Parse, validate, generate, and format UUID strings (RFC 4122).
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   inspect/is_hex_digit.asm  (str_hex_digit_value)
;   convert/hex.asm           (str_bytes_to_hex)
;
; -----------------------------------------------------------------------------
; UUID format: xxxxxxxx-xxxx-Mxxx-Nxxx-xxxxxxxxxxxx
;   Total: 32 hex digits + 4 hyphens = 36 characters
;
;   M = version nibble (1-5, or 0)
;   N = variant nibble (8-B for RFC 4122)
;
; UUID stored as 16 raw bytes (128 bits), big-endian field order.
;
; Functions:
;   str_parse_uuid      — parse UUID string → 16 bytes
;   str_uuid_to_str     — 16 bytes → UUID string (lowercase)
;   str_uuid_to_str_up  — 16 bytes → UUID string (uppercase)
;   str_uuid_version    — get version from raw bytes
;   str_uuid_variant    — get variant from raw bytes
;   str_uuid_is_nil     — check if UUID is all zeros
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

UUID_STR_LEN    equ 36          ; "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
UUID_BYTES      equ 16

section .rodata
_uuid_hex_lo: db "0123456789abcdef"
_uuid_hex_hi: db "0123456789ABCDEF"

section .text

; -----------------------------------------------------------------------------
; str_parse_uuid
;
; Parse a UUID string into 16 raw bytes.
; Accepts both uppercase and lowercase hex.
; Both hyphenated ("xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx") and
; compact ("xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx") formats accepted.
;
; Signature:
;   int64_t str_parse_uuid(const StrSlice *src, uint8_t *out)
;
; Arguments:
;   RDI  — source StrSlice
;   RSI  — output buffer (exactly 16 bytes)
;
; Returns:
;   RAX  = STR_OK
;   RAX  = STR_ERR_NULL
;   RAX  = STR_ERR_PARSE   invalid UUID format
; -----------------------------------------------------------------------------

STR_FUNC str_parse_uuid

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, [rdi + StrSlice.len]
    mov     r13, rsi            ; out

    ; check length: 36 (hyphenated) or 32 (compact)
    cmp     r12, UUID_STR_LEN
    je      .uuid_hyphenated

    cmp     r12, 32
    je      .uuid_compact

    ; check for braces: "{xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx}"
    cmp     r12, 38
    jne     .uuid_parse_err

    movzx   eax, byte [rbx]
    cmp     al, '{'
    jne     .uuid_parse_err

    movzx   eax, byte [rbx + 37]
    cmp     al, '}'
    jne     .uuid_parse_err

    inc     rbx                 ; skip '{'
    mov     r12, UUID_STR_LEN
    jmp     .uuid_hyphenated

.uuid_hyphenated:
    ; validate hyphen positions: 8, 13, 18, 23
    cmp     byte [rbx + 8],  '-'
    jne     .uuid_parse_err
    cmp     byte [rbx + 13], '-'
    jne     .uuid_parse_err
    cmp     byte [rbx + 18], '-'
    jne     .uuid_parse_err
    cmp     byte [rbx + 23], '-'
    jne     .uuid_parse_err

    ; parse 32 hex digits (skipping hyphens)
    xor     r14, r14            ; src index
    xor     r15, r15            ; dst index

.uuid_h_loop:
    cmp     r15, UUID_BYTES
    jae     .uuid_done

    ; skip hyphen
    movzx   eax, byte [rbx + r14]
    cmp     al, '-'
    jne     .uuid_h_parse_byte
    inc     r14
    movzx   eax, byte [rbx + r14]

.uuid_h_parse_byte:
    ; parse high nibble
    movzx   edi, byte [rbx + r14]
    push    r14
    push    r15
    call    str_hex_digit_value
    pop     r15
    pop     r14
    test    rax, rax
    js      .uuid_parse_err

    mov     r9d, eax
    shl     r9d, 4
    inc     r14

    ; parse low nibble
    movzx   edi, byte [rbx + r14]
    push    r14
    push    r15
    push    r9
    call    str_hex_digit_value
    pop     r9
    pop     r15
    pop     r14
    test    rax, rax
    js      .uuid_parse_err

    or      r9d, eax
    mov     [r13 + r15], r9b
    inc     r14
    inc     r15
    jmp     .uuid_h_loop

.uuid_compact:
    ; 32 hex chars, no hyphens
    xor     r14, r14
    xor     r15, r15

.uuid_c_loop:
    cmp     r15, UUID_BYTES
    jae     .uuid_done

    movzx   edi, byte [rbx + r14]
    push    r14
    push    r15
    call    str_hex_digit_value
    pop     r15
    pop     r14
    test    rax, rax
    js      .uuid_parse_err

    mov     r9d, eax
    shl     r9d, 4
    inc     r14

    movzx   edi, byte [rbx + r14]
    push    r14
    push    r15
    push    r9
    call    str_hex_digit_value
    pop     r9
    pop     r15
    pop     r14
    test    rax, rax
    js      .uuid_parse_err

    or      r9d, eax
    mov     [r13 + r15], r9b
    inc     r14
    inc     r15
    jmp     .uuid_c_loop

.uuid_done:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.uuid_parse_err:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_PARSE
    pop     rbp
    ret

STR_ENDFUNC str_parse_uuid

; -----------------------------------------------------------------------------
; _uuid_format (internal)
; Format 16 UUID bytes to 36-char string with given hex table.
; dst must be at least 36 bytes.
; -----------------------------------------------------------------------------

_uuid_format:
    ; RDI = src (16 bytes), RSI = dst (36 bytes), RDX = hex table

    push    rbx
    mov     rbx, rdx            ; hex table

    ; field offsets: bytes 0-3, 4-5, 6-7, 8-9, 10-15
    ; format: [0-3]-[4-5]-[6-7]-[8-9]-[10-15]
    ; = 8-4-4-4-12 hex chars + 4 hyphens

    xor     ecx, ecx            ; src byte
    xor     edx, edx            ; dst offset

.uft_loop:
    ; insert hyphens at positions 8, 13, 18, 23
    cmp     edx, 8
    je      .uft_hyp
    cmp     edx, 13
    je      .uft_hyp
    cmp     edx, 18
    je      .uft_hyp
    cmp     edx, 23
    je      .uft_hyp
    jmp     .uft_hex

.uft_hyp:
    mov     byte [rsi + rdx], '-'
    inc     edx
    jmp     .uft_loop

.uft_hex:
    cmp     ecx, 16
    jae     .uft_done

    movzx   eax, byte [rdi + rcx]
    mov     r8d, eax
    shr     r8d, 4
    movzx   r8d, byte [rbx + r8]
    mov     [rsi + rdx], r8b
    inc     edx

    and     eax, 0xF
    movzx   eax, byte [rbx + rax]
    mov     [rsi + rdx], al
    inc     edx

    inc     ecx
    jmp     .uft_loop

.uft_done:
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; str_uuid_to_str
;
; Format 16 UUID bytes to lowercase hyphenated string.
;
; Signature:
;   int64_t str_uuid_to_str(const uint8_t *uuid, uint8_t *dst,
;                            uint64_t dst_cap, uint64_t *out_len)
; -----------------------------------------------------------------------------

STR_FUNC str_uuid_to_str

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    cmp     rdx, UUID_STR_LEN
    jb      .u2s_too_small

    push    rcx                 ; out_len

    lea     rdx, [rel _uuid_hex_lo]
    call    _uuid_format

    pop     rcx
    test    rcx, rcx
    jz      .u2s_ok
    mov     qword [rcx], UUID_STR_LEN

.u2s_ok:
    xor     eax, eax
    pop     rbp
    ret

.u2s_too_small:
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_uuid_to_str

; -----------------------------------------------------------------------------
; str_uuid_to_str_up — uppercase variant
; -----------------------------------------------------------------------------

STR_FUNC str_uuid_to_str_up

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    cmp     rdx, UUID_STR_LEN
    jb      .u2su_too_small

    push    rcx

    lea     rdx, [rel _uuid_hex_hi]
    call    _uuid_format

    pop     rcx
    test    rcx, rcx
    jz      .u2su_ok
    mov     qword [rcx], UUID_STR_LEN

.u2su_ok:
    xor     eax, eax
    pop     rbp
    ret

.u2su_too_small:
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_uuid_to_str_up

; -----------------------------------------------------------------------------
; str_uuid_version
;
; Get the version number from a UUID (nibble at byte 6, bits 7:4).
;
; Signature:
;   uint8_t str_uuid_version(const uint8_t *uuid)
;
; Returns:
;   AL = version (1-5) or 0 for nil/unknown
; -----------------------------------------------------------------------------

STR_FUNC str_uuid_version

    movzx   eax, byte [rdi + 6]
    shr     al, 4
    pop     rbp
    ret

STR_ENDFUNC str_uuid_version

; -----------------------------------------------------------------------------
; str_uuid_variant
;
; Get the variant from byte 8, bits 7:6.
;
; Signature:
;   uint8_t str_uuid_variant(const uint8_t *uuid)
;
; Returns:
;   AL = 0x8..0xB for RFC 4122
; -----------------------------------------------------------------------------

STR_FUNC str_uuid_variant

    movzx   eax, byte [rdi + 8]
    and     al, 0xC0            ; top 2 bits
    shr     al, 4
    pop     rbp
    ret

STR_ENDFUNC str_uuid_variant

; -----------------------------------------------------------------------------
; str_uuid_is_nil
;
; Check if UUID is the nil UUID (all zeros).
;
; Signature:
;   int64_t str_uuid_is_nil(const uint8_t *uuid)
;
; Returns:
;   RAX = 1 if nil, 0 otherwise
; -----------------------------------------------------------------------------

STR_FUNC str_uuid_is_nil

    ; check 16 bytes for all-zero
    mov     rax, [rdi]
    or      rax, [rdi + 8]
    test    rax, rax
    setz    al
    movzx   eax, al
    pop     rbp
    ret

STR_ENDFUNC str_uuid_is_nil
%endif ; GUARD_LIB_STR_PARSE_UUID_ASM
