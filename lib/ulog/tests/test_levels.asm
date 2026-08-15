; =============================================================================
; Tattva OS — lib/ulog/tests/test_levels.asm
; =============================================================================
; level_module_map.asm's override table and level_parse.asm's string table —
; the two pieces of level/ most likely to break silently (an off-by-one in
; the MOD_COUNT mask, a typo in a token string) without a test noticing.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_TESTS_TEST_LEVELS_ASM
%define LIB_ULOG_TESTS_TEST_LEVELS_ASM

[BITS 64]

%include "lib/ulog/level/level_defs.inc"
%include "lib/ulog/module_ids.inc"

section .text

; -----------------------------------------------------------------------------
; ulog_test_levels — Output: RAX = 0 pass, -1 fail
; -----------------------------------------------------------------------------
global ulog_test_levels
ulog_test_levels:
    push rbx

    call level_module_map_init

    ; unset module reports LEVEL_NO_OVERRIDE
    mov di, MOD_KERNEL_SCHED
    call level_module_map_get
    cmp al, LEVEL_NO_OVERRIDE
    jne .fail

    ; set it, read it back
    mov di, MOD_KERNEL_SCHED
    mov sil, LVL_DEBUG
    call level_module_map_set
    mov di, MOD_KERNEL_SCHED
    call level_module_map_get
    cmp al, LVL_DEBUG
    jne .fail

    ; a different module is unaffected
    mov di, MOD_UNET_CORE
    call level_module_map_get
    cmp al, LEVEL_NO_OVERRIDE
    jne .fail

    ; level_parse round-trips every known token
    mov rdi, .tok_warn
    call level_parse
    cmp eax, LVL_WARN
    jne .fail

    mov rdi, .tok_garbage
    call level_parse
    cmp eax, LVL_DEFAULT
    jne .fail

    xor rax, rax
    jmp .done

.fail:
    mov rax, -1

.done:
    pop rbx
    ret

section .rodata
.tok_warn:    db "warn", 0
.tok_garbage: db "not_a_level", 0

%endif ; LIB_ULOG_TESTS_TEST_LEVELS_ASM
