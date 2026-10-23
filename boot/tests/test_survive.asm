; =============================================================================
; Utkarsha OS — boot/tests/test_survive.asm
; =============================================================================
; Test assertion for survive/ panic snapshot and CRC32 verification.
;
; Author:  Utkarsha Labs
; Target:  x86-64, long mode (64-bit)
; =============================================================================

%ifndef TEST_SURVIVE_ASM
%define TEST_SURVIVE_ASM

[BITS 64]

; =============================================================================
; test_survive — verify survive snapshot saving and CRC32 verification
; =============================================================================
test_survive:
    push rsi
    push rax
    push rbx
    push rcx
    push rdx

    mov rsi, msg_test_survive
    call uart_print_64

    ; Save hardware state to SURVIVE_PAGE
    call survive_snapshot_save

    ; Verify snapshot checksum
    call survive_checksum_verify
    cmp rax, 1
    jne .failed

    ; Panic wakeup writes diagnostics here before verification.  They are
    ; intentionally mutable and must not invalidate the pristine CPU state.
    mov rbx, [SURVIVE_PAGE + 0x800]
    mov rcx, [SURVIVE_PAGE + 0xA00]
    mov rax, 0x1122334455667788
    mov [SURVIVE_PAGE + 0x800], rax
    mov rax, 0x8877665544332211
    mov [SURVIVE_PAGE + 0xA00], rax
    call survive_checksum_verify
    cmp rax, 1
    jne .restore_failed
    mov [SURVIVE_PAGE + 0x800], rbx
    mov [SURVIVE_PAGE + 0xA00], rcx

    ; Conversely, one changed byte in the saved register/stack region must be
    ; detected. Restore it and prove the checksum becomes valid again.
    mov dl, [SURVIVE_PAGE + 0x20]
    xor byte [SURVIVE_PAGE + 0x20], 1
    call survive_checksum_verify
    test rax, rax
    jnz .restore_immutable_failed
    mov [SURVIVE_PAGE + 0x20], dl
    call survive_checksum_verify
    cmp rax, 1
    jne .failed

    mov rsi, msg_pass_survive
    call uart_print_64
    pop rdx
    pop rcx
    pop rbx
    pop rax
    pop rsi
    clc
    ret

.restore_immutable_failed:
    mov [SURVIVE_PAGE + 0x20], dl
    jmp .failed

.restore_failed:
    mov [SURVIVE_PAGE + 0x800], rbx
    mov [SURVIVE_PAGE + 0xA00], rcx

.failed:
    mov rsi, msg_fail_survive
    call uart_print_64
    pop rdx
    pop rcx
    pop rbx
    pop rax
    pop rsi
    stc
    ret

; =============================================================================
; Data (64-bit)
; =============================================================================
msg_test_survive:  db "TEST: Survive snapshot checksum validation... ", 0
msg_pass_survive:  db "PASS", 0x0D, 0x0A, 0
msg_fail_survive:  db "FAIL", 0x0D, 0x0A, 0

[BITS 16]

%endif ; TEST_SURVIVE_ASM
