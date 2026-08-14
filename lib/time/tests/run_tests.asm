; =============================================================================
; lib/time/tests/run_tests.asm
; Time Library diagnostic test runner.
;
; Exercises TSC reads, CMOS RTC date sweep, monotonic timings, and delay offsets.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_TIME_TESTS_ASM
%define IO_TIME_TESTS_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/time/time.inc"

section .rodata
str_test_start:     db "TEST:STARTING_TIME_UNIT_TESTS", 0
str_tsc_pass:       db "TEST:TIME:TSC_OK", 0
str_rtc_pass:       db "TEST:TIME:RTC_OK", 0
str_delay_pass:     db "TEST:TIME:DELAY_OK", 0
str_all_pass:       db "TEST:TIME:ALL_PASS", 0

section .bss
alignb 8
test_tm:            resb tm_t_size

section .text

global time_run_unit_tests

extern console_milestone
extern tsc_read
extern tsc_calibrate
extern tsc_ns
extern rtc_read_time
extern time_monotonic
extern time_monotonic_ms
extern time_delay_ms

; =============================================================================
; time_run_unit_tests — Run diagnostics for the Time library
; Out: RAX = 0 on success, or negative error code on check failure
; =============================================================================
IO_FUNC time_run_unit_tests
    push    rbx
    push    rcx
    push    rdx

    ; 1. Start test milestone
    lea     rdi, [rel str_test_start]
    call    console_milestone

    ; =========================================================================
    ; Test Case 1: TSC Read & Calibration
    ; =========================================================================
    call    tsc_read
    test    rax, rax
    jz      .fail                   ; Ticks must be non-zero

    call    tsc_calibrate           ; Calibrates frequency
    test    rax, rax
    jz      .fail                   ; Frequency must be non-zero

    call    tsc_ns                  ; Elapsed nanoseconds
    test    rax, rax
    jz      .fail

    lea     rdi, [rel str_tsc_pass]
    call    console_milestone

    ; =========================================================================
    ; Test Case 2: CMOS RTC Wall Clock Read
    ; =========================================================================
    lea     rdi, [rel test_tm]
    call    rtc_read_time
    test    rax, rax
    jnz     .fail                   ; Reading RTC must succeed (0)

    ; Validate year sanity bounds (should be >= 2026)
    mov     rax, [rel test_tm + tm_t.year]
    cmp     rax, 2026
    jb      .fail

    ; Validate month sanity bounds (1-12)
    mov     rax, [rel test_tm + tm_t.month]
    cmp     rax, 1
    jb      .fail
    cmp     rax, 12
    ja      .fail

    lea     rdi, [rel str_rtc_pass]
    call    console_milestone

    ; =========================================================================
    ; Test Case 3: Delays and Monotonic clock increments
    ; =========================================================================
    call    time_monotonic_ms
    mov     rbx, rax                ; RBX = start ms

    mov     rdi, 10                 ; Delay 10 milliseconds
    call    time_delay_ms

    call    time_monotonic_ms       ; RAX = end ms
    sub     rax, rbx                ; RAX = elapsed ms
    
    ; Sanity check: elapsed milliseconds must be at least 8ms (with scheduling margin)
    cmp     rax, 8
    jb      .fail

    lea     rdi, [rel str_delay_pass]
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
    pop     rdx
    pop     rcx
    pop     rbx
    ret
IO_ENDFUNC time_run_unit_tests

%endif ; IO_TIME_TESTS_ASM
