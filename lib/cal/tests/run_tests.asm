; =============================================================================
; lib/cal/tests/run_tests.asm
; Calendar Library diagnostic test runner.
;
; Exercises leap years, Sakamoto weekday values, epoch translations, and ISO 8601 parsing.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_CAL_TESTS_ASM
%define IO_CAL_TESTS_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/cal/cal.inc"

section .rodata
str_test_start:     db "TEST:STARTING_CAL_UNIT_TESTS", 0
str_greg_pass:      db "TEST:CAL:GREGORIAN_OK", 0
str_epoch_pass:     db "TEST:CAL:EPOCH_OK", 0
str_iso_pass:       db "TEST:CAL:ISO8601_OK", 0
str_all_pass:       db "TEST:CAL:ALL_PASS", 0

; Expected ISO string for test datetime: 2026-07-19T11:15:53Z
str_expected_iso:   db "2026-07-19T11:15:53Z", 0

section .bss
align 8
test_tm1:           resb tm_t_size
test_tm2:           resb tm_t_size
test_tm3:           resb tm_t_size
iso_buf:            resb 32

section .text

global cal_run_unit_tests

extern console_milestone
extern cal_is_leap_year
extern cal_days_in_month
extern cal_weekday
extern cal_to_epoch
extern cal_from_epoch
extern cal_format_iso8601
extern cal_parse_iso8601

; =============================================================================
; cal_run_unit_tests — Run diagnostics for the Calendar library
; Out: RAX = 0 on success, or negative error code on check failure
; =============================================================================
IO_FUNC cal_run_unit_tests
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi

    ; 1. Start test milestone
    lea     rdi, [rel str_test_start]
    call    console_milestone

    ; =========================================================================
    ; Test Case 1: Gregorian Calculations
    ; =========================================================================
    ; 2020 should be a leap year (1)
    mov     rdi, 2020
    call    cal_is_leap_year
    cmp     rax, 1
    jne     .fail

    ; 2021 should not be a leap year (0)
    mov     rdi, 2021
    call    cal_is_leap_year
    cmp     rax, 0
    jne     .fail

    ; 2100 should not be a leap year (0)
    mov     rdi, 2100
    call    cal_is_leap_year
    cmp     rax, 0
    jne     .fail

    ; 2000 should be a leap year (1)
    mov     rdi, 2000
    call    cal_is_leap_year
    cmp     rax, 1
    jne     .fail

    ; Feb 2020 should have 29 days
    mov     rdi, 2020
    mov     rsi, 2
    call    cal_days_in_month
    cmp     rax, 29
    jne     .fail

    ; Feb 2021 should have 28 days
    mov     rdi, 2021
    mov     rsi, 2
    call    cal_days_in_month
    cmp     rax, 28
    jne     .fail

    ; Weekday calculation: 2026-07-19 is Sunday (0)
    mov     rdi, 2026
    mov     rsi, 7
    mov     rdx, 19
    call    cal_weekday
    cmp     rax, WEEKDAY_SUNDAY
    jne     .fail

    lea     rdi, [rel str_greg_pass]
    call    console_milestone

    ; =========================================================================
    ; Test Case 2: Epoch conversions
    ; =========================================================================
    ; Setup test datetime tm1: 2026-07-19 11:15:53
    lea     rbx, [rel test_tm1]
    mov     qword [rbx + tm_t.year], 2026
    mov     qword [rbx + tm_t.month], 7
    mov     qword [rbx + tm_t.day], 19
    mov     qword [rbx + tm_t.hour], 11
    mov     qword [rbx + tm_t.minute], 15
    mov     qword [rbx + tm_t.second], 53
    mov     qword [rbx + tm_t.nanosecond], 0

    ; Convert to epoch
    mov     rdi, rbx
    call    cal_to_epoch
    mov     rcx, rax                ; RCX = epoch seconds timestamp

    ; Convert epoch back to datetime tm2
    mov     rdi, rcx
    lea     rsi, [rel test_tm2]
    call    cal_from_epoch

    ; Verify tm2 fields match tm1
    lea     rbx, [rel test_tm1]
    lea     rdx, [rel test_tm2]
    
    mov     rax, [rbx + tm_t.year]
    cmp     rax, [rdx + tm_t.year]
    jne     .fail
    mov     rax, [rbx + tm_t.month]
    cmp     rax, [rdx + tm_t.month]
    jne     .fail
    mov     rax, [rbx + tm_t.day]
    cmp     rax, [rdx + tm_t.day]
    jne     .fail
    mov     rax, [rbx + tm_t.hour]
    cmp     rax, [rdx + tm_t.hour]
    jne     .fail
    mov     rax, [rbx + tm_t.minute]
    cmp     rax, [rdx + tm_t.minute]
    jne     .fail
    mov     rax, [rbx + tm_t.second]
    cmp     rax, [rdx + tm_t.second]
    jne     .fail

    lea     rdi, [rel str_epoch_pass]
    call    console_milestone

    ; =========================================================================
    ; Test Case 3: ISO 8601 Formatter & Parser
    ; =========================================================================
    ; Format tm1 to string
    lea     rdi, [rel test_tm1]
    lea     rsi, [rel iso_buf]
    call    cal_format_iso8601
    cmp     rax, 20                 ; Expect formatted string length 20
    jne     .fail

    ; Compare string to expected "2026-07-19T11:15:53Z"
    lea     rsi, [rel iso_buf]
    lea     rdi, [rel str_expected_iso]
.strcmp:
    movzx   al, byte [rdi]
    movzx   ah, byte [rsi]
    cmp     al, ah
    jne     .fail
    test    al, al
    jz      .strcmp_done
    inc     rdi
    inc     rsi
    jmp     .strcmp
.strcmp_done:

    ; Parse string back to tm3
    lea     rdi, [rel str_expected_iso]
    lea     rsi, [rel test_tm3]
    call    cal_parse_iso8601
    test    rax, rax
    jnz     .fail                   ; Expect 0 on success

    ; Verify tm3 fields match tm1
    lea     rbx, [rel test_tm1]
    lea     rdx, [rel test_tm3]

    mov     rax, [rbx + tm_t.year]
    cmp     rax, [rdx + tm_t.year]
    jne     .fail
    mov     rax, [rbx + tm_t.month]
    cmp     rax, [rdx + tm_t.month]
    jne     .fail
    mov     rax, [rbx + tm_t.day]
    cmp     rax, [rdx + tm_t.day]
    jne     .fail
    mov     rax, [rbx + tm_t.hour]
    cmp     rax, [rdx + tm_t.hour]
    jne     .fail
    mov     rax, [rbx + tm_t.minute]
    cmp     rax, [rdx + tm_t.minute]
    jne     .fail
    mov     rax, [rbx + tm_t.second]
    cmp     rax, [rdx + tm_t.second]
    jne     .fail

    lea     rdi, [rel str_iso_pass]
    call    console_milestone

    ; =========================================================================
    ; Test Suite Success
    ; =========================================================================
    lea     rdi, [rel str_all_pass]
    call    console_milestone

    xor     rax, rax                ; Return 0 (All tests passed)
    jmp     .done

.fail:
    mov     rax, -1                 ; Test failure error code

.done:
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret
IO_ENDFUNC cal_run_unit_tests

%endif ; IO_CAL_TESTS_ASM
