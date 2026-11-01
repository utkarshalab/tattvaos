; ============================================================================
; Unit Test — Formatting, Fixed Point, Time, SipHash
;             (src/core/fmt.asm, fixed.asm, time.asm, siphash.asm)
; ============================================================================
; test_misc_suite -> eax = failed cases (each case returns 0 / 1).
; fmt: decimal, hex, padding, zero, signed, a pointer, a string. fixed
; (Q16.16): conversions, rounding, multiply / divide (signs, fractions),
; sqrt, clamp, lerp. time: ns / ms, add (saturating), sub (0 below).
; siphash24: the reference vectors (key 00 .. 0f; messages of 0, 1, 8 and
; 15 bytes 00, 01, ...), verify.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

extern fmt_uint
extern fmt_int
extern fmt_ptr
extern fmt_str
extern fix_from_int
extern fix_to_int
extern fix_to_int_round
extern fix_mul
extern fix_div
extern fix_sqrt
extern fix_clamp
extern fix_lerp
extern ut_time_ns_to_ms
extern ut_time_ms_to_ns
extern ut_time_add_ns
extern ut_time_sub_ns
extern siphash24
extern siphash24_verify
extern memcmp

%define ONE 65536

section .text

global test_misc_suite
global test_misc_main
test_misc_suite:
test_misc_main:
    push rbx
    xor ebx, ebx
%macro CASE 1
    call %1
    add ebx, eax
%endmacro
    CASE tf_uint
    CASE tf_pad
    CASE tf_int
    CASE tf_ptr_str
    CASE tx_convert
    CASE tx_mul_div
    CASE tx_sqrt
    CASE tx_clamp_lerp
    CASE tt_convert
    CASE tt_add_sub
    CASE ts_vectors
    CASE ts_verify
    mov eax, ebx
    pop rbx
    ret

%macro FAIL_IF 1
    j%1 .fail
%endmacro
%macro PASS 0
    xor eax, eax
    add rsp, 8
    ret
.fail:
    mov eax, 1
    add rsp, 8
    ret
%endmacro

; the text written (rax bytes at out) equal to the string %1 -> jump .fail if not
%macro TEXT_IS 1
    jmp %%cmp
%%want: db %1
%%want_end:
%%cmp:
    cmp rax, %%want_end - %%want
    jne .fail
    lea rdi, [rel out]
    lea rsi, [rel %%want]
    mov edx, %%want_end - %%want
    call memcmp
    test rax, rax
    jnz .fail
%endmacro
; fmt_uint / fmt_int of value %2 in base %3, width %4, pad %5
%macro FMT 5
    lea rdi, [rel out]
    mov rsi, %2
    mov edx, %3
    mov ecx, %4
    mov r8d, %5
    call fmt_%1
%endmacro

tf_uint:
    sub rsp, 8
    FMT uint, 12345, 10, 0, 0
    TEXT_IS "12345"
    FMT uint, 0, 10, 0, 0
    TEXT_IS "0"
    FMT uint, 0xBEEF, 16, 0, 0
    TEXT_IS "BEEF"
    FMT uint, 5, 2, 0, 0
    TEXT_IS "101"
    mov rsi, -1
    lea rdi, [rel out]
    xor edx, edx                        ; base 0 means 10
    xor ecx, ecx
    xor r8d, r8d
    call fmt_uint
    TEXT_IS "18446744073709551615"
    PASS

tf_pad:
    sub rsp, 8
    FMT uint, 42, 10, 6, 0              ; pad 0 means a space
    TEXT_IS "    42"
    FMT uint, 7, 16, 4, '0'
    TEXT_IS "0007"
    FMT uint, 123456, 10, 3, '0'        ; wider than the width: not cut
    TEXT_IS "123456"
    PASS

tf_int:
    sub rsp, 8
    FMT int, -42, 10, 0, 0
    TEXT_IS "-42"
    FMT int, 42, 10, 0, 0
    TEXT_IS "42"
    FMT int, -5, 10, 4, '0'             ; the sign counted in the width
    TEXT_IS "-005"
    PASS

tf_ptr_str:
    sub rsp, 8
    lea rdi, [rel out]
    mov rsi, 0xDEADBEEF
    call fmt_ptr
    TEXT_IS "00000000DEADBEEF"
    lea rdi, [rel out]
    lea rsi, [rel s_hi]
    call fmt_str
    TEXT_IS "hi there"
    PASS

tx_convert:
    sub rsp, 8
    mov edi, 3
    call fix_from_int
    cmp rax, 3 * ONE
    FAIL_IF ne
    mov rdi, -2
    call fix_from_int
    cmp rax, -2 * ONE
    FAIL_IF ne
    mov edi, 3 * ONE + ONE / 2 + 1      ; 3.5 and a bit
    call fix_to_int
    cmp rax, 3
    FAIL_IF ne
    mov edi, 3 * ONE + ONE / 2
    call fix_to_int_round
    cmp rax, 4
    FAIL_IF ne
    mov edi, 3 * ONE + ONE / 2 - 1
    call fix_to_int_round
    cmp rax, 3
    FAIL_IF ne
    PASS

tx_mul_div:
    sub rsp, 8
    mov edi, 3 * ONE / 2                ; 1.5 * 2.25 = 3.375
    mov esi, 9 * ONE / 4
    call fix_mul
    cmp rax, 27 * ONE / 8
    FAIL_IF ne
    mov rdi, -3 * ONE                   ; -3 * 0.5 = -1.5
    mov esi, ONE / 2
    call fix_mul
    cmp rax, -3 * ONE // 2              ; // : NASM's signed divide
    FAIL_IF ne
    mov edi, 7 * ONE                    ; 7 / 2 = 3.5
    mov esi, 2 * ONE
    call fix_div
    cmp rax, 7 * ONE / 2
    FAIL_IF ne
    mov edi, ONE                        ; 1 / 4 = 0.25
    mov esi, 4 * ONE
    call fix_div
    cmp rax, ONE / 4
    FAIL_IF ne
    mov rdi, -9 * ONE                   ; -9 / 3 = -3
    mov esi, 3 * ONE
    call fix_div
    cmp rax, -3 * ONE
    FAIL_IF ne
    mov rdi, 30000 * ONE                ; large: 30000 / 0.5 = 60000
    mov esi, ONE / 2
    call fix_div
    mov rcx, 60000 * ONE                ; wider than a cmp immediate
    cmp rax, rcx
    FAIL_IF ne
    PASS

tx_sqrt:
    sub rsp, 8
    mov edi, 16 * ONE
    call fix_sqrt
    cmp rax, 4 * ONE
    FAIL_IF ne
    mov edi, ONE / 4                    ; sqrt 0.25 = 0.5
    call fix_sqrt
    cmp rax, ONE / 2
    FAIL_IF ne
    mov edi, 2 * ONE                    ; sqrt 2 = 1.41421 (92681 / 65536)
    call fix_sqrt
    cmp rax, 92681
    FAIL_IF ne
    xor edi, edi
    call fix_sqrt
    test rax, rax
    FAIL_IF nz
    PASS

tx_clamp_lerp:
    sub rsp, 8
    mov edi, 5 * ONE
    xor esi, esi
    mov edx, 2 * ONE
    call fix_clamp
    cmp rax, 2 * ONE
    FAIL_IF ne
    mov rdi, -1
    xor esi, esi
    mov edx, ONE
    call fix_clamp
    test rax, rax
    FAIL_IF nz
    mov edi, 10 * ONE                   ; 10 .. 20 at a quarter: 12.5
    mov esi, 20 * ONE
    mov edx, ONE / 4
    call fix_lerp
    cmp rax, 25 * ONE / 2
    FAIL_IF ne
    PASS

tt_convert:
    sub rsp, 8
    mov edi, 2500000                    ; 2.5 ms: 2
    call ut_time_ns_to_ms
    cmp rax, 2
    FAIL_IF ne
    mov edi, 7
    call ut_time_ms_to_ns
    cmp rax, 7000000
    FAIL_IF ne
    PASS

tt_add_sub:
    sub rsp, 8
    mov edi, 100
    mov esi, 23
    call ut_time_add_ns
    cmp rax, 123
    FAIL_IF ne
    mov rdi, -10
    mov esi, 100
    call ut_time_add_ns
    cmp rax, -1                         ; saturated
    FAIL_IF ne
    mov edi, 100
    mov esi, 23
    call ut_time_sub_ns
    cmp rax, 77
    FAIL_IF ne
    mov edi, 10
    mov esi, 23
    call ut_time_sub_ns
    test rax, rax
    FAIL_IF nz
    PASS

; siphash24 of the first %1 message bytes -> compared with %2
%macro SIP 2
    lea rdi, [rel sip_msg]
    mov esi, %1
    lea rdx, [rel sip_key]
    call siphash24
    mov rcx, %2
    cmp rax, rcx
    jne .fail
%endmacro

ts_vectors:
    sub rsp, 8
    SIP 0, 0x726fdb47dd0e0e31
    SIP 1, 0x74f839c593dc67fd
    SIP 8, 0x93f5f5799a932462
    SIP 15, 0xa129ca6149be45e5
    PASS

ts_verify:
    sub rsp, 8
    lea rdi, [rel sip_msg]
    mov esi, 15
    lea rdx, [rel sip_key]
    mov rcx, 0xa129ca6149be45e5
    call siphash24_verify
    cmp rax, 1
    FAIL_IF ne
    lea rdi, [rel sip_msg]
    mov esi, 15
    lea rdx, [rel sip_key]
    mov rcx, 0xa129ca6149be45e4
    call siphash24_verify
    test rax, rax
    FAIL_IF nz
    PASS

section .rodata
s_hi:       db "hi there", 0
sip_key:    db 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15
sip_msg:    db 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15

section .bss
out:        resb 128
