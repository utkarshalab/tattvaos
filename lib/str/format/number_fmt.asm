; =============================================================================
; str/format/number_fmt.asm
; Number formatting functions: thousands separator, bytesize, and ordinals.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   core/copy.asm  (str_copy_bytes)
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_copy_bytes

section .rodata

_suffixes:
    db "B", 0, 0
    db "KB", 0
    db "MB", 0
    db "GB", 0
    db "TB", 0
    db "PB", 0
    db "EB", 0

section .text

; -----------------------------------------------------------------------------
; str_format_thousands
;
; Format integer with thousands separator (e.g. 1000000 -> "1,000,000").
;
; Signature:
;   int64_t str_format_thousands(uint64_t val, uint8_t sep_char,
;                                uint8_t *dst, uint64_t cap, uint64_t *out_len)
;
; Arguments:
;   RDI  — val (uint64_t)
;   RSI  — sep_char (uint8_t)
;   RDX  — dst (uint8_t*)
;   RCX  — cap (uint64_t)
;   R8   — out_len (uint64_t*)
; -----------------------------------------------------------------------------
STR_FUNC str_format_thousands
    guard_null rdx, STR_ERR_NULL
    guard_null r8,  STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15
    sub     rsp, 40             ; 32-byte temp buffer for digits + 8 bytes align

    mov     rbx, rdi            ; val
    mov     r12d, esi           ; sep_char
    mov     r13, rdx            ; dst
    mov     r14, rcx            ; cap
    mov     r15, r8             ; out_len

    ; 1. Generate digits right-to-left in [rsp .. rsp+31]
    mov     rax, rbx
    mov     rcx, 10
    lea     r8, [rsp + 32]      ; start of digits (ends here)
    
    test    rax, rax
    jnz     .digit_loop
    ; val is 0
    dec     r8
    mov     byte [r8], '0'
    jmp     .digits_done

.digit_loop:
    test    rax, rax
    jz      .digits_done
    xor     rdx, rdx
    div     rcx                 ; RDX = digit
    dec     r8
    add     dl, '0'
    mov     [r8], dl
    jmp     .digit_loop

.digits_done:
    ; Digits range: [r8 .. rsp+32)
    lea     rax, [rsp + 32]
    sub     rax, r8             ; digits_len
    mov     rcx, rax            ; digits_len

    ; 2. Copy to dst inserting separators
    xor     rdx, rdx            ; dst_offset = 0
    xor     rsi, rsi            ; k = 0 (digit index)

.copy_loop:
    cmp     rsi, rcx
    je      .done

    ; rem = digits_len - k
    mov     rax, rcx
    sub     rax, rsi            ; rem

    test    rsi, rsi
    jz      .write_digit
    
    ; check if rem % 3 == 0
    push    rcx
    xor     edx, edx
    mov     r9, 3
    div     r9
    pop     rcx
    test    rdx, rdx
    jnz     .write_digit

    ; insert sep_char
    ; restore rdx as dst_offset! (divide clobbers RDX)
    ; Fix: divide clobbered RDX. Let's restructure to keep dst_offset in a register that is not clobbered, e.g. r10.

.write_digit:
    jmp     .done
STR_ENDFUNC str_format_thousands

; -----------------------------------------------------------------------------
; Clean implementation of str_format_thousands keeping dst_offset safe
; -----------------------------------------------------------------------------

STR_FUNC str_format_thousands
    guard_null rdx, STR_ERR_NULL
    guard_null r8,  STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15
    sub     rsp, 40

    mov     rbx, rdi            ; val
    mov     r12d, esi           ; sep_char
    mov     r13, rdx            ; dst
    mov     r14, rcx            ; cap
    mov     r15, r8             ; out_len

    mov     rax, rbx
    mov     rcx, 10
    lea     r8, [rsp + 32]

    test    rax, rax
    jnz     .dig_loop
    dec     r8
    mov     byte [r8], '0'
    jmp     .dig_done

.dig_loop:
    test    rax, rax
    jz      .dig_done
    xor     rdx, rdx
    div     rcx
    dec     r8
    add     dl, '0'
    mov     [r8], dl
    jmp     .dig_loop

.dig_done:
    lea     rax, [rsp + 32]
    sub     rax, r8             ; digits_len
    mov     rcx, rax            ; digits_len

    xor     r10, r10            ; dst_offset = 0
    xor     rsi, rsi            ; k = 0

.c_loop:
    cmp     rsi, rcx
    je      .c_done

    test    rsi, rsi
    jz      .c_write

    ; rem = digits_len - k
    mov     rax, rcx
    sub     rax, rsi
    xor     rdx, rdx
    push    rcx
    mov     r9, 3
    div     r9                  ; RDX = rem % 3
    pop     rcx
    test    rdx, rdx
    jnz     .c_write

    ; write sep_char
    cmp     r10, r14
    jae     .too_small
    mov     [r13 + r10], r12b
    inc     r10

.c_write:
    cmp     r10, r14
    jae     .too_small
    movzx   eax, byte [r8 + rsi]
    mov     [r13 + r10], al
    inc     r10
    inc     rsi
    jmp     .c_loop

.c_done:
    mov     [r15], r10
    add     rsp, 40
    pop_regs r15, r14, r13, r12, rbx
    ret_ok

.too_small:
    add     rsp, 40
    pop_regs r15, r14, r13, r12, rbx
    ret_err STR_ERR_BUF_TOO_SMALL
STR_ENDFUNC str_format_thousands

; -----------------------------------------------------------------------------
; str_format_ordinal
;
; Format number as ordinal (e.g. 1 -> "1st", 11 -> "11th").
;
; Signature:
;   int64_t str_format_ordinal(uint64_t val, uint8_t *dst,
;                              uint64_t cap, uint64_t *out_len)
;
; Arguments:
;   RDI  — val (uint64_t)
;   RSI  — dst (uint8_t*)
;   RDX  — cap (uint64_t)
;   RCX  — out_len (uint64_t*)
; -----------------------------------------------------------------------------
STR_FUNC str_format_ordinal
    guard_null rsi, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15
    sub     rsp, 40             ; 32-byte temp buffer for digits + 8 bytes align

    mov     rbx, rdi            ; val
    mov     r12, rsi            ; dst
    mov     r13, rdx            ; cap
    mov     r14, rcx            ; out_len

    ; 1. Generate digits
    mov     rax, rbx
    mov     rcx, 10
    lea     r8, [rsp + 32]

    test    rax, rax
    jnz     .dig_loop
    dec     r8
    mov     byte [r8], '0'
    jmp     .dig_done

.dig_loop:
    test    rax, rax
    jz      .dig_done
    xor     rdx, rdx
    div     rcx
    dec     r8
    add     dl, '0'
    mov     [r8], dl
    jmp     .dig_loop

.dig_done:
    lea     rax, [rsp + 32]
    sub     rax, r8             ; digits_len
    mov     r15, rax            ; digits_len

    ; check capacity: digits_len + 2 <= cap
    lea     rax, [r15 + 2]
    cmp     rax, r13
    ja      .too_small

    ; 2. Determine suffix
    ; mod100 = val % 100
    mov     rax, rbx
    xor     rdx, rdx
    mov     rcx, 100
    div     rcx                 ; RDX = val % 100
    mov     r9, rdx             ; mod100

    ; mod10 = val % 10
    mov     rax, rbx
    xor     rdx, rdx
    mov     rcx, 10
    div     rcx                 ; RDX = val % 10
    mov     r10, rdx            ; mod10

    ; check teen rule: if mod100 >= 11 and mod100 <= 13 -> "th"
    cmp     r9, 11
    jb      .check_single
    cmp     r9, 13
    jbe     .suffix_th

.check_single:
    cmp     r10, 1
    je      .suffix_st
    cmp     r10, 2
    je      .suffix_nd
    cmp     r10, 3
    je      .suffix_rd

.suffix_th:
    mov     ax, "th"
    jmp     .write_output

.suffix_st:
    mov     ax, "st"
    jmp     .write_output

.suffix_nd:
    mov     ax, "nd"
    jmp     .write_output

.suffix_rd:
    mov     ax, "rd"

.write_output:
    ; copy digits to dst
    mov     rdi, r12
    mov     rsi, r8
    mov     rdx, r15
    call    str_copy_bytes

    ; append suffix (2 bytes in AX)
    mov     [r12 + r15], ax

    lea     rax, [r15 + 2]
    mov     [r14], rax          ; write out_len

    add     rsp, 40
    pop_regs r15, r14, r13, r12, rbx
    ret_ok

.too_small:
    add     rsp, 40
    pop_regs r15, r14, r13, r12, rbx
    ret_err STR_ERR_BUF_TOO_SMALL
STR_ENDFUNC str_format_ordinal

; -----------------------------------------------------------------------------
; str_format_bytesize
;
; Format byte size into human readable string (e.g. 1024 -> "1.00 KB").
;
; Signature:
;   int64_t str_format_bytesize(uint64_t bytes, uint8_t *dst,
;                               uint64_t cap, uint64_t *out_len)
;
; Arguments:
;   RDI  — bytes (uint64_t)
;   RSI  — dst (uint8_t*)
;   RDX  — cap (uint64_t)
;   RCX  — out_len (uint64_t*)
; -----------------------------------------------------------------------------
STR_FUNC str_format_bytesize
    guard_null rsi, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15
    sub     rsp, 40             ; temp buffer for formatting

    mov     rbx, rdi            ; bytes
    mov     r12, rsi            ; dst
    mov     r13, rdx            ; cap
    mov     r14, rcx            ; out_len

    ; Find scale: successive division by 1024
    mov     rax, rbx
    xor     r15, r15            ; scale = 0

.scale_loop:
    cmp     rax, 1024
    jb      .scale_done
    cmp     r15, 6              ; maximum EB suffix
    je      .scale_done

    shr     rax, 10             ; rax = rax / 1024
    inc     r15                 ; scale++
    jmp     .scale_loop

.scale_done:
    ; If scale == 0: format as integer B
    test    r15, r15
    jnz     .format_fractional

    ; format integer only
    mov     rax, rbx
    mov     rcx, 10
    lea     r8, [rsp + 32]
.int_loop:
    test    rax, rax
    jz      .int_done
    xor     rdx, rdx
    div     rcx
    dec     r8
    add     dl, '0'
    mov     [r8], dl
    jmp     .int_loop

.int_done:
    lea     rax, [rsp + 32]
    sub     rax, r8             ; digits_len
    test    rax, rax
    jnz     .int_write
    ; bytes is 0
    dec     r8
    mov     byte [r8], '0'
    mov     rax, 1

.int_write:
    mov     rcx, rax            ; digits_len
    ; check capacity: digits_len + 2 (for " B") <= cap
    lea     rax, [rcx + 2]
    cmp     rax, r13
    ja      .too_small

    mov     rdi, r12
    mov     rsi, r8
    mov     rdx, rcx
    call    str_copy_bytes

    mov     byte [r12 + rcx], ' '
    mov     byte [r12 + rcx + 1], 'B'
    
    lea     rax, [rcx + 2]
    mov     [r14], rax
    add     rsp, 40
    pop_regs r15, r14, r13, r12, rbx
    ret_ok

.format_fractional:
    ; Compute (bytes * 100) / 1024^scale
    ; Compute 1024^scale
    mov     rcx, r15
    mov     r8, 1
.pow_loop:
    shl     r8, 10              ; r8 *= 1024
    dec     rcx
    jnz     .pow_loop

    ; RDX:RAX = bytes * 100
    mov     rax, rbx
    mov     r9, 100
    mul     r9                  ; RDX:RAX = RAX * 9

    ; divide by 1024^scale (R8)
    div     r8                  ; RAX = quotient, RDX = remainder

    ; round to nearest: if remainder >= divisor / 2, increment RAX
    mov     rcx, r8
    shr     rcx, 1              ; divisor / 2
    cmp     rdx, rcx
    jb      .no_round
    inc     rax

.no_round:
    ; RAX = scaled_value * 100
    ; integer part = RAX / 100, fraction part = RAX % 100
    xor     rdx, rdx
    mov     rcx, 100
    div     rcx                 ; RAX = integer part, RDX = fraction part (0..99)

    mov     r10, rax            ; integer part
    mov     r11, rdx            ; fraction part

    ; format integer part to stack [rsp..]
    mov     rax, r10
    mov     rcx, 10
    lea     r8, [rsp + 32]
.int2_loop:
    test    rax, rax
    jz      .int2_done
    xor     rdx, rdx
    div     rcx
    dec     r8
    add     dl, '0'
    mov     [r8], dl
    jmp     .int2_loop

.int2_done:
    lea     rax, [rsp + 32]
    sub     rax, r8             ; int_len
    test    rax, rax
    jnz     .int2_ok
    dec     r8
    mov     byte [r8], '0'
    mov     rax, 1

.int2_ok:
    mov     rcx, rax            ; int_len

    ; format fraction part to 2 digits: r11 / 10 and r11 % 10
    mov     rax, r11
    xor     rdx, rdx
    mov     r9, 10
    div     r9                  ; RAX = tens, RDX = ones
    add     al, '0'
    add     dl, '0'
    mov     byte [rsp + 32], al
    mov     byte [rsp + 33], dl

    ; Get suffix string
    ; Suffix table is at _suffixes. Index = r15 * 3
    lea     rsi, [rel _suffixes]
    mov     rax, r15
    lea     rax, [rax + rax*2]  ; rax = r15 * 3
    add     rsi, rax            ; rsi = suffix pointer

    ; Find suffix length
    xor     rdx, rdx
.suff_len_loop:
    cmp     byte [rsi + rdx], 0
    je      .suff_len_done
    inc     rdx
    jmp     .suff_len_loop
.suff_len_done:
    ; rdx = suffix_len

    ; total capacity check: int_len + 1 (dot) + 2 (frac) + 1 (space) + suffix_len <= cap
    lea     rax, [rcx + 1 + 2 + 1]
    add     rax, rdx            ; total len
    cmp     rax, r13
    ja      .too_small_frac

    ; save total len in R9
    mov     r9, rax

    ; 1. copy integer part
    push    r9
    push    rdx
    push    rsi
    mov     rdi, r12
    mov     rsi, r8
    mov     rdx, rcx
    call    str_copy_bytes
    pop     rsi
    pop     rdx
    pop     r9

    ; 2. dot
    mov     byte [r12 + rcx], '.'
    
    ; 3. copy 2 fraction digits
    movzx   eax, byte [rsp + 32]
    mov     [r12 + rcx + 1], al
    movzx   eax, byte [rsp + 33]
    mov     [r12 + rcx + 2], al

    ; 4. space
    mov     byte [r12 + rcx + 3], ' '

    ; 5. copy suffix
    push    r9
    lea     rdi, [r12 + rcx + 4]
    call    str_copy_bytes
    pop     r9

    mov     [r14], r9           ; write out_len
    add     rsp, 40
    pop_regs r15, r14, r13, r12, rbx
    ret_ok

.too_small_frac:
    add     rsp, 40
    pop_regs r15, r14, r13, r12, rbx
    ret_err STR_ERR_BUF_TOO_SMALL
STR_ENDFUNC str_format_bytesize
