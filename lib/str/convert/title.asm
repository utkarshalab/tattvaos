%ifndef GUARD_LIB_STR_CONVERT_TITLE_ASM
%define GUARD_LIB_STR_CONVERT_TITLE_ASM
; =============================================================================
; str/convert/title.asm
; Title casing, capitalization, and case-swapping.
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
;   unicode/props.asm (str_cp_is_white_space)
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"







section .text

; -----------------------------------------------------------------------------
; str_to_title_case
;
; Uppercase the first letter of each word, lowercase the rest.
;
; Signature:
;   int64_t str_to_title_case(const StrSlice *src, uint8_t *dst,
;                             uint64_t cap, uint64_t *out_len)
; -----------------------------------------------------------------------------
STR_FUNC str_to_title_case
    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15
    sub     rsp, 24             ; space for advance [rsp], dst_offset [rsp+8], is_word_start [rsp+16]

    mov     rbx, [rdi + StrSlice.ptr]   ; src_ptr
    mov     r12, [rdi + StrSlice.len]   ; src_len
    mov     r13, rsi                    ; dst
    mov     r14, rdx                    ; cap
    mov     r15, rcx                    ; out_len

    lea     r11, [rbx + r12]            ; end_ptr
    mov     qword [rsp + 8], 0          ; dst_offset = 0
    mov     qword [rsp + 16], 1         ; is_word_start = 1

.loop:
    cmp     rbx, r11
    jae     .done

    ; decode next
    mov     rdi, rbx
    mov     rsi, rsp
    call    str_utf8_decode_unchecked
    ; eax = cp
    mov     r8, [rsp]                   ; advance size
    add     rbx, r8                     ; advance src_ptr

    ; check if cp is whitespace
    mov     edi, eax
    push    rax
    call    str_cp_is_white_space
    pop     r10                         ; r10 = cp
    test    rax, rax
    jnz     .whitespace

    ; not whitespace: check if starting word
    mov     rax, [rsp + 16]             ; is_word_start
    test    rax, rax
    jz      .lowercase

    ; titlecase: make uppercase
    mov     edi, r10d
    call    str_cp_to_upper
    mov     qword [rsp + 16], 0         ; clear is_word_start
    jmp     .encode

.lowercase:
    mov     edi, r10d
    call    str_cp_to_lower
    jmp     .encode

.whitespace:
    mov     eax, r10d                   ; write whitespace character as-is
    mov     qword [rsp + 16], 1         ; set is_word_start = 1

.encode:
    ; check capacity: dst_offset + 4 <= cap
    mov     rsi, [rsp + 8]              ; dst_offset
    lea     rcx, [rsi + 4]
    cmp     rcx, r14
    ja      .too_small

    ; encode into dst + dst_offset
    mov     edi, eax
    mov     rsi, r13
    add     rsi, [rsp + 8]
    call    str_utf8_encode_unchecked
    ; rax = written bytes
    add     [rsp + 8], rax              ; advance dst_offset
    jmp     .loop

.done:
    mov     rax, [rsp + 8]              ; dst_offset
    mov     [r15], rax                  ; write out_len
    add     rsp, 24
    pop_regs r15, r14, r13, r12, rbx
    ret_ok

.too_small:
    add     rsp, 24
    pop_regs r15, r14, r13, r12, rbx
    ret_err STR_ERR_BUF_TOO_SMALL
STR_ENDFUNC str_to_title_case

; -----------------------------------------------------------------------------
; str_capitalize
;
; Uppercase first character only, lowercase the rest.
;
; Signature:
;   int64_t str_capitalize(const StrSlice *src, uint8_t *dst,
;                          uint64_t cap, uint64_t *out_len)
; -----------------------------------------------------------------------------
STR_FUNC str_capitalize
    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15
    sub     rsp, 24             ; advance [rsp], dst_offset [rsp+8], first [rsp+16]

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, [rdi + StrSlice.len]
    mov     r13, rsi
    mov     r14, rdx
    mov     r15, rcx

    lea     r11, [rbx + r12]
    mov     qword [rsp + 8], 0
    mov     qword [rsp + 16], 1         ; first = 1

.loop:
    cmp     rbx, r11
    jae     .done

    mov     rdi, rbx
    mov     rsi, rsp
    call    str_utf8_decode_unchecked
    mov     r8, [rsp]
    add     rbx, r8

    mov     r10, [rsp + 16]             ; first
    test    r10, r10
    jz      .lowercase

    mov     edi, eax
    call    str_cp_to_upper
    mov     qword [rsp + 16], 0         ; clear first flag
    jmp     .encode

.lowercase:
    mov     edi, eax
    call    str_cp_to_lower

.encode:
    mov     rsi, [rsp + 8]
    lea     rcx, [rsi + 4]
    cmp     rcx, r14
    ja      .too_small

    mov     edi, eax
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
STR_ENDFUNC str_capitalize

; -----------------------------------------------------------------------------
; str_swap_case
;
; Uppercase ↔ lowercase for every letter. Non-letters pass through.
;
; Signature:
;   int64_t str_swap_case(const StrSlice *src, uint8_t *dst,
;                         uint64_t cap, uint64_t *out_len)
; -----------------------------------------------------------------------------
STR_FUNC str_swap_case
    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15
    sub     rsp, 24             ; advance [rsp], dst_offset [rsp+8]

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, [rdi + StrSlice.len]
    mov     r13, rsi
    mov     r14, rdx
    mov     r15, rcx

    lea     r11, [rbx + r12]
    mov     qword [rsp + 8], 0

.loop:
    cmp     rbx, r11
    jae     .done

    mov     rdi, rbx
    mov     rsi, rsp
    call    str_utf8_decode_unchecked
    mov     r8, [rsp]
    add     rbx, r8

    ; check if lowercase -> convert to upper
    mov     edi, eax
    push    rax
    call    str_is_lower_cp
    pop     rdx
    test    rax, rax
    jz      .check_upper

    mov     edi, edx
    call    str_cp_to_upper
    jmp     .encode

.check_upper:
    mov     edi, edx
    push    rdx
    call    str_is_upper_cp
    pop     rdx
    test    rax, rax
    jz      .keep_as_is

    mov     edi, edx
    call    str_cp_to_lower
    jmp     .encode

.keep_as_is:
    mov     eax, edx

.encode:
    mov     rsi, [rsp + 8]
    lea     rcx, [rsi + 4]
    cmp     rcx, r14
    ja      .too_small

    mov     edi, eax
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
STR_ENDFUNC str_swap_case

%endif ; GUARD_LIB_STR_CONVERT_TITLE_ASM
