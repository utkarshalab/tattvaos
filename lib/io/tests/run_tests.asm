; =============================================================================
; lib/io/tests/run_tests.asm
; Diagnostic unit-testing harness for Tattva OS I/O Subsystem.
;
; Exercises the core safety properties, alignment constraints, memory fences,
; and buffer tracking logic of lib/io, broadcasting results over COM1.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_TESTS_RUN_TESTS_ASM
%define IO_TESTS_RUN_TESTS_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/io/io.inc"
%include "lib/io/error/codes.asm"

section .rodata
str_test_start:    db "TEST:STARTING_IO_UNIT_TESTS", 0
str_align_pass:    db "TEST:ALIGN_OK", 0
str_smap_pass:     db "TEST:SMAP_OK", 0
str_pin_pass:      db "TEST:PIN_OK", 0
str_fixed_pass:    db "TEST:FIXED_BUF_OK", 0
str_all_pass:      db "TEST:ALL_PASS", 0

section .text

global io_run_unit_tests

extern console_milestone
extern align_is_page_aligned
extern align_page_round_up
extern io_validate_user_buffer
extern buffer_pin
extern buffer_unpin
extern buffer_is_pinned
extern fixed_buf_register
extern fixed_buf_resolve
extern fixed_buf_unregister

; =============================================================================
; io_run_unit_tests — Main unit test runner entry point
; In : None
; Out: RAX = 0 on success, spins/halts on failure
; =============================================================================
IO_FUNC io_run_unit_tests
    push    rbx

    ; 1. Print test suite start marker
    lea     rdi, [rel str_test_start]
    call    console_milestone

    ; =========================================================================
    ; Test Case 1: Core Alignment Helpers
    ; =========================================================================
    mov     rdi, 0x1000             ; 4KB page aligned
    call    align_is_page_aligned
    cmp     rax, 1
    jne     .fail

    mov     rdi, 0x1005             ; Not page aligned
    call    align_is_page_aligned
    cmp     rax, 0
    jne     .fail

    mov     rdi, 0x1005             ; Round up to 0x2000
    call    align_page_round_up
    cmp     rax, 0x2000
    jne     .fail

    lea     rdi, [rel str_align_pass]
    call    console_milestone

    ; =========================================================================
    ; Test Case 2: SMAP User Pointer Boundary Checks
    ; =========================================================================
    mov     rdi, 0x0000700000000000 ; Valid user address range
    mov     rsi, 0x1000             ; 4KB size
    call    io_validate_user_buffer
    cmp     rax, 0
    jne     .fail

    mov     rdi, 0x0000800000000000 ; Exactly at user boundary
    mov     rsi, 0x1000
    call    io_validate_user_buffer
    cmp     rax, IO_ERR_BADARG
    jne     .fail

    mov     rdi, 0xFFFFFFFFFFFFFF00 ; Overflow check
    mov     rsi, 0x200
    call    io_validate_user_buffer
    cmp     rax, IO_ERR_BADARG
    jne     .fail

    lea     rdi, [rel str_smap_pass]
    call    console_milestone

    ; =========================================================================
    ; Test Case 3: Buffer Pinning Table Refcounts
    ; =========================================================================
    mov     rdi, 0x2000000          ; Virtual base address to pin
    mov     rsi, 4096               ; 1 page
    call    buffer_pin
    cmp     rax, 0
    jne     .fail

    mov     rdi, 0x2000000
    mov     rsi, 4096
    call    buffer_is_pinned
    cmp     rax, 1
    jne     .fail

    mov     rdi, 0x2000000
    mov     rsi, 4096
    call    buffer_unpin
    cmp     rax, 0
    jne     .fail

    mov     rdi, 0x2000000
    mov     rsi, 4096
    call    buffer_is_pinned
    cmp     rax, 0
    jne     .fail

    lea     rdi, [rel str_pin_pass]
    call    console_milestone

    ; =========================================================================
    ; Test Case 4: Pre-Registered Fixed Buffers
    ; =========================================================================
    mov     rdi, 0x3000000          ; Virtual base buffer
    mov     rsi, 0x1000000          ; Physical backing target address
    mov     rdx, 4096               ; Size 4KB
    call    fixed_buf_register
    cmp     rax, 0
    jl      .fail
    mov     rbx, rax                ; Save handle in RBX

    ; Resolve hot-path offset
    mov     rdi, rbx                ; Handle
    mov     rsi, 0x3000100          ; Target virtual offset
    call    fixed_buf_resolve
    cmp     rax, 0x1000100          ; Must match target physical + offset
    jne     .fail

    ; Cleanly unregister
    mov     rdi, rbx
    call    fixed_buf_unregister
    cmp     rax, 0
    jne     .fail

    lea     rdi, [rel str_fixed_pass]
    call    console_milestone

    ; 2. Broadcast overall test suite success milestone
    lea     rdi, [rel str_all_pass]
    call    console_milestone

    xor     rax, rax                ; All tests passed successfully
    pop     rbx
    ret

.fail:
    ; Lock system execution state on fail indicating check violation
    cli
.loop_halt:
    hlt
    jmp     .loop_halt
IO_ENDFUNC io_run_unit_tests

%endif ; IO_TESTS_RUN_TESTS_ASM
