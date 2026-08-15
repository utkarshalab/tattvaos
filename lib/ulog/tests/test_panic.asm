; =============================================================================
; Tattva OS — lib/ulog/tests/test_panic.asm
; =============================================================================
; panic_nmi_safe.asm's reentrancy guard — the one piece of ulog where a bug
; means a hang during an actual kernel panic, so it gets tested even though
; it's the part hardest to exercise realistically outside a real fault.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_TESTS_TEST_PANIC_ASM
%define LIB_ULOG_TESTS_TEST_PANIC_ASM

[BITS 64]

section .text

; -----------------------------------------------------------------------------
; ulog_test_panic — Output: RAX = 0 pass, -1 fail
; -----------------------------------------------------------------------------
global ulog_test_panic
ulog_test_panic:
    push rbx

    ; PANIC_MAX_REENTRY successive enters must all succeed
    mov ebx, 3                       ; matches PANIC_MAX_REENTRY
.enter_loop:
    test ebx, ebx
    jz .enter_done
    call panic_nmi_guard_enter
    test eax, eax
    jz .fail
    dec ebx
    jmp .enter_loop
.enter_done:

    ; one more, past the limit, must be denied
    call panic_nmi_guard_enter
    test eax, eax
    jnz .fail

    ; unwind back to zero depth
    call panic_nmi_guard_exit
    call panic_nmi_guard_exit
    call panic_nmi_guard_exit

    ; depth is back to 0 — a fresh enter must succeed again
    call panic_nmi_guard_enter
    test eax, eax
    jz .fail
    call panic_nmi_guard_exit

    xor rax, rax
    jmp .done

.fail:
    mov rax, -1

.done:
    pop rbx
    ret

%endif ; LIB_ULOG_TESTS_TEST_PANIC_ASM
