; =============================================================================
; str/convert/ident.asm
; Case conversions for identifiers (snake, camel, pascal, kebab).
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
;   convert/case.asm (str_cp_to_upper, str_cp_to_lower)
;   inspect/is_lower.asm (str_is_lower_cp)
;   inspect/is_upper.asm (str_is_upper_cp)
;   inspect/is_alnum.asm (str_is_alnum_cp)
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_utf8_decode_unchecked
extern str_utf8_encode_unchecked
extern str_cp_to_upper
extern str_cp_to_lower
extern str_is_lower_cp
extern str_is_upper_cp
extern str_is_alnum_cp

section .text

; -----------------------------------------------------------------------------
; str_to_snake_case
;
; Convert identifier to snake_case ("helloWorld" -> "hello_world").
;
; Signature:
;   int64_t str_to_snake_case(const StrSlice *src, uint8_t *dst,
;                             uint64_t cap, uint64_t *out_len)
; -----------------------------------------------------------------------------
STR_FUNC str_to_snake_case
    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL

    ; Forward to helper with separator = '_'
    push    rcx
    mov     rcx, rdx
    mov     rdx, rsi
    mov     rsi, '_'
    call    _to_separator_case
    pop     rcx
    ret
STR_ENDFUNC str_to_snake_case

; -----------------------------------------------------------------------------
; str_to_kebab_case
;
; Convert identifier to kebab-case ("helloWorld" -> "hello-world").
;
; Signature:
;   int64_t str_to_kebab_case(const StrSlice *src, uint8_t *dst,
;                             uint64_t cap, uint64_t *out_len)
; -----------------------------------------------------------------------------
STR_FUNC str_to_kebab_case
    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL

    ; Forward to helper with separator = '-'
    push    rcx
    mov     rcx, rdx
    mov     rdx, rsi
    mov     rsi, '-'
    call    _to_separator_case
    pop     rcx
    ret
STR_ENDFUNC str_to_kebab_case

; -----------------------------------------------------------------------------
; _to_separator_case  (internal helper)
;
; Signature:
;   int64_t _to_separator_case(const StrSlice *src, uint8_t sep_char,
;                              uint8_t *dst, uint64_t cap, uint64_t *out_len)
; -----------------------------------------------------------------------------
_to_separator_case:
    push_regs rbx, r12, r13, r14, r15
    sub     rsp, 40             ; space for advance [rsp], dst_offset [rsp+8], flags [rsp+16..24], out_len [rsp+32]

    mov     rbx, [rdi + StrSlice.ptr]   ; read_ptr
    mov     rax, [rdi + StrSlice.len]
    lea     r12, [rbx + rax]            ; end_ptr
    mov     r13, rsi                    ; sep_char
    mov     r14, rdx                    ; dst
    mov     r15, rcx                    ; cap
    mov     rax, [rbp + 16]             ; out_len
    mov     [rsp + 32], rax

    mov     qword [rsp + 8], 0          ; dst_offset = 0
    mov     qword [rsp + 16], 0         ; prev_was_lower = 0
    mov     qword [rsp + 24], 0         ; prev_was_upper = 0

.loop:
    cmp     rbx, r12
    jae     .done

    mov     rdi, rbx
    mov     rsi, rsp
    call    str_utf8_decode_unchecked
    mov     rcx, [rsp]
    add     rbx, rcx                    ; advance read_ptr

    mov     r10d, eax                   ; cp

    ; check if space, hyphen, underscore
    cmp     r10d, 0x20
    je      .delimiter
    cmp     r10d, '-'
    je      .delimiter
    cmp     r10d, '_'
    je      .delimiter

    ; check if uppercase
    mov     edi, r10d
    push    r10
    call    str_is_upper_cp
    pop     r10
    test    rax, rax
    jz      .not_upper

    ; It is uppercase!
    ; check if prev_was_lower == 1
    mov     rax, [rsp + 16]
    test    rax, rax
    jnz     .insert_sep

    ; check if prev_was_upper == 1
    mov     rax, [rsp + 24]
    test    rax, rax
    jz      .write_upper                ; if no prev casing run, just write

    ; check if next codepoint is lowercase (look ahead)
    cmp     rbx, r12
    jae     .write_upper

    mov     rdi, rbx
    lea     rsi, [rsp]
    push    r10
    call    str_utf8_decode_unchecked
    pop     r10
    mov     edi, eax
    call    str_is_lower_cp
    test    rax, rax
    jz      .write_upper                ; next is not lower

.insert_sep:
    ; insert separator character
    mov     r8, [rsp + 8]               ; dst_offset
    cmp     r8, r15                     ; cap check
    jae     .too_small
    mov     [r14 + r8], r13b            ; write sep_char
    inc     qword [rsp + 8]

.write_upper:
    mov     edi, r10d
    call    str_cp_to_lower
    mov     r10d, eax
    mov     qword [rsp + 16], 0         ; prev_was_lower = 0
    mov     qword [rsp + 24], 1         ; prev_was_upper = 1
    jmp     .encode

.not_upper:
    ; check if lowercase
    mov     edi, r10d
    push    r10
    call    str_is_lower_cp
    pop     r10
    test    rax, rax
    jz      .other_char

    mov     qword [rsp + 16], 1         ; prev_was_lower = 1
    mov     qword [rsp + 24], 0         ; prev_was_upper = 0
    jmp     .encode

.other_char:
    mov     qword [rsp + 16], 0
    mov     qword [rsp + 24], 0
    jmp     .encode

.delimiter:
    ; write separator, reset flags
    mov     r8, [rsp + 8]
    cmp     r8, r15
    jae     .too_small
    mov     [r14 + r8], r13b
    inc     qword [rsp + 8]
    mov     qword [rsp + 16], 0
    mov     qword [rsp + 24], 0
    jmp     .loop

.encode:
    mov     rsi, [rsp + 8]
    lea     rcx, [rsi + 4]
    cmp     rcx, r15
    ja      .too_small

    mov     edi, r10d
    mov     rsi, r14
    add     rsi, [rsp + 8]
    call    str_utf8_encode_unchecked
    add     [rsp + 8], rax
    jmp     .loop

.done:
    mov     rax, [rsp + 32]             ; out_len ptr
    mov     rcx, [rsp + 8]              ; dst_offset
    mov     [rax], rcx
    add     rsp, 40
    pop_regs r15, r14, r13, r12, rbx
    ret_ok

.too_small:
    add     rsp, 40
    pop_regs r15, r14, r13, r12, rbx
    ret_err STR_ERR_BUF_TOO_SMALL

; -----------------------------------------------------------------------------
; str_to_camel_case
;
; Convert identifier to camelCase ("hello_world" -> "helloWorld").
;
; Signature:
;   int64_t str_to_camel_case(const StrSlice *src, uint8_t *dst,
;                             uint64_t cap, uint64_t *out_len)
; -----------------------------------------------------------------------------
STR_FUNC str_to_camel_case
    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15
    sub     rsp, 24             ; advance [rsp], dst_offset [rsp+8], states [rsp+16]
    ; states: [rsp+16] = capitalize_next, [rsp+17] = first

    mov     rbx, [rdi + StrSlice.ptr]
    mov     rax, [rdi + StrSlice.len]
    lea     r12, [rbx + rax]
    mov     r13, rsi
    mov     r14, rdx
    mov     r15, rcx

    mov     qword [rsp + 8], 0
    mov     byte [rsp + 16], 0          ; capitalize_next = 0
    mov     byte [rsp + 17], 1          ; first = 1

.loop:
    cmp     rbx, r12
    jae     .done

    mov     rdi, rbx
    mov     rsi, rsp
    call    str_utf8_decode_unchecked
    mov     rcx, [rsp]
    add     rbx, rcx

    mov     r10d, eax

    ; check delimiter
    cmp     r10d, 0x20
    je      .delimiter
    cmp     r10d, '-'
    je      .delimiter
    cmp     r10d, '_'
    je      .delimiter

    ; check first
    movzx   eax, byte [rsp + 17]
    test    al, al
    jz      .not_first

    mov     edi, r10d
    call    str_cp_to_lower
    mov     r10d, eax
    mov     byte [rsp + 17], 0          ; first = 0
    jmp     .encode

.not_first:
    movzx   eax, byte [rsp + 16]        ; capitalize_next
    test    al, al
    jz      .encode                     ; if not first and not capitalize, write as-is

    mov     edi, r10d
    call    str_cp_to_upper
    mov     r10d, eax
    mov     byte [rsp + 16], 0          ; capitalize_next = 0
    jmp     .encode

.delimiter:
    mov     byte [rsp + 16], 1          ; capitalize_next = 1
    jmp     .loop

.encode:
    mov     rsi, [rsp + 8]
    lea     rcx, [rsi + 4]
    cmp     rcx, r14
    ja      .too_small

    mov     edi, r10d
    mov     rsi, r13
    add     rsi, [rsp + 8]
    call    str_utf8_encode_unchecked
    add     [rsp + 8], rax
    jmp     .loop

.done:
    mov     rax, [rsp + 8]
    mov     [r15], rax
    add     rsp, 24
    pop_regs r15, r14, r13, r12, rbx
    ret_ok

.too_small:
    add     rsp, 24
    pop_regs r15, r14, r13, r12, rbx
    ret_err STR_ERR_BUF_TOO_SMALL
STR_ENDFUNC str_to_camel_case

; -----------------------------------------------------------------------------
; str_to_pascal_case
;
; Convert identifier to PascalCase ("hello_world" -> "HelloWorld").
;
; Signature:
;   int64_t str_to_pascal_case(const StrSlice *src, uint8_t *dst,
;                              uint64_t cap, uint64_t *out_len)
; -----------------------------------------------------------------------------
STR_FUNC str_to_pascal_case
    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15
    sub     rsp, 24

    mov     rbx, [rdi + StrSlice.ptr]
    mov     rax, [rdi + StrSlice.len]
    lea     r12, [rbx + rax]
    mov     r13, rsi
    mov     r14, rdx
    mov     r15, rcx

    mov     qword [rsp + 8], 0
    mov     byte [rsp + 16], 1          ; capitalize_next = 1 (Pascal starts capital)
    mov     byte [rsp + 17], 0          ; first = 0 (ignored for Pascal)

.loop:
    cmp     rbx, r12
    jae     .done

    mov     rdi, rbx
    mov     rsi, rsp
    call    str_utf8_decode_unchecked
    mov     rcx, [rsp]
    add     rbx, rcx

    mov     r10d, eax

    cmp     r10d, 0x20
    je      .delimiter
    cmp     r10d, '-'
    je      .delimiter
    cmp     r10d, '_'
    je      .delimiter

    movzx   eax, byte [rsp + 16]
    test    al, al
    jz      .encode

    mov     edi, r10d
    call    str_cp_to_upper
    mov     r10d, eax
    mov     byte [rsp + 16], 0
    jmp     .encode

.delimiter:
    mov     byte [rsp + 16], 1
    jmp     .loop

.encode:
    mov     rsi, [rsp + 8]
    lea     rcx, [rsi + 4]
    cmp     rcx, r14
    ja      .too_small

    mov     edi, r10d
    mov     rsi, r13
    add     rsi, [rsp + 8]
    call    str_utf8_encode_unchecked
    add     [rsp + 8], rax
    jmp     .loop

.done:
    mov     rax, [rsp + 8]
    mov     [r15], rax
    add     rsp, 24
    pop_regs r15, r14, r13, r12, rbx
    ret_ok

.too_small:
    add     rsp, 24
    pop_regs r15, r14, r13, r12, rbx
    ret_err STR_ERR_BUF_TOO_SMALL
STR_ENDFUNC str_to_pascal_case
