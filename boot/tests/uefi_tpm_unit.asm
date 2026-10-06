; Native userspace harness for boot/tpm/uefi_tpm.asm.
; Exercises the real LocateProtocol and HashLogExtendEvent call sites against
; Microsoft-x64 ABI mocks, including the packed EFI_TCG2_EVENT layout.

[BITS 64]
default rel

%include "boot/tpm/uefi_tpm.asm"

section .text
global _start
_start:
    lea rax, [rel boot_services]
    mov [rel system_table + SYS_TABLE_BOOT_SERVICES], rax
    lea rax, [rel fake_locate_protocol]
    mov [rel boot_services + BS_LOCATE_PROTOCOL], rax
    lea rax, [rel fake_hash_log_extend]
    mov [rel tcg2_interface + 16], rax

    lea rcx, [rel system_table]
    call uefi_tpm_init
    test rax, rax
    jnz .fail_1
    lea rax, [rel tcg2_interface]
    cmp [rel tcg2_protocol], rax
    jne .fail_1
    cmp dword [rel locate_calls], 1
    jne .fail_1

    lea rcx, [rel system_table]
    lea rdx, [rel measured_data]
    mov r8d, measured_data_end - measured_data
    mov r9d, 7
    call uefi_tpm_measure
    test rax, rax
    jnz .fail_2
    cmp dword [rel hash_calls], 1
    jne .fail_2
    cmp dword [rel tcg2_event + TCG2_EVENT_PCR_INDEX_OFF], 7
    jne .fail_2

    ; Invalid PCRs fail before invoking firmware.
    lea rcx, [rel system_table]
    lea rdx, [rel measured_data]
    mov r8d, measured_data_end - measured_data
    mov r9d, TCG2_MAX_PCR_INDEX + 1
    call uefi_tpm_measure
    mov r10, EFI_INVALID_PARAMETER
    cmp rax, r10
    jne .fail_3
    cmp dword [rel hash_calls], 1
    jne .fail_3

    ; A failed re-probe clears a previously published protocol pointer.
    lea rax, [rel fake_locate_failure]
    mov [rel boot_services + BS_LOCATE_PROTOCOL], rax
    lea rcx, [rel system_table]
    call uefi_tpm_init
    mov r10, EFI_NOT_FOUND
    cmp rax, r10
    jne .fail_4
    cmp qword [rel tcg2_protocol], 0
    jne .fail_4

    lea rcx, [rel system_table]
    lea rdx, [rel measured_data]
    mov r8d, measured_data_end - measured_data
    mov r9d, 4
    call uefi_tpm_measure
    mov r10, EFI_UNSUPPORTED
    cmp rax, r10
    jne .fail_5

    xor edi, edi
    jmp .exit
.fail_1:
    mov edi, 1
    jmp .exit
.fail_2:
    mov edi, 2
    jmp .exit
.fail_3:
    mov edi, 3
    jmp .exit
.fail_4:
    mov edi, 4
    jmp .exit
.fail_5:
    mov edi, 5
.exit:
    mov eax, 60
    syscall

; EFI_STATUS LocateProtocol(Guid, Registration, Interface).
fake_locate_protocol:
    inc dword [rel locate_calls]
    test rdx, rdx
    jnz .bad
    mov rax, 0x42BE7455607F766C
    cmp [rcx], rax
    jne .bad
    mov rax, 0x0F72B26DD7E40B93
    cmp [rcx + 8], rax
    jne .bad
    lea rax, [rel tcg2_interface]
    mov [r8], rax
    xor eax, eax
    ret
.bad:
    mov rax, EFI_INVALID_PARAMETER
    ret

fake_locate_failure:
    mov rax, EFI_NOT_FOUND
    ret

; EFI_STATUS HashLogExtendEvent(This, Flags, Data, Length, Event).
fake_hash_log_extend:
    inc dword [rel hash_calls]
    lea rax, [rel tcg2_interface]
    cmp rcx, rax
    jne .bad
    test rdx, rdx
    jnz .bad
    lea rax, [rel measured_data]
    cmp r8, rax
    jne .bad
    cmp r9, measured_data_end - measured_data
    jne .bad

    mov r10, [rsp + 40]
    lea rax, [rel tcg2_event]
    cmp r10, rax
    jne .bad
    cmp dword [r10], tcg2_event_end - tcg2_event
    jne .bad
    cmp dword [r10 + 4], tcg2_event_header_end - tcg2_event_header
    jne .bad
    cmp word [r10 + 8], 1
    jne .bad
    cmp dword [r10 + 10], 7
    jne .bad
    cmp dword [r10 + 14], 0x0D
    jne .bad

    lea r11, [rel expected_event]
    add r10, 18
    mov ecx, expected_event_end - expected_event
.event_loop:
    mov al, [r11]
    cmp [r10], al
    jne .bad
    inc r10
    inc r11
    dec ecx
    jnz .event_loop

    xor eax, eax
    ret
.bad:
    mov rax, EFI_INVALID_PARAMETER
    ret

section .data
align 8
measured_data:
    db 0x55, 0x4C, 0x46, 0, 2, 0, 0, 0
    dq 0x0123456789ABCDEF
measured_data_end:
expected_event:
    db "Tattva kernel", 0
expected_event_end:

section .bss align=16
system_table:  resb 128
boot_services: resb 384
tcg2_interface: resb 24
locate_calls:  resd 1
hash_calls:    resd 1
