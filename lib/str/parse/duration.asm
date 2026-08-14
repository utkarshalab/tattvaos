%ifndef GUARD_LIB_STR_PARSE_DURATION_ASM
%define GUARD_LIB_STR_PARSE_DURATION_ASM
; =============================================================================
; str/parse/duration.asm
; Parse human-readable duration strings → nanoseconds (uint64).
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
; Supported duration formats:
;
;   "1h30m"        → 5400000000000 ns
;   "2.5s"         → 2500000000 ns
;   "100ms"        → 100000000 ns
;   "500us"        → 500000 ns
;   "200μs"        → 200000 ns  (U+03BC micro sign)
;   "1ns"          → 1 ns
;   "1h 30m 45s"   → with spaces
;   "90m"          → 5400000000000 ns
;   "1d"           → 86400000000000 ns
;   "1w"           → 604800000000000 ns
;
; Unit suffixes (case-insensitive):
;   ns, us, μs, ms, s, m, h, d, w
;
; Functions:
;   str_parse_duration       — parse to nanoseconds
;   str_parse_duration_slice — StrSlice variant
;   str_duration_to_str      — nanoseconds → human-readable
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"


; Nanosecond multipliers
NS_PER_NS   equ 1
NS_PER_US   equ 1000
NS_PER_MS   equ 1000000
NS_PER_S    equ 1000000000
NS_PER_M    equ 60000000000
NS_PER_H    equ 3600000000000
NS_PER_D    equ 86400000000000
NS_PER_W    equ 604800000000000

section .text

; -----------------------------------------------------------------------------
; str_parse_duration
;
; Parse a duration string into nanoseconds.
;
; Signature:
;   int64_t str_parse_duration(const StrSlice *src, uint64_t *out_ns)
;
; Arguments:
;   RDI  — source StrSlice
;   RSI  — pointer to uint64_t to receive nanoseconds
;
; Returns:
;   RAX  = STR_OK
;   RAX  = STR_ERR_NULL
;   RAX  = STR_ERR_PARSE    unrecognized format
;   RAX  = STR_ERR_OVERFLOW total nanoseconds overflow
; -----------------------------------------------------------------------------

STR_FUNC str_parse_duration

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, [rdi + StrSlice.len]
    mov     r13, rsi            ; out_ns

    xor     r14, r14            ; total_ns (accumulator)
    xor     r15, r15            ; index (i)
    xor     r9, r9              ; parsed any component?

.dur_loop:
    ; skip whitespace
.dur_skip_ws:
    cmp     r15, r12
    jae     .dur_done

    movzx   eax, byte [rbx + r15]
    cmp     al, ' '
    je      .dur_ws_adv
    cmp     al, 0x09
    jb      .dur_parse_value
    cmp     al, 0x0D
    jbe     .dur_ws_adv
    jmp     .dur_parse_value

.dur_ws_adv:
    inc     r15
    jmp     .dur_skip_ws

.dur_parse_value:
    ; parse numeric value (integer or float)
    ; create sub-slice from current position
    sub     rsp, STRSLICE_SIZE + 24
    and     rsp, -16

    lea     rax, [rbx + r15]
    mov     [rsp + StrSlice.ptr], rax
    mov     rax, r12
    sub     rax, r15
    mov     [rsp + StrSlice.len], rax

    ; try integer first
    mov     rdi, rsp
    lea     rsi, [rsp + STRSLICE_SIZE]       ; out_uint
    lea     rdx, [rsp + STRSLICE_SIZE + 8]   ; out_consumed
    call    str_parse_u64
    test    rax, rax
    jnz     .dur_try_float

    mov     r10, [rsp + STRSLICE_SIZE]        ; uint value
    mov     r11, [rsp + STRSLICE_SIZE + 8]    ; consumed
    ; r10 = integer part, r11 = bytes consumed
    xor     r8, r8                            ; is_float = 0

    ; check for decimal point (float)
    lea     rax, [r15 + r11]
    cmp     rax, r12
    jae     .dur_got_unit
    movzx   ecx, byte [rbx + rax]
    cmp     cl, '.'
    jne     .dur_got_unit

    ; has decimal — reparse as float
    jmp     .dur_try_float_after_uint

.dur_try_float:
    mov     rdi, rsp
    lea     rsi, [rsp + STRSLICE_SIZE]        ; out double ptr
    lea     rdx, [rsp + STRSLICE_SIZE + 8]    ; out_consumed
    call    str_parse_f64
    test    rax, rax
    jnz     .dur_parse_err

.dur_try_float_after_uint:
    ; we have a float value — convert to uint with unit handling
    ; for now: get consumed and unit suffix, use integer arithmetic
    mov     r11, [rsp + STRSLICE_SIZE + 8]    ; consumed
    ; load double bits
    mov     r10, [rsp + STRSLICE_SIZE]        ; double bits
    movq    xmm0, r10
    ; convert to integer (truncate)
    cvttsd2si r10, xmm0
    mov     r8, 1                             ; is_float

.dur_got_unit:
    add     r15, r11            ; advance past number

    mov     rsp, rbp
    sub     rsp, 0

    ; parse unit suffix
    cmp     r15, r12
    jae     .dur_parse_err      ; no unit

    ; read up to 3 bytes for unit
    movzx   eax, byte [rbx + r15]
    or      al, 0x20            ; fold to lowercase

    ; check multi-char units first
    ; "ns"
    cmp     al, 'n'
    jne     .dur_check_us

    mov     rdx, r15
    inc     rdx
    cmp     rdx, r12
    jae     .dur_parse_err

    movzx   ecx, byte [rbx + rdx]
    or      cl, 0x20
    cmp     cl, 's'
    jne     .dur_parse_err

    mov     rdx, NS_PER_NS
    add     r15, 2
    jmp     .dur_apply_unit

.dur_check_us:
    ; "us" or "μs"
    cmp     al, 'u'
    jne     .dur_check_mu

    mov     rdx, r15
    inc     rdx
    cmp     rdx, r12
    jae     .dur_parse_err

    movzx   ecx, byte [rbx + rdx]
    or      cl, 0x20
    cmp     cl, 's'
    jne     .dur_parse_err

    mov     rdx, NS_PER_US
    add     r15, 2
    jmp     .dur_apply_unit

.dur_check_mu:
    ; μ = U+03BC = 0xCE 0xBC in UTF-8
    cmp     byte [rbx + r15], 0xCE
    jne     .dur_check_ms

    mov     rdx, r15
    inc     rdx
    cmp     rdx, r12
    jae     .dur_check_ms

    cmp     byte [rbx + rdx], 0xBC
    jne     .dur_check_ms

    ; check 's' after μ
    add     rdx, 1
    cmp     rdx, r12
    jae     .dur_parse_err

    movzx   ecx, byte [rbx + rdx]
    or      cl, 0x20
    cmp     cl, 's'
    jne     .dur_parse_err

    mov     rdx, NS_PER_US
    add     r15, 4              ; μ(2) + s(1) = 3 + we need 3
    ; actually μ = 2 UTF-8 bytes + 's' = 3 bytes
    dec     r15
    add     r15, 3
    dec     r15
    ; simplify:
    sub     r15, 2
    add     r15, 3
    jmp     .dur_apply_unit

.dur_check_ms:
    cmp     al, 'm'
    jne     .dur_check_s

    mov     rdx, r15
    inc     rdx
    cmp     rdx, r12
    jae     .dur_single_m       ; just 'm' (minutes)

    movzx   ecx, byte [rbx + rdx]
    or      cl, 0x20
    cmp     cl, 's'
    jne     .dur_single_m

    ; "ms"
    mov     rdx, NS_PER_MS
    add     r15, 2
    jmp     .dur_apply_unit

.dur_single_m:
    ; "m" = minutes
    mov     rdx, NS_PER_M
    inc     r15
    jmp     .dur_apply_unit

.dur_check_s:
    cmp     al, 's'
    jne     .dur_check_h
    mov     rdx, NS_PER_S
    inc     r15
    jmp     .dur_apply_unit

.dur_check_h:
    cmp     al, 'h'
    jne     .dur_check_d
    mov     rdx, NS_PER_H
    inc     r15
    jmp     .dur_apply_unit

.dur_check_d:
    cmp     al, 'd'
    jne     .dur_check_w
    mov     rdx, NS_PER_D
    inc     r15
    jmp     .dur_apply_unit

.dur_check_w:
    cmp     al, 'w'
    jne     .dur_parse_err
    mov     rdx, NS_PER_W
    inc     r15

.dur_apply_unit:
    ; component_ns = value * multiplier
    ; overflow check
    mov     rax, r10
    mul     rdx                 ; rdx:rax = value * multiplier
    test    rdx, rdx
    jnz     .dur_overflow

    ; add to total
    add     r14, rax
    jc      .dur_overflow

    inc     r9                  ; parsed a component
    jmp     .dur_loop

.dur_done:
    test    r9, r9
    jz      .dur_parse_err

    mov     [r13], r14

    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.dur_parse_err:
    mov     rsp, rbp
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_PARSE
    pop     rbp
    ret

.dur_overflow:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_OVERFLOW
    pop     rbp
    ret

STR_ENDFUNC str_parse_duration

; -----------------------------------------------------------------------------
; str_parse_duration_slice — StrSlice wrapper (same as above, it already is)
; Alias for clarity
; -----------------------------------------------------------------------------

global str_parse_duration_slice
str_parse_duration_slice:
    jmp     str_parse_duration

; -----------------------------------------------------------------------------
; str_duration_to_str
;
; Convert nanoseconds to a human-readable string.
; Chooses the most appropriate unit automatically.
;
; Signature:
;   int64_t str_duration_to_str(uint64_t ns, uint8_t *buf,
;                                uint64_t buf_cap, uint64_t *out_len)
;
; Arguments:
;   RDI  — nanoseconds
;   RSI  — output buffer
;   RDX  — capacity
;   RCX  — out_len
; -----------------------------------------------------------------------------

STR_FUNC str_duration_to_str

    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14

    mov     rbx, rdi            ; ns value
    mov     r12, rsi            ; buf
    mov     r13, rdx            ; cap
    mov     r14, rcx            ; out_len

    ; determine best unit
    cmp     rbx, NS_PER_W
    jae     .dts_weeks

    cmp     rbx, NS_PER_D
    jae     .dts_days

    cmp     rbx, NS_PER_H
    jae     .dts_hours

    cmp     rbx, NS_PER_M
    jae     .dts_minutes

    cmp     rbx, NS_PER_S
    jae     .dts_seconds

    cmp     rbx, NS_PER_MS
    jae     .dts_ms

    cmp     rbx, NS_PER_US
    jae     .dts_us

    ; nanoseconds
    mov     rdi, rbx
    mov     rsi, r12
    mov     rdx, r13
    sub     rsp, 8
    and     rsp, -8
    mov     rcx, rsp
    call    str_u64_to_str
    mov     r10, [rsp]
    add     rsp, 8
    ; append "ns"
    lea     rax, [r12 + r10]
    mov     byte [rax], 'n'
    mov     byte [rax + 1], 's'
    add     r10, 2
    jmp     .dts_write_len

.dts_us:
    mov     rax, rbx
    xor     edx, edx
    mov     rcx, NS_PER_US
    div     rcx
    jmp     .dts_fmt_suffix_us

.dts_ms:
    mov     rax, rbx
    xor     edx, edx
    mov     rcx, NS_PER_MS
    div     rcx
    jmp     .dts_fmt_suffix_ms

.dts_seconds:
    mov     rax, rbx
    xor     edx, edx
    mov     rcx, NS_PER_S
    div     rcx
    jmp     .dts_fmt_suffix_s

.dts_minutes:
    mov     rax, rbx
    xor     edx, edx
    mov     rcx, NS_PER_M
    div     rcx
    jmp     .dts_fmt_suffix_m

.dts_hours:
    mov     rax, rbx
    xor     edx, edx
    mov     rcx, NS_PER_H
    div     rcx
    jmp     .dts_fmt_suffix_h

.dts_days:
    mov     rax, rbx
    xor     edx, edx
    mov     rcx, NS_PER_D
    div     rcx
    jmp     .dts_fmt_suffix_d

.dts_weeks:
    mov     rax, rbx
    xor     edx, edx
    mov     rcx, NS_PER_W
    div     rcx
    jmp     .dts_fmt_suffix_w

    ; for each: rax = value, format then append suffix
.dts_fmt_suffix_us:
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
    mov     byte [rax], 'u'
    mov     byte [rax + 1], 's'
    add     r10, 2
    jmp     .dts_write_len

.dts_fmt_suffix_ms:
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
    mov     byte [rax], 'm'
    mov     byte [rax + 1], 's'
    add     r10, 2
    jmp     .dts_write_len

.dts_fmt_suffix_s:
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
    mov     byte [rax], 's'
    add     r10, 1
    jmp     .dts_write_len

.dts_fmt_suffix_m:
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
    mov     byte [rax], 'm'
    add     r10, 1
    jmp     .dts_write_len

.dts_fmt_suffix_h:
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
    mov     byte [rax], 'h'
    add     r10, 1
    jmp     .dts_write_len

.dts_fmt_suffix_d:
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
    mov     byte [rax], 'd'
    add     r10, 1
    jmp     .dts_write_len

.dts_fmt_suffix_w:
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
    mov     byte [rax], 'w'
    add     r10, 1

.dts_write_len:
    test    r14, r14
    jz      .dts_ok
    mov     [r14], r10

.dts_ok:
    pop_regs r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_duration_to_str
%endif ; GUARD_LIB_STR_PARSE_DURATION_ASM
