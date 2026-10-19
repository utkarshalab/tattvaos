; =============================================================================
; File     : tests/unit/test_unit.asm
; Project  : Utkarsha VCS (vcs)
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Unit tests for core VCS modules.
; =============================================================================

%ifndef VCS_TEST_UNIT_ASM
%define VCS_TEST_UNIT_ASM

%include "include/vcs.inc"

bits 64

section .text

; -----------------------------------------------------------------------------
; test_unit_run — Run all unit tests
; Output: rax = 0 if all passed, nonzero if failed
; -----------------------------------------------------------------------------
global test_unit_run
test_unit_run:
    PROLOGUE_SAVE rbx

    call    test_core_arena
    test    rax, rax
    jnz     .failed

    call    test_core_bytes
    test    rax, rax
    jnz     .failed

    call    test_core_strings
    test    rax, rax
    jnz     .failed

    call    test_graph_bloom
    test    rax, rax
    jnz     .failed

    mov     rax, 0
    jmp .done

.failed:
    mov     rax, 1

.done:
    EPILOGUE_RESTORE rbx
    ret

section .text

; -----------------------------------------------------------------------------
; test_core_arena — Test arena allocator
; Output: rax = 0 on pass, 1 on fail
; -----------------------------------------------------------------------------
test_core_arena:
    PROLOGUE_SAVE rbx
    call    arena_init
    call    arena_create
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; test_core_bytes — Test byte operations
; Output: rax = 0 on pass, 1 on fail
; -----------------------------------------------------------------------------
test_core_bytes:
    PROLOGUE_SAVE rbx
    call    bytes_copy
    call    bytes_compare
    call    bytes_fill
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; test_core_strings — Test string operations
; Output: rax = 0 on pass, 1 on fail
; -----------------------------------------------------------------------------
test_core_strings:
    PROLOGUE_SAVE rbx
    call    str_len
    call    str_copy
    call    str_compare
    call    str_find_char
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; test_graph_bloom — Test bloom filter
; Output: rax = 0 on pass, 1 on fail
; -----------------------------------------------------------------------------
test_graph_bloom:
    PROLOGUE_SAVE rbx
    call    bloom_init
    call    bloom_add
    call    bloom_test
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

%endif ; VCS_TEST_UNIT_ASM