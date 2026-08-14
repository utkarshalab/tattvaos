%ifndef GUARD_LIB_STR_PARSE_SIZE_ASM
%define GUARD_LIB_STR_PARSE_SIZE_ASM
; =============================================================================
; str/parse/size.asm
; Parse human-readable byte size strings → uint64 bytes.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   convert/int.asm   (str_parse_u64)
;   convert/float.asm (str_parse_f64)
;
; -----------------------------------------------------------------------------
; Supported formats:
;
;   "1024"     → 1024 bytes (bare number = bytes)
;   "1KB"      → 1000 bytes  (SI: 1000^1)
;   "1KiB"     → 1024 bytes  (IEC: 1024^1)
;   "2.5MB"    → 2500000 bytes
;   "1GiB"     → 1073741824 bytes
;   "500 MB"   → with space
;   "1TB"      → 1000^4
;   "1TiB"     → 1024^4
;
; SI prefixes (powers of 1000):  KB, MB, GB, TB, PB, EB
; IEC prefixes (powers of 1024): KiB, MiB, GiB, TiB, PiB, EiB
; Both case-insensitive.
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"


; SI multipliers (powers of 1000)
SIZE_KB     equ 1000
SIZE_MB     equ 1000000
SIZE_GB     equ 1000000000
SIZE_TB     equ 1000000000000
SIZE_PB     equ 1000000000000000
SIZE_EB     equ 1000000000000000000

; IEC multipliers (powers of 1024)
SIZE_KiB    equ 1024
SIZE_MiB    equ 1048576
SIZE_GiB    equ 1073741824
SIZE_TiB    equ 1099511627776
SIZE_PiB    equ 1125899906842624
; EiB = 1152921504606846976

section .text

; -----------------------------------------------------------------------------
; str_parse_size
;
; Parse a byte size string.
;
; Signature:
;   int64_t str_parse_size(const StrSlice *src, uint64_t *out_bytes)
;
; Arguments:
;   RDI  — source StrSlice
;   RSI  — pointer to uint64_t to receive byte count
;
; Returns:
;   RAX  = STR_OK
;   RAX  = STR_ERR_NULL
;   RAX  = STR_ERR_PARSE
;   RAX  = STR_ERR_OVERFLOW
; -----------------------------------------------------------------------------

STR_FUNC str_parse_size

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, [rdi + StrSlice.len]
    mov     r13, rsi            ; out_bytes

    xor     r15, r15            ; index

    ; skip leading whitespace
.sz_skip_ws:
    cmp     r15, r12
    jae     .sz_parse_err
    movzx   eax, byte [rbx + r15]
    cmp     al, ' '
    je      .sz_ws_adv
    cmp     al, 0x09
    jb      .sz_parse_value
    cmp     al, 0x0D
    jbe     .sz_ws_adv
    jmp     .sz_parse_value
.sz_ws_adv:
    inc     r15
    jmp     .sz_skip_ws

.sz_parse_value:
    ; parse numeric part (integer or float)
    sub     rsp, STRSLICE_SIZE + 24
    and     rsp, -16

    lea     rax, [rbx + r15]
    mov     [rsp + StrSlice.ptr], rax
    mov     rax, r12
    sub     rax, r15
    mov     [rsp + StrSlice.len], rax

    ; try integer
    mov     rdi, rsp
    lea     rsi, [rsp + STRSLICE_SIZE]
    lea     rdx, [rsp + STRSLICE_SIZE + 8]
    call    str_parse_u64
    test    rax, rax
    jnz     .sz_try_float

    mov     r14, [rsp + STRSLICE_SIZE]        ; uint value
    mov     r10, [rsp + STRSLICE_SIZE + 8]    ; consumed
    add     r15, r10

    ; check for decimal
    cmp     r15, r12
    jae     .sz_got_unit
    movzx   ecx, byte [rbx + r15]
    cmp     cl, '.'
    je      .sz_try_float
    jmp     .sz_got_unit

.sz_try_float:
    mov     rdi, rsp
    lea     rsi, [rsp + STRSLICE_SIZE]
    lea     rdx, [rsp + STRSLICE_SIZE + 8]
    call    str_parse_f64
    test    rax, rax
    jnz     .sz_parse_err_stack

    ; get float value
    mov     r10, [rsp + STRSLICE_SIZE]        ; double bits
    movq    xmm0, r10
    mov     r10, [rsp + STRSLICE_SIZE + 8]    ; consumed
    add     r15, r10
    ; store float for later use (r14 not valid — use xmm0)
    ; for float handling: compute after unit detection
    mov     r14, 0xFFFFFFFFFFFFFFFF           ; sentinel: is float

    mov     rsp, rbp
    sub     rsp, 0
    jmp     .sz_got_unit_float

.sz_got_unit:
    mov     rsp, rbp
    sub     rsp, 0

    ; skip optional space between number and unit
.sz_skip_unit_ws:
    cmp     r15, r12
    jae     .sz_no_unit         ; bare number = bytes

    movzx   eax, byte [rbx + r15]
    cmp     al, ' '
    je      .sz_unit_ws_adv
    jmp     .sz_parse_unit

.sz_unit_ws_adv:
    inc     r15
    jmp     .sz_skip_unit_ws

.sz_got_unit_float:
    ; same as sz_got_unit but for float path
    ; skip space
.sz_float_unit_ws:
    cmp     r15, r12
    jae     .sz_no_unit

    movzx   eax, byte [rbx + r15]
    cmp     al, ' '
    jne     .sz_parse_unit
    inc     r15
    jmp     .sz_float_unit_ws

.sz_parse_unit:
    ; read unit chars (fold to uppercase for matching)
    movzx   eax, byte [rbx + r15]
    or      al, 0x20            ; fold to lowercase for comparison
    inc     r15

    ; first letter determines SI vs IEC and prefix
    cmp     al, 'k'
    je      .sz_kilo
    cmp     al, 'm'
    je      .sz_mega
    cmp     al, 'g'
    je      .sz_giga
    cmp     al, 't'
    je      .sz_tera
    cmp     al, 'p'
    je      .sz_peta
    cmp     al, 'e'
    je      .sz_exa
    cmp     al, 'b'
    je      .sz_bytes_unit
    jmp     .sz_parse_err

.sz_kilo:
    call    .sz_check_iec
    jc      .sz_kib
    mov     r11, SIZE_KB
    jmp     .sz_apply_mult
.sz_kib:
    mov     r11, SIZE_KiB
    jmp     .sz_apply_mult

.sz_mega:
    call    .sz_check_iec
    jc      .sz_mib
    mov     r11, SIZE_MB
    jmp     .sz_apply_mult
.sz_mib:
    mov     r11, SIZE_MiB
    jmp     .sz_apply_mult

.sz_giga:
    call    .sz_check_iec
    jc      .sz_gib
    mov     r11, SIZE_GB
    jmp     .sz_apply_mult
.sz_gib:
    mov     r11, SIZE_GiB
    jmp     .sz_apply_mult

.sz_tera:
    call    .sz_check_iec
    jc      .sz_tib
    mov     r11, SIZE_TB
    jmp     .sz_apply_mult
.sz_tib:
    mov     r11, SIZE_TiB
    jmp     .sz_apply_mult

.sz_peta:
    call    .sz_check_iec
    jc      .sz_pib
    mov     r11, SIZE_PB
    jmp     .sz_apply_mult
.sz_pib:
    mov     r11, SIZE_PiB
    jmp     .sz_apply_mult

.sz_exa:
    call    .sz_check_iec
    jc      .sz_eib
    mov     r11, SIZE_EB
    jmp     .sz_apply_mult
.sz_eib:
    ; EiB = 1152921504606846976
    mov     r11, 1152921504606846976
    jmp     .sz_apply_mult

.sz_bytes_unit:
    mov     r11, 1
    jmp     .sz_apply_mult

.sz_no_unit:
    ; bare number = bytes
    mov     [r13], r14
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.sz_apply_mult:
    ; check if float path
    cmp     r14, 0xFFFFFFFFFFFFFFFF
    je      .sz_float_mult

    ; integer: r14 * r11
    mov     rax, r14
    mul     r11                 ; rdx:rax = value * multiplier
    test    rdx, rdx
    jnz     .sz_overflow

    mov     [r13], rax
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.sz_float_mult:
    ; float: xmm0 * r11 (convert r11 to double, multiply, truncate)
    cvtsi2sd xmm1, r11
    mulsd   xmm0, xmm1
    cvttsd2si rax, xmm0
    mov     [r13], rax
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.sz_overflow:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_OVERFLOW
    pop     rbp
    ret

.sz_parse_err_stack:
    mov     rsp, rbp
.sz_parse_err:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_PARSE
    pop     rbp
    ret

; Internal: check if next chars are "iB" (IEC) or just "B" (SI)
; Sets CF if IEC, clears CF if SI
; Advances r15 past the suffix
.sz_check_iec:
    ; current r15 points to char after prefix letter
    cmp     r15, r12
    jae     .sz_ci_si           ; no more chars → SI

    movzx   ecx, byte [rbx + r15]
    or      cl, 0x20

    cmp     cl, 'i'
    jne     .sz_ci_b_only

    ; "i" found — check for "b"
    inc     r15
    cmp     r15, r12
    jae     .sz_ci_iec          ; just "Ki" etc. → treat as IEC

    movzx   ecx, byte [rbx + r15]
    or      cl, 0x20
    cmp     cl, 'b'
    jne     .sz_ci_iec

    inc     r15                 ; skip 'b'

.sz_ci_iec:
    stc                         ; CF = 1: IEC
    ret

.sz_ci_b_only:
    cmp     cl, 'b'
    jne     .sz_ci_si
    inc     r15                 ; skip 'b'

.sz_ci_si:
    clc                         ; CF = 0: SI
    ret

STR_ENDFUNC str_parse_size

; -----------------------------------------------------------------------------
; str_size_to_str
;
; Convert byte count to human-readable string.
; Chooses IEC units (KiB, MiB, etc.) for powers of 1024.
;
; Signature:
;   int64_t str_size_to_str(uint64_t bytes, uint8_t *buf,
;                            uint64_t buf_cap, uint64_t *out_len)
; -----------------------------------------------------------------------------

STR_FUNC str_size_to_str

    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14

    mov     rbx, rdi            ; bytes
    mov     r12, rsi            ; buf
    mov     r13, rdx            ; cap
    mov     r14, rcx            ; out_len

    ; pick unit
    cmp     rbx, SIZE_PiB
    jae     .sts_pib

    cmp     rbx, SIZE_TiB
    jae     .sts_tib

    cmp     rbx, SIZE_GiB
    jae     .sts_gib

    cmp     rbx, SIZE_MiB
    jae     .sts_mib

    cmp     rbx, SIZE_KiB
    jae     .sts_kib

    ; bytes
    mov     rdi, rbx
    mov     rsi, r12
    mov     rdx, r13
    sub     rsp, 8
    and     rsp, -8
    mov     rcx, rsp
    call    str_u64_to_str
    mov     r10, [rsp]
    add     rsp, 8
    lea     rax, [r12 + r10]
    mov     byte [rax], 'B'
    add     r10, 1
    jmp     .sts_done

.sts_kib:
    mov     rax, rbx
    mov     rcx, SIZE_KiB
    xor     edx, edx
    div     rcx
    mov     rdi, rax
    mov     rsi, r12
    mov     rdx, r13
    sub     rsp, 8
    and     rsp, -8
    mov     rcx, rsp
    call    str_u64_to_str
    mov     r10, [rsp]
    add     rsp, 8
    lea     rax, [r12 + r10]
    mov     byte [rax],     'K'
    mov     byte [rax + 1], 'i'
    mov     byte [rax + 2], 'B'
    add     r10, 3
    jmp     .sts_done

.sts_mib:
    mov     rax, rbx
    mov     rcx, SIZE_MiB
    xor     edx, edx
    div     rcx
    mov     rdi, rax
    mov     rsi, r12
    mov     rdx, r13
    sub     rsp, 8
    and     rsp, -8
    mov     rcx, rsp
    call    str_u64_to_str
    mov     r10, [rsp]
    add     rsp, 8
    lea     rax, [r12 + r10]
    mov     byte [rax],     'M'
    mov     byte [rax + 1], 'i'
    mov     byte [rax + 2], 'B'
    add     r10, 3
    jmp     .sts_done

.sts_gib:
    mov     rax, rbx
    mov     rcx, SIZE_GiB
    xor     edx, edx
    div     rcx
    mov     rdi, rax
    mov     rsi, r12
    mov     rdx, r13
    sub     rsp, 8
    and     rsp, -8
    mov     rcx, rsp
    call    str_u64_to_str
    mov     r10, [rsp]
    add     rsp, 8
    lea     rax, [r12 + r10]
    mov     byte [rax],     'G'
    mov     byte [rax + 1], 'i'
    mov     byte [rax + 2], 'B'
    add     r10, 3
    jmp     .sts_done

.sts_tib:
    mov     rax, rbx
    mov     rcx, SIZE_TiB
    xor     edx, edx
    div     rcx
    mov     rdi, rax
    mov     rsi, r12
    mov     rdx, r13
    sub     rsp, 8
    and     rsp, -8
    mov     rcx, rsp
    call    str_u64_to_str
    mov     r10, [rsp]
    add     rsp, 8
    lea     rax, [r12 + r10]
    mov     byte [rax],     'T'
    mov     byte [rax + 1], 'i'
    mov     byte [rax + 2], 'B'
    add     r10, 3
    jmp     .sts_done

.sts_pib:
    mov     rax, rbx
    mov     rcx, SIZE_PiB
    xor     edx, edx
    div     rcx
    mov     rdi, rax
    mov     rsi, r12
    mov     rdx, r13
    sub     rsp, 8
    and     rsp, -8
    mov     rcx, rsp
    call    str_u64_to_str
    mov     r10, [rsp]
    add     rsp, 8
    lea     rax, [r12 + r10]
    mov     byte [rax],     'P'
    mov     byte [rax + 1], 'i'
    mov     byte [rax + 2], 'B'
    add     r10, 3

.sts_done:
    test    r14, r14
    jz      .sts_ok
    mov     [r14], r10

.sts_ok:
    pop_regs r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_size_to_str
%endif ; GUARD_LIB_STR_PARSE_SIZE_ASM
